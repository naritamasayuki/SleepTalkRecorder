import Foundation

/// 録音された寝言クリップ1件のメタデータを表すモデル
struct RecordingItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    let duration: TimeInterval
    let peakDecibels: Float

    init(
        id: UUID = UUID(),
        fileName: String,
        createdAt: Date = Date(),
        duration: TimeInterval,
        peakDecibels: Float
    ) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.duration = duration
        self.peakDecibels = peakDecibels
    }

    /// 録音長を「MM:SS」形式の文字列で返す
    var formattedDuration: String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 録音開始日時を日本語ロケールでフォーマットして返す
    var formattedDate: String {
        Self.dateFormatter.string(from: createdAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日(E) HH:mm:ss"
        return formatter
    }()
}
