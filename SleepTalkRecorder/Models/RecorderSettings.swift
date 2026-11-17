import Foundation

/// 自動録音の検知パラメータおよび画面動作の設定を保持するモデル
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

    static let `default` = RecorderSettings(
        thresholdDecibels: -35.0,
        silenceTimeoutSeconds: 3.0,
        minimumDurationSeconds: 0.8,
        preRollSeconds: 1.5,
        dimScreenDuringMonitoring: true
    )

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
            dimScreenDuringMonitoring: dimScreenDuringMonitoring
        )
    }
}
