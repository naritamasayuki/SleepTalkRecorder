import Foundation

/// App Store のアプリ内レビュー依頼を表示する適切なタイミングを判定するマネージャ
enum ReviewPromptManager {
    private static let lastPromptDateKey = "com.sleeptalkrecorder.lastReviewPromptDate"
    private static let minimumRecordingsCount = 3
    private static let minimumIntervalDays: TimeInterval = 30 * 24 * 60 * 60

    /// レビュー依頼を表示すべきタイミングかどうかを判定する
    static func shouldRequestReview(
        totalRecordingsCount: Int,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard totalRecordingsCount >= minimumRecordingsCount else { return false }

        if let lastDate = userDefaults.object(forKey: lastPromptDateKey) as? Date {
            return now.timeIntervalSince(lastDate) >= minimumIntervalDays
        }
        return true
    }

    /// レビュー依頼を表示した日時を記録する
    static func markPromptShown(at date: Date = Date(), userDefaults: UserDefaults = .standard) {
        userDefaults.set(date, forKey: lastPromptDateKey)
    }
}
