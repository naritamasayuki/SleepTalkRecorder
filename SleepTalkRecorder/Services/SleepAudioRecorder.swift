import AVFoundation
import Foundation
import OSLog
import Observation

/// 1回の睡眠モニタリングセッションの結果を保持・永続化するサマリーモデル
struct SessionSummary: Codable, Equatable, Sendable {
    struct InterruptionInterval: Codable, Equatable, Sendable, Identifiable {
        let id: UUID
        let beganAt: Date
        let endedAt: Date?

        init(id: UUID = UUID(), beganAt: Date, endedAt: Date? = nil) {
            self.id = id
            self.beganAt = beganAt
            self.endedAt = endedAt
        }
    }

    let startedAt: Date
    let endedAt: Date
    let detectedCount: Int
    let endedAutomatically: Bool
    let endedDueToLowStorage: Bool
    let interruptions: [InterruptionInterval]

    private static let storageKey = "com.sleeptalkrecorder.pendingSessionSummary"

    static func loadPending(from userDefaults: UserDefaults = .standard) -> SessionSummary? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionSummary.self, from: data)
    }

    func savePending(to userDefaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) {
            userDefaults.set(data, forKey: Self.storageKey)
        }
    }

    static func clearPending(from userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: storageKey)
    }
}

/// 寝言の自動検知とバックグラウンド録音を制御するレコーダークラス
@MainActor
@Observable
final class SleepAudioRecorder {
    enum MonitoringState: Equatable, Sendable {
        case idle
        case countdown
        case monitoring
        case recording
        case interrupted
    }

    enum PermissionState: Equatable, Sendable {
        case undetermined
        case granted
        case denied
    }

    /// 最低限必要な空きストレージ容量（100 MB）
    static let minimumRequiredStorageBytes: Int64 = 100 * 1024 * 1024

    private(set) var state: MonitoringState = .idle
    private(set) var permissionState: PermissionState = .undetermined
    private(set) var currentDecibels: Float = -60.0
    private(set) var sessionStartTime: Date?
    private(set) var sessionRecordingCount: Int = 0
    private(set) var currentClipDuration: TimeInterval = 0
    private(set) var countdownEndTime: Date?
    private(set) var autoStopDate: Date?
    private(set) var isMicTesting: Bool = false
    private(set) var isCalibratingNoiseFloor: Bool = false
    private(set) var pendingSessionSummary: SessionSummary?
    var errorMessage: String?

    var settings: RecorderSettings {
        didSet {
            let clamped = settings.clamped()
            if settings != clamped {
                settings = clamped
            }
            settings.save()
            processor?.updateSettings(clamped)
        }
    }

    private let store: RecordingStore
    private let logger = Logger(subsystem: "com.sleeptalkrecorder.app", category: "SleepAudioRecorder")
    private var isStarting = false
    private var audioEngine: AVAudioEngine?
    private var processor: AudioStreamProcessor?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var countdownTask: Task<Void, Never>?
    private var autoStopTask: Task<Void, Never>?
    private var storageCheckTask: Task<Void, Never>?
    private var interruptionRetryTask: Task<Void, Never>?
    private var calibrationSamples: [Float] = []
    private var sessionInterruptions: [SessionSummary.InterruptionInterval] = []
    private var activeInterruptionStart: Date?

    init(store: RecordingStore, settings: RecorderSettings = .load()) {
        self.store = store
        self.settings = settings
        self.pendingSessionSummary = SessionSummary.loadPending()
        refreshPermissionState()
    }

    /// 現在のマイクアクセス権限を確認して状態を更新する
    func refreshPermissionState() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            permissionState = .granted
        case .denied:
            permissionState = .denied
        case .undetermined:
            permissionState = .undetermined
        @unknown default:
            permissionState = .undetermined
        }
    }

    /// マイクアクセス権限をリクエストする
    func requestPermission() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        permissionState = granted ? .granted : .denied
        return granted
    }

    /// 未確認の朝サマリーを既読にして閉じる
    func dismissPendingSessionSummary() {
        pendingSessionSummary = nil
        SessionSummary.clearPending()
    }

    // MARK: - マイクテスト・ノイズフロア自動調整

    /// 録音ファイルを保存せずにマイク入力レベルだけをリアルタイム確認するテストモードを開始する
    func startMicTest() async -> Bool {
        guard state == .idle else { return false }
        if isMicTesting { return true }

        refreshPermissionState()
        if permissionState == .undetermined {
            let granted = await requestPermission()
            guard granted else {
                errorMessage = String(localized: "Microphone access is not permitted, so recording cannot start.")
                return false
            }
        } else if permissionState == .denied {
            errorMessage = String(localized: "Microphone access is denied. Please enable microphone permission in Settings.")
            return false
        }

        do {
            try configureAudioSession()
            try startAudioEngine(detectionEnabled: false)
            isMicTesting = true
            logger.info("マイクテストを開始しました")
            return true
        } catch {
            logger.error("マイクテスト開始エラー: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "Failed to start audio recording: \(error.localizedDescription)")
            cleanupEngine()
            deactivateAudioSession()
            return false
        }
    }

    /// マイクテストを停止する
    func stopMicTest() {
        guard isMicTesting else { return }
        isMicTesting = false
        isCalibratingNoiseFloor = false
        calibrationSamples.removeAll()
        cleanupEngine()
        deactivateAudioSession()
        currentDecibels = -60.0
        logger.info("マイクテストを停止しました")
    }

    /// 部屋の静かな環境音を数秒間計測し、ノイズフロア + 8 dB をしきい値に自動設定する
    @discardableResult
    func calibrateAmbientNoise(durationSeconds: TimeInterval = 5.0) async -> Float? {
        guard !isCalibratingNoiseFloor else { return nil }
        let wasTesting = isMicTesting
        if !wasTesting {
            let started = await startMicTest()
            guard started else { return nil }
        }

        isCalibratingNoiseFloor = true
        calibrationSamples.removeAll()
        try? await Task.sleep(for: .seconds(durationSeconds))
        isCalibratingNoiseFloor = false

        guard !calibrationSamples.isEmpty else {
            if !wasTesting { stopMicTest() }
            return nil
        }

        let sorted = calibrationSamples.sorted()
        // 上位15%の一時的な物音を除外した85パーセンタイルを環境ノイズ基準にする
        let p85Index = min(sorted.count - 1, max(0, Int(Double(sorted.count) * 0.85)))
        let noiseFloor = sorted[p85Index]
        let recommended = min(max((noiseFloor + 8.0).rounded(), -55.0), -15.0)
        settings.thresholdDecibels = recommended
        logger.info("環境音キャリブレーション完了: ノイズフロア \(noiseFloor) dB -> 推奨しきい値 \(recommended) dB")
        return recommended
    }

    // MARK: - 寝言モニタリング制御

    /// 寝言モニタリング（自動待機・録音）を開始する
    func startMonitoring() async {
        guard state == .idle, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        if isMicTesting {
            stopMicTest()
        }

        refreshPermissionState()
        if permissionState == .undetermined {
            let granted = await requestPermission()
            guard granted else {
                errorMessage = String(localized: "Microphone access is not permitted, so recording cannot start.")
                return
            }
        } else if permissionState == .denied {
            errorMessage = String(localized: "Microphone access is denied. Please enable microphone permission in Settings.")
            return
        }

        guard hasSufficientStorage() else {
            errorMessage = String(localized: "Not enough free storage space to start overnight recording. Please free up at least 100 MB.")
            return
        }

        if settings.transcribeForFileName {
            _ = await SpeechTranscriber.requestAuthorizationIfNeeded()
        }

        // 開始遅延中でも画面ロック時にiOSにサスペンドされないよう、最初にオーディオセッションとエンジンを起動する
        let hasDelay = settings.startDelayMinutes > 0
        do {
            try configureAudioSession()
            try startAudioEngine(detectionEnabled: !hasDelay)
            registerAudioNotifications()
        } catch {
            logger.error("モニタリング開始エラー: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "Failed to start audio recording: \(error.localizedDescription)")
            cleanupEngine()
            deactivateAudioSession()
            state = .idle
            return
        }

        let now = Date()
        sessionStartTime = now
        sessionRecordingCount = 0
        currentClipDuration = 0
        sessionInterruptions = []
        activeInterruptionStart = nil
        startPeriodicStorageCheck()

        if hasDelay {
            let delaySeconds = TimeInterval(settings.startDelayMinutes * 60)
            let targetDate = now.addingTimeInterval(delaySeconds)
            countdownEndTime = targetDate
            state = .countdown
            logger.info("開始遅延タイマーを開始しました (\(self.settings.startDelayMinutes)分後・オーディオエンジン稼働維持)")

            countdownTask?.cancel()
            countdownTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delaySeconds))
                guard !Task.isCancelled else { return }
                self?.activateDetectionAfterCountdown()
            }
        } else {
            countdownEndTime = nil
            state = .monitoring
            scheduleAutoStopIfNeeded(from: now)
            logger.info("寝言モニタリングを開始しました (しきい値: \(self.settings.thresholdDecibels) dBFS)")
        }
    }

    /// 開始遅延カウントダウンをスキップして今すぐ音声監視を開始する
    func skipCountdownAndStartNow() {
        guard state == .countdown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        activateDetectionAfterCountdown()
    }

    /// 寝言モニタリングを停止する
    func stopMonitoring(endedAutomatically: Bool = false, endedDueToLowStorage: Bool = false) {
        guard state != .idle else { return }
        countdownTask?.cancel()
        countdownTask = nil
        autoStopTask?.cancel()
        autoStopTask = nil
        storageCheckTask?.cancel()
        storageCheckTask = nil
        interruptionRetryTask?.cancel()
        interruptionRetryTask = nil
        countdownEndTime = nil
        autoStopDate = nil

        unregisterAudioNotifications()
        processor?.finalizeIfNeeded()
        cleanupEngine()
        deactivateAudioSession()

        let finishedAt = Date()
        if let began = activeInterruptionStart {
            sessionInterruptions.append(.init(beganAt: began, endedAt: finishedAt))
            activeInterruptionStart = nil
        }

        let recordedCount = sessionRecordingCount
        if let startedAt = sessionStartTime {
            let shouldRecordSummary = recordedCount > 0 || endedAutomatically || endedDueToLowStorage || !sessionInterruptions.isEmpty
            if shouldRecordSummary {
                let summary = SessionSummary(
                    startedAt: startedAt,
                    endedAt: finishedAt,
                    detectedCount: recordedCount,
                    endedAutomatically: endedAutomatically,
                    endedDueToLowStorage: endedDueToLowStorage,
                    interruptions: sessionInterruptions
                )
                pendingSessionSummary = summary
                summary.savePending()
            }
        }

        state = .idle
        currentDecibels = -60.0
        currentClipDuration = 0
        sessionStartTime = nil
        sessionRecordingCount = 0
        sessionInterruptions = []

        if endedDueToLowStorage {
            BedtimeReminderManager.sendLowStorageStoppedNotification()
        } else if endedAutomatically {
            BedtimeReminderManager.sendMorningSummaryNotification(detectedCount: recordedCount)
        }

        logger.info("寝言モニタリングを停止しました (自動終了: \(endedAutomatically), 空き容量不足: \(endedDueToLowStorage), 検知件数: \(recordedCount))")
    }

    private func activateDetectionAfterCountdown() {
        guard state == .countdown else { return }
        countdownEndTime = nil
        processor?.setDetectionEnabled(true)
        state = .monitoring
        let now = Date()
        scheduleAutoStopIfNeeded(from: now)
        logger.info("開始遅延が終了したため音声検知を有効化しました")
    }

    private func scheduleAutoStopIfNeeded(from startDate: Date) {
        autoStopTask?.cancel()
        autoStopTask = nil
        autoStopDate = nil

        guard settings.autoStopHours > 0 else { return }
        let durationSeconds = TimeInterval(settings.autoStopHours * 3600)
        autoStopDate = startDate.addingTimeInterval(durationSeconds)
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(durationSeconds))
            guard !Task.isCancelled else { return }
            self?.logger.info("自動終了タイマーに到達したためモニタリングを停止します")
            self?.stopMonitoring(endedAutomatically: true)
        }
    }

    // MARK: - ストレージ空き容量チェック

    private func hasSufficientStorage() -> Bool {
        do {
            let values = try store.directoryURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage {
                return available >= Self.minimumRequiredStorageBytes
            }
        } catch {
            logger.warning("空き容量チェックに失敗しました: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }

    private func startPeriodicStorageCheck() {
        storageCheckTask?.cancel()
        storageCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.state != .idle else { break }
                if !self.hasSufficientStorage() {
                    self.logger.error("ストレージ空き容量が不足したためモニタリングを安全停止します")
                    self.errorMessage = String(localized: "Monitoring stopped because device storage is running low.")
                    self.stopMonitoring(endedAutomatically: true, endedDueToLowStorage: true)
                    break
                }
            }
        }
    }

    // MARK: - Private Setup

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        )
        try session.setActive(true)
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.warning("AVAudioSessionの非アクティブ化に失敗しました: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startAudioEngine(detectionEnabled: Bool) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(
                domain: "SleepAudioRecorder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Could not obtain a valid microphone input format.")]
            )
        }

        let streamProcessor = AudioStreamProcessor(
            inputFormat: inputFormat,
            directoryURL: store.directoryURL,
            settings: settings,
            detectionEnabled: detectionEnabled,
            onLevelUpdate: { [weak self] decibels, isRecording, clipDuration in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.isCalibratingNoiseFloor {
                        self.calibrationSamples.append(decibels)
                    }
                    if self.isMicTesting {
                        if abs(self.currentDecibels - decibels) >= 0.3 {
                            self.currentDecibels = decibels
                        }
                        return
                    }
                    guard self.state != .idle, self.state != .interrupted else { return }
                    if self.state != .countdown {
                        let targetState: MonitoringState = isRecording ? .recording : .monitoring
                        if self.state != targetState {
                            self.state = targetState
                        }
                    }
                    if abs(self.currentDecibels - decibels) >= 0.4 {
                        self.currentDecibels = decibels
                    }
                    if isRecording || self.currentClipDuration != 0 {
                        self.currentClipDuration = clipDuration
                    }
                }
            },
            onRecordingSaved: { [weak self] item in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.store.add(item)
                    self.sessionRecordingCount += 1

                    if self.settings.transcribeForFileName {
                        let fileURL = self.store.fileURL(for: item)
                        let allowServer = self.settings.allowServerSpeechRecognition
                        if let transcript = await SpeechTranscriber.transcribe(
                            fileURL: fileURL,
                            allowServerRecognition: allowServer
                        ) {
                            self.store.updateTranscript(for: item.id, transcript: transcript)
                        }
                    }
                }
            },
            onError: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.errorMessage = message
                }
            }
        )

        streamProcessor.installTap(on: inputNode, format: inputFormat)

        engine.prepare()
        try engine.start()

        self.processor = streamProcessor
        self.audioEngine = engine
    }

    private func cleanupEngine() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        processor = nil
    }

    // MARK: - Notifications

    private func registerAudioNotifications() {
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            Task { @MainActor [weak self] in
                self?.handleInterruption(type: type, options: options)
            }
        }

        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleRouteChange(reason: reason)
            }
        }
    }

    private func unregisterAudioNotifications() {
        let center = NotificationCenter.default
        if let interruptionObserver {
            center.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let routeChangeObserver {
            center.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
    }

    private func handleInterruption(type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            logger.info("オーディオ割り込みが発生しました")
            interruptionRetryTask?.cancel()
            interruptionRetryTask = nil
            processor?.finalizeIfNeeded()
            cleanupEngine()
            if state != .idle {
                if activeInterruptionStart == nil {
                    activeInterruptionStart = Date()
                }
                state = .interrupted
            }
        case .ended:
            logger.info("オーディオ割り込みが終了しました (shouldResume: \(options.contains(.shouldResume)))")
            guard state == .interrupted else { return }
            // shouldResume の有無にかかわらず段階的にリトライし、朝まで止まりっぱなしを防ぐ
            attemptResumeAfterInterruption(immediate: options.contains(.shouldResume))
        @unknown default:
            break
        }
    }

    private func attemptResumeAfterInterruption(immediate: Bool) {
        interruptionRetryTask?.cancel()
        let retryDelays: [TimeInterval] = immediate ? [0.5, 3.0, 8.0] : [2.0, 5.0, 10.0]

        interruptionRetryTask = Task { [weak self] in
            guard let self else { return }
            for (attempt, delay) in retryDelays.enumerated() {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, self.state == .interrupted else { return }

                let stillCountingDown = (self.countdownEndTime ?? .distantPast) > Date()
                do {
                    try self.configureAudioSession()
                    try self.startAudioEngine(detectionEnabled: !stillCountingDown)
                    if let began = self.activeInterruptionStart {
                        self.sessionInterruptions.append(.init(beganAt: began, endedAt: Date()))
                        self.activeInterruptionStart = nil
                    }
                    self.state = stillCountingDown ? .countdown : .monitoring
                    self.logger.info("割り込み後の自動復帰に成功しました (試行 \(attempt + 1) 回目)")
                    return
                } catch {
                    self.logger.warning("割り込み後の再開リトライ \(attempt + 1) 回目失敗: \(error.localizedDescription, privacy: .public)")
                }
            }

            // 全リトライ失敗時はローカル通知とエラーメッセージで必ずユーザーに知らせる
            self.logger.error("割り込み後の再開リトライがすべて失敗しました")
            self.errorMessage = String(localized: "Failed to resume recording after interruption.")
            BedtimeReminderManager.sendInterruptionFailureNotification()
        }
    }

    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        // オーディオ入力デバイスの抜き差し時に入力フォーマットが変わる可能性があるため再起動する
        if reason == .oldDeviceUnavailable || reason == .newDeviceAvailable {
            guard state == .monitoring || state == .recording || state == .countdown else { return }
            let wasCountdown = state == .countdown
            logger.info("オーディオルート変更を検知したためエンジンを再構成します")
            processor?.finalizeIfNeeded()
            cleanupEngine()
            do {
                try startAudioEngine(detectionEnabled: !wasCountdown)
                state = wasCountdown ? .countdown : .monitoring
            } catch {
                logger.error("ルート変更後の再起動に失敗しました: \(error.localizedDescription, privacy: .public)")
                errorMessage = String(localized: "Could not resume recording after audio route change.")
                stopMonitoring()
            }
        }
    }
}

// MARK: - オーディオスレッド・キュー処理

/// 専用のシリアルキュー上でPCMバッファ解析・リングバッファ管理・ファイル書き出しを行うプロセッサ
private final class AudioStreamProcessor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sleeptalkrecorder.audioprocessing", qos: .userInitiated)
    private let inputFormat: AVAudioFormat
    private let directoryURL: URL
    private let logger = Logger(subsystem: "com.sleeptalkrecorder.app", category: "AudioStreamProcessor")

    private var detector: VoiceActivityDetector
    private var ringBuffer: AudioRingBuffer<AVAudioPCMBuffer>
    private var isDetectionEnabled: Bool
    private var activeFile: AVAudioFile?
    private var activeFileURL: URL?
    private var activeFileName: String?
    private var recordingStartDate: Date?
    private var recordedDuration: TimeInterval = 0

    private let onLevelUpdate: @Sendable (Float, Bool, TimeInterval) -> Void
    private let onRecordingSaved: @Sendable (RecordingItem) -> Void
    private let onError: @Sendable (String) -> Void

    init(
        inputFormat: AVAudioFormat,
        directoryURL: URL,
        settings: RecorderSettings,
        detectionEnabled: Bool = true,
        onLevelUpdate: @escaping @Sendable (Float, Bool, TimeInterval) -> Void,
        onRecordingSaved: @escaping @Sendable (RecordingItem) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.inputFormat = inputFormat
        self.directoryURL = directoryURL
        self.detector = VoiceActivityDetector(settings: settings)
        self.isDetectionEnabled = detectionEnabled
        let maxPreRollFrames = Int(inputFormat.sampleRate * settings.preRollSeconds)
        self.ringBuffer = AudioRingBuffer(maxFrames: maxPreRollFrames)
        self.onLevelUpdate = onLevelUpdate
        self.onRecordingSaved = onRecordingSaved
        self.onError = onError
    }

    /// オーディオスレッドから呼ばれるタップブロックを非MainActorコンテキストで登録する
    func installTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) {
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let copied = buffer.copyPCMBuffer() else { return }
            self.enqueue(SendablePCMBuffer(buffer: copied))
        }
    }

    func setDetectionEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.isDetectionEnabled = enabled
            if !enabled {
                self.ringBuffer.clear()
            }
        }
    }

    func updateSettings(_ newSettings: RecorderSettings) {
        queue.async { [weak self] in
            guard let self else { return }
            self.detector.settings = newSettings
            self.ringBuffer.maxFrames = Int(self.inputFormat.sampleRate * newSettings.preRollSeconds)
        }
    }

    func enqueue(_ wrapped: SendablePCMBuffer) {
        queue.async { [weak self] in
            self?.processBuffer(wrapped.buffer)
        }
    }

    func finalizeIfNeeded() {
        queue.sync {
            guard detector.state == .recording else {
                ringBuffer.clear()
                return
            }
            let effectiveSpeech = detector.recordingDuration - detector.silenceDuration
            let shouldSave = effectiveSpeech >= detector.settings.minimumDurationSeconds
            let peak = detector.peakDecibels
            finishRecordingFile(shouldSave: shouldSave, peakDecibels: peak)
            detector.reset()
        }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)
        let decibels = VoiceActivityDetector.calculateDecibels(samples: samples)

        // 開始遅延中・マイクテスト中はレベル更新のみ行い、録音検知はスキップする
        guard isDetectionEnabled else {
            onLevelUpdate(decibels, false, 0)
            return
        }

        let bufferDuration = Double(frameLength) / inputFormat.sampleRate
        let previousPeak = detector.peakDecibels
        let action = detector.process(decibels: decibels, bufferDuration: bufferDuration)

        switch action {
        case .none:
            ringBuffer.append(buffer, frameCount: frameLength)
            onLevelUpdate(decibels, false, 0)

        case .startRecording:
            startRecordingFile(initialPreRoll: ringBuffer.drainAll(), triggerBuffer: buffer, bufferDuration: bufferDuration)
            onLevelUpdate(decibels, true, recordedDuration)

        case .continueRecording:
            let wrote = writeBufferToActiveFile(buffer, duration: bufferDuration)
            if !wrote {
                // 書き込み失敗時は現在までのクリップを確定し、異常状態をUIへ通知する
                finishRecordingFile(shouldSave: recordedDuration >= detector.settings.minimumDurationSeconds, peakDecibels: max(previousPeak, decibels))
                detector.reset()
                onLevelUpdate(decibels, false, 0)
            } else {
                onLevelUpdate(decibels, true, recordedDuration)
            }

        case .finishRecording(let shouldSave):
            _ = writeBufferToActiveFile(buffer, duration: bufferDuration)
            let peak = max(previousPeak, decibels)
            finishRecordingFile(shouldSave: shouldSave, peakDecibels: peak)
            onLevelUpdate(decibels, false, 0)
        }
    }

    private func startRecordingFile(
        initialPreRoll: [AVAudioPCMBuffer],
        triggerBuffer: AVAudioPCMBuffer,
        bufferDuration: TimeInterval
    ) {
        let now = Date()
        let fileName = "sleeptalk_\(Int(now.timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).m4a"
        let fileURL = directoryURL.appendingPathComponent(fileName)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(inputFormat.channelCount),
            AVEncoderBitRateKey: 64_000
        ]

        do {
            let file = try AVAudioFile(
                forWriting: fileURL,
                settings: outputSettings,
                commonFormat: inputFormat.commonFormat,
                interleaved: inputFormat.isInterleaved
            )

            var totalDuration: TimeInterval = 0
            for preBuffer in initialPreRoll {
                try file.write(from: preBuffer)
                totalDuration += Double(preBuffer.frameLength) / inputFormat.sampleRate
            }
            try file.write(from: triggerBuffer)
            totalDuration += bufferDuration

            activeFile = file
            activeFileURL = fileURL
            activeFileName = fileName
            recordingStartDate = now
            recordedDuration = totalDuration
        } catch {
            logger.error("録音ファイル作成・書き込みエラー: \(error.localizedDescription, privacy: .public)")
            onError(String(localized: "Failed to create recording file."))
            cleanupTempFile(at: fileURL)
            detector.reset()
        }
    }

    @discardableResult
    private func writeBufferToActiveFile(_ buffer: AVAudioPCMBuffer, duration: TimeInterval) -> Bool {
        guard let activeFile else { return false }
        do {
            try activeFile.write(from: buffer)
            recordedDuration += duration
            return true
        } catch {
            logger.error("音声バッファ書き込みエラー: \(error.localizedDescription, privacy: .public)")
            onError(String(localized: "An error occurred while writing audio data. Please check available storage."))
            return false
        }
    }

    private func finishRecordingFile(shouldSave: Bool, peakDecibels: Float) {
        let savedURL = activeFileURL
        let savedName = activeFileName
        let savedDate = recordingStartDate ?? Date()
        let savedDuration = recordedDuration

        // AVAudioFileを解放してファイルを確定させる
        activeFile = nil
        activeFileURL = nil
        activeFileName = nil
        recordingStartDate = nil
        recordedDuration = 0

        guard let savedURL, let savedName else { return }

        if shouldSave, savedDuration > 0 {
            let item = RecordingItem(
                fileName: savedName,
                createdAt: savedDate,
                duration: savedDuration,
                peakDecibels: peakDecibels
            )
            onRecordingSaved(item)
        } else {
            logger.debug("最小録音時間未満のためノイズとして破棄しました (\(savedDuration, format: .fixed(precision: 2))秒)")
            cleanupTempFile(at: savedURL)
        }
    }

    private func cleanupTempFile(at url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// 独立コピー済みのAVAudioPCMBufferをキュー間で安全に受け渡すためのSendableラッパー
private struct SendablePCMBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

private extension AVAudioPCMBuffer {
    /// オーディオコールバックの再利用バッファから独立したコピーを作成する
    func copyPCMBuffer() -> AVAudioPCMBuffer? {
        guard let copied = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        copied.frameLength = frameLength
        guard let src = floatChannelData, let dst = copied.floatChannelData else {
            return nil
        }
        let channels = Int(format.channelCount)
        let frames = Int(frameLength)
        for ch in 0..<channels {
            dst[ch].update(from: src[ch], count: frames)
        }
        return copied
    }
}
