import Foundation

/// 録音された寝言クリップ1件のメタデータを表すモデル
struct RecordingItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var fileName: String
    let createdAt: Date
    let duration: TimeInterval
    let peakDecibels: Float
    var transcript: String?
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        fileName: String,
        createdAt: Date = Date(),
        duration: TimeInterval,
        peakDecibels: Float,
        transcript: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.duration = duration
        self.peakDecibels = peakDecibels
        self.transcript = transcript
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        peakDecibels = try container.decode(Float.self, forKey: .peakDecibels)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    /// 一覧表示用のタイトル（文字起こし結果があれば優先して返す）
    var displayTitle: String {
        if let transcript, !transcript.isEmpty {
            return transcript
        }
        return formattedDate
    }

    /// 録音長を「MM:SS」形式の文字列で返す
    var formattedDuration: String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 録音開始日時を端末のロケール設定に合わせてフォーマットして返す
    var formattedDate: String {
        formattedDate(locale: .autoupdatingCurrent)
    }

    /// 指定されたロケールで録音開始日時をフォーマットして返す
    func formattedDate(locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: createdAt)
    }

    /// 録音時刻のみを端末のロケール設定に合わせてフォーマットして返す
    var formattedTimeOnly: String {
        createdAt.formatted(date: .omitted, time: .standard)
    }
}
