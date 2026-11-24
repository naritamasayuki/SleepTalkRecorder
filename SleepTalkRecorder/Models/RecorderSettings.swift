import Foundation

/// 自動録音の検知パラメータおよび画面・通知・タイマー動作の設定を保持するモデル
struct RecorderSettings: Equatable, Codable, Sendable {
    /// 録音を開始する音量しきい値（dBFS: -60.0 〜 -5.0）
    var thresholdDecibels: Float
    /// 音声がしきい値を下回ってから録音を終了するまでの無音継続時間（秒）
    var silenceTimeoutSeconds: TimeInterval
    /// ノイズ誤検知を除外するための最小録音時間（秒）。この時間未満の録音は破棄される
    var minimumDurationSeconds: TimeInterval
    /// トリガー直前の音声をさかのぼって保存するプリロール時間（秒）
    var preRollSeconds: TimeInterval
    /// モニタリング中に画面を暗く（省電力表示に）するかどうか
    var dimScreenDuringMonitoring: Bool
    /// 録音後に寝言を文字起こしして音声ファイル名に設定するかどうか
    var transcribeForFileName: Bool
    /// 毎日の就寝リマインダー通知を有効にするかどうか
    var bedtimeReminderEnabled: Bool
    /// 就寝リマインダー通知の時（0〜23）
    var bedtimeReminderHour: Int
    /// 就寝リマインダー通知の分（0〜59）
    var bedtimeReminderMinute: Int
    /// 開始ボタン押下後に録音監視を始めるまでの遅延時間（分: 0〜60）
    var startDelayMinutes: Int
    /// 監視開始から自動で停止するまでの時間（時間: 0は無制限、1〜12）
    var autoStopHours: Int

    static let `default` = RecorderSettings(
        thresholdDecibels: -35.0,
        silenceTimeoutSeconds: 3.0,
        minimumDurationSeconds: 0.8,
        preRollSeconds: 1.5,
        dimScreenDuringMonitoring: true,
        transcribeForFileName: true,
        bedtimeReminderEnabled: false,
        bedtimeReminderHour: 23,
        bedtimeReminderMinute: 0,
        startDelayMinutes: 0,
        autoStopHours: 8
    )

    init(
        thresholdDecibels: Float,
        silenceTimeoutSeconds: TimeInterval,
        minimumDurationSeconds: TimeInterval,
        preRollSeconds: TimeInterval,
        dimScreenDuringMonitoring: Bool,
        transcribeForFileName: Bool = true,
        bedtimeReminderEnabled: Bool = false,
        bedtimeReminderHour: Int = 23,
        bedtimeReminderMinute: Int = 0,
        startDelayMinutes: Int = 0,
        autoStopHours: Int = 8
    ) {
        self.thresholdDecibels = thresholdDecibels
        self.silenceTimeoutSeconds = silenceTimeoutSeconds
        self.minimumDurationSeconds = minimumDurationSeconds
        self.preRollSeconds = preRollSeconds
        self.dimScreenDuringMonitoring = dimScreenDuringMonitoring
        self.transcribeForFileName = transcribeForFileName
        self.bedtimeReminderEnabled = bedtimeReminderEnabled
        self.bedtimeReminderHour = bedtimeReminderHour
        self.bedtimeReminderMinute = bedtimeReminderMinute
        self.startDelayMinutes = startDelayMinutes
        self.autoStopHours = autoStopHours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default
        thresholdDecibels = try container.decodeIfPresent(Float.self, forKey: .thresholdDecibels) ?? defaults.thresholdDecibels
        silenceTimeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .silenceTimeoutSeconds) ?? defaults.silenceTimeoutSeconds
        minimumDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .minimumDurationSeconds) ?? defaults.minimumDurationSeconds
        preRollSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .preRollSeconds) ?? defaults.preRollSeconds
        dimScreenDuringMonitoring = try container.decodeIfPresent(Bool.self, forKey: .dimScreenDuringMonitoring) ?? defaults.dimScreenDuringMonitoring
        transcribeForFileName = try container.decodeIfPresent(Bool.self, forKey: .transcribeForFileName) ?? defaults.transcribeForFileName
        bedtimeReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .bedtimeReminderEnabled) ?? defaults.bedtimeReminderEnabled
        bedtimeReminderHour = try container.decodeIfPresent(Int.self, forKey: .bedtimeReminderHour) ?? defaults.bedtimeReminderHour
        bedtimeReminderMinute = try container.decodeIfPresent(Int.self, forKey: .bedtimeReminderMinute) ?? defaults.bedtimeReminderMinute
        startDelayMinutes = try container.decodeIfPresent(Int.self, forKey: .startDelayMinutes) ?? defaults.startDelayMinutes
        autoStopHours = try container.decodeIfPresent(Int.self, forKey: .autoStopHours) ?? defaults.autoStopHours
    }

    private static let storageKey = "com.sleeptalkrecorder.settings"

    /// 指定された UserDefaults から設定を読み込む
    static func load(from userDefaults: UserDefaults = .standard) -> RecorderSettings {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(RecorderSettings.self, from: data) else {
            return .default
        }
        return decoded.clamped()
    }

    /// 指定された UserDefaults に設定を保存する
    func save(to userDefaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(clamped()) {
            userDefaults.set(data, forKey: Self.storageKey)
        }
    }

    /// 各パラメータが安全な範囲に収まるようクランプした値を返す
    func clamped() -> RecorderSettings {
        RecorderSettings(
            thresholdDecibels: min(max(thresholdDecibels, -60.0), -5.0),
            silenceTimeoutSeconds: min(max(silenceTimeoutSeconds, 1.0), 10.0),
            minimumDurationSeconds: min(max(minimumDurationSeconds, 0.2), 5.0),
            preRollSeconds: min(max(preRollSeconds, 0.0), 3.0),
            dimScreenDuringMonitoring: dimScreenDuringMonitoring,
            transcribeForFileName: transcribeForFileName,
            bedtimeReminderEnabled: bedtimeReminderEnabled,
            bedtimeReminderHour: min(max(bedtimeReminderHour, 0), 23),
            bedtimeReminderMinute: min(max(bedtimeReminderMinute, 0), 59),
            startDelayMinutes: min(max(startDelayMinutes, 0), 60),
            autoStopHours: min(max(autoStopHours, 0), 12)
        )
    }
}
