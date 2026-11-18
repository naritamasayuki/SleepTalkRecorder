import XCTest
@testable import SleepTalkRecorder

final class SleepTalkAnalyzerTests: XCTestCase {
    func testEmptyRecordingsReturnsZeroAnalysis() {
        let result = SleepTalkAnalyzer.analyze([])

        XCTAssertEqual(result.totalCount, 0)
        XCTAssertEqual(result.totalDuration, 0)
        XCTAssertEqual(result.averageDuration, 0)
        XCTAssertNil(result.maxPeakDecibels)
        XCTAssertNil(result.peakHour)
        XCTAssertEqual(result.hourlyBuckets.count, 24)
        XCTAssertTrue(result.topKeywords.isEmpty)
        XCTAssertTrue(result.insights.isEmpty)
    }

    func testAnalyzeAggregatesHoursVolumesAndKeywords() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!

        let date2AM = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 2, minute: 15)))
        let date3AM = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 3, minute: 40)))

        let items = [
            RecordingItem(fileName: "a.m4a", createdAt: date2AM, duration: 2.0, peakDecibels: -35.0, transcript: "明日も仕事だ"),
            RecordingItem(fileName: "b.m4a", createdAt: date2AM, duration: 4.0, peakDecibels: -20.0, transcript: "明日は休み"),
            RecordingItem(fileName: "c.m4a", createdAt: date3AM, duration: 3.0, peakDecibels: -10.0, transcript: nil)
        ]

        let result = SleepTalkAnalyzer.analyze(items, calendar: calendar)

        XCTAssertEqual(result.totalCount, 3)
        XCTAssertEqual(result.totalDuration, 9.0, accuracy: 0.001)
        XCTAssertEqual(result.averageDuration, 3.0, accuracy: 0.001)
        XCTAssertEqual(result.maxPeakDecibels ?? -999, -10.0, accuracy: 0.001)
        XCTAssertEqual(result.transcribedCount, 2)
        XCTAssertEqual(result.peakHour, 2)
        XCTAssertEqual(result.hourlyBuckets[2].count, 2)
        XCTAssertEqual(result.hourlyBuckets[3].count, 1)

        XCTAssertEqual(result.volumeBreakdown.quietCount, 1)
        XCTAssertEqual(result.volumeBreakdown.normalCount, 1)
        XCTAssertEqual(result.volumeBreakdown.loudCount, 1)

        XCTAssertEqual(result.topKeywords.first?.word, "明日")
        XCTAssertEqual(result.topKeywords.first?.count, 2)
        XCTAssertFalse(result.insights.isEmpty)
        XCTAssertEqual(result.primaryNeed?.type, .relief)
    }

    func testPsychologicalNeedDetectsRestRequest() {
        let items = [
            RecordingItem(fileName: "1.m4a", duration: 2.0, peakDecibels: -35.0, transcript: "もう眠い、疲れた、休みたい"),
            RecordingItem(fileName: "2.m4a", duration: 1.5, peakDecibels: -32.0, transcript: "帰りたいたいへんだ")
        ]

        let result = SleepTalkAnalyzer.analyze(items)
        XCTAssertEqual(result.primaryNeed?.type, .rest)
        XCTAssertTrue(result.primaryNeed?.matchedKeywords.contains("眠い") == true)
    }

    func testPsychologicalNeedDetectsEnglishKeywords() {
        let items = [
            RecordingItem(fileName: "en1.m4a", duration: 2.5, peakDecibels: -14.0, transcript: "work tomorrow deadline"),
            RecordingItem(fileName: "en2.m4a", duration: 2.0, peakDecibels: -18.0, transcript: "late for work")
        ]

        let result = SleepTalkAnalyzer.analyze(items)
        XCTAssertEqual(result.primaryNeed?.type, .relief)
        XCTAssertTrue(result.primaryNeed?.matchedKeywords.contains("work") == true)
    }

    func testPsychologicalNeedDetectsEnglishRestKeywords() {
        let items = [
            RecordingItem(fileName: "1.m4a", duration: 2.0, peakDecibels: -35.0, transcript: "I am so sleepy and tired"),
            RecordingItem(fileName: "2.m4a", duration: 1.5, peakDecibels: -32.0, transcript: "Need rest and break")
        ]

        let result = SleepTalkAnalyzer.analyze(items)
        XCTAssertEqual(result.primaryNeed?.type, .rest)
        XCTAssertTrue(result.primaryNeed?.matchedKeywords.contains("sleepy") == true)
        XCTAssertFalse(result.topKeywords.isEmpty)
        XCTAssertFalse(result.insights.isEmpty)
    }

    func testRecordingItemFormattedDateAdaptsToLocale() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 2, minute: 15, second: 30)))
        let item = RecordingItem(fileName: "a.m4a", createdAt: date, duration: 2.0, peakDecibels: -30.0)

        let jaText = item.formattedDate(locale: Locale(identifier: "ja_JP"))
        let enText = item.formattedDate(locale: Locale(identifier: "en_US"))

        XCTAssertNotEqual(jaText, enText)
        XCTAssertTrue(jaText.contains("月") || jaText.contains("/"))
        XCTAssertTrue(enText.contains("Nov"))
    }
}
