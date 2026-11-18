import AVFoundation
import Foundation
import OSLog
import Observation

/// 寝言の自動検知とバックグラウンド録音を制御するレコーダークラス
@MainActor
@Observable
final class SleepAudioRecorder {
    enum MonitoringState: Equatable, Sendable {
        case idle
        case monitoring
        case recording
        case interrupted
    }

    enum PermissionState: Equatable, Sendable {
        case undetermined
        case granted
        case denied
    }

    private(set) var state: MonitoringState = .idle
    private(set) var permissionState: PermissionState = .undetermined
    private(set) var currentDecibels: Float = -60.0
    private(set) var sessionStartTime: Date?
    private(set) var sessionRecordingCount: Int = 0
    private(set) var currentClipDuration: TimeInterval = 0
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

    init(store: RecordingStore, settings: RecorderSettings = .load()) {
        self.store = store
        self.settings = settings
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

    /// 寝言モニタリング（自動待機・録音）を開始する
    func startMonitoring() async {
        guard state == .idle, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        refreshPermissionState()
        if permissionState == .undetermined {
            let granted = await requestPermission()
            guard granted else {
                errorMessage = "マイクへのアクセスが許可されていないため、録音を開始できません。"
                return
            }
        } else if permissionState == .denied {
            errorMessage = "マイクへのアクセスが拒否されています。設定アプリからマイクの許可を有効にしてください。"
            return
        }

        if settings.transcribeForFileName {
            _ = await SpeechTranscriber.requestAuthorizationIfNeeded()
        }

        do {
            try configureAudioSession()
            try startAudioEngine()
            registerAudioNotifications()

            sessionStartTime = Date()
            sessionRecordingCount = 0
            currentClipDuration = 0
            state = .monitoring
            logger.info("寝言モニタリングを開始しました (しきい値: \(self.settings.thresholdDecibels) dBFS)")
        } catch {
            logger.error("モニタリング開始エラー: \(error.localizedDescription, privacy: .public)")
            errorMessage = "オーディオ録音の開始に失敗しました: \(error.localizedDescription)"
            cleanupEngine()
            state = .idle
        }
    }

    /// 寝言モニタリングを停止する
    func stopMonitoring() {
        guard state != .idle else { return }
        unregisterAudioNotifications()
        processor?.finalizeIfNeeded()
        cleanupEngine()
        deactivateAudioSession()

        state = .idle
        currentDecibels = -60.0
        currentClipDuration = 0
        sessionStartTime = nil
        logger.info("寝言モニタリングを停止しました")
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

    private func startAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(
                domain: "SleepAudioRecorder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "有効なマイク入力フォーマットを取得できませんでした。"]
            )
        }

        let streamProcessor = AudioStreamProcessor(
            inputFormat: inputFormat,
            directoryURL: store.directoryURL,
            settings: settings,
            onLevelUpdate: { [weak self] decibels, isRecording, clipDuration in
                Task { @MainActor [weak self] in
                    guard let self, self.state != .idle, self.state != .interrupted else { return }
                    let targetState: MonitoringState = isRecording ? .recording : .monitoring
                    if self.state != targetState {
                        self.state = targetState
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
                        if let transcript = await SpeechTranscriber.transcribe(fileURL: fileURL) {
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
            processor?.finalizeIfNeeded()
            cleanupEngine()
            if state != .idle {
                state = .interrupted
            }
        case .ended:
            logger.info("オーディオ割り込みが終了しました")
            guard state == .interrupted else { return }
            if options.contains(.shouldResume) {
                do {
                    try configureAudioSession()
                    try startAudioEngine()
                    state = .monitoring
                } catch {
                    logger.error("割り込み後の再開に失敗しました: \(error.localizedDescription, privacy: .public)")
                    errorMessage = "割り込み後の録音再開に失敗しました。"
                    state = .idle
                }
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        // オーディオ入力デバイスの抜き差し時に入力フォーマットが変わる可能性があるため再起動する
        if reason == .oldDeviceUnavailable || reason == .newDeviceAvailable {
            guard state == .monitoring || state == .recording else { return }
            logger.info("オーディオルート変更を検知したためエンジンを再構成します")
            processor?.finalizeIfNeeded()
            cleanupEngine()
            do {
                try startAudioEngine()
                state = .monitoring
            } catch {
                logger.error("ルート変更後の再起動に失敗しました: \(error.localizedDescription, privacy: .public)")
                errorMessage = "マイクの切り替え後に録音を再開できませんでした。"
                state = .idle
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
        onLevelUpdate: @escaping @Sendable (Float, Bool, TimeInterval) -> Void,
        onRecordingSaved: @escaping @Sendable (RecordingItem) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.inputFormat = inputFormat
        self.directoryURL = directoryURL
        self.detector = VoiceActivityDetector(settings: settings)
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
            writeBufferToActiveFile(buffer, duration: bufferDuration)
            onLevelUpdate(decibels, true, recordedDuration)

        case .finishRecording(let shouldSave):
            writeBufferToActiveFile(buffer, duration: bufferDuration)
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
            onError("録音ファイルの作成に失敗しました。")
            cleanupTempFile(at: fileURL)
            detector.reset()
        }
    }

    private func writeBufferToActiveFile(_ buffer: AVAudioPCMBuffer, duration: TimeInterval) {
        guard let activeFile else { return }
        do {
            try activeFile.write(from: buffer)
            recordedDuration += duration
        } catch {
            logger.error("音声バッファ書き込みエラー: \(error.localizedDescription, privacy: .public)")
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
