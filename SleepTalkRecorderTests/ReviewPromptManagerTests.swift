import XCTest
@testable import SleepTalkRecorder

final class ReviewPromptManagerTests: XCTestCase {
    func testDoesNotPromptBelowMinimumRecordingCount() {
        let suiteName = "ReviewPromptTest_Min_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(ReviewPromptManager.shouldRequestReview(totalRecordingsCount: 0, userDefaults: defaults))
        XCTAssertFalse(ReviewPromptManager.shouldRequestReview(totalRecordingsCount: 2, userDefaults: defaults))
        XCTAssertTrue(ReviewPromptManager.shouldRequestReview(totalRecordingsCount: 3, userDefaults: defaults))
    }

    func testCooldownPreventsFrequentPromptsAndAllowsAfter30Days() {
        let suiteName = "ReviewPromptTest_Cooldown_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(ReviewPromptManager.shouldRequestReview(totalRecordingsCount: 5, now: day0, userDefaults: defaults))

        ReviewPromptManager.markPromptShown(at: day0, userDefaults: defaults)

        let day10 = day0.addingTimeInterval(10 * 24 * 60 * 60)
        XCTAssertFalse(ReviewPromptManager.shouldRequestReview(totalRecordingsCount: 10, now: day10, userDefaults: defaults))

        let day31 = day0.addingTimeInterval(31 * 24 * 60 * 60)
        XCTAssertTrue(ReviewPromptManager.shouldRequestReview(totalRecordingsCount: 10, now: day31, userDefaults: defaults))
    }

    func testBedtimeReminderSettingsPersistenceAndClamping() {
        let suiteName = "BedtimeReminderSettingsTest_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = RecorderSettings(
            thresholdDecibels: -35.0,
            silenceTimeoutSeconds: 3.0,
            minimumDurationSeconds: 0.8,
            preRollSeconds: 1.5,
            dimScreenDuringMonitoring: true,
            transcribeForFileName: true,
            bedtimeReminderEnabled: true,
            bedtimeReminderHour: 29,
            bedtimeReminderMinute: -10
        )
        settings.save(to: defaults)

        let loaded = RecorderSettings.load(from: defaults)
        XCTAssertTrue(loaded.bedtimeReminderEnabled)
        XCTAssertEqual(loaded.bedtimeReminderHour, 23)
        XCTAssertEqual(loaded.bedtimeReminderMinute, 0)
    }
}
