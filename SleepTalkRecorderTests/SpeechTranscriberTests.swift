import XCTest
@testable import SleepTalkRecorder

final class SpeechTranscriberTests: XCTestCase {
    func testSanitizeFileNameRemovesForbiddenCharacters() {
        let input = "  おはよう/世界:テスト\n明日*も?よろしく  "
        let result = SpeechTranscriber.sanitizeFileName(input)
        XCTAssertEqual(result, "おはよう_世界_テスト_明日_も_よろしく")
    }

    func testSanitizeFileNameTruncatesToMaxLength() {
        let input = String(repeating: "あ", count: 40)
        let result = SpeechTranscriber.sanitizeFileName(input, maxLength: 24)
        XCTAssertEqual(result?.count, 24)
    }

    func testSanitizeFileNameReturnsNilForEmptyOrSymbolsOnly() {
        XCTAssertNil(SpeechTranscriber.sanitizeFileName("   \n\t  "))
        XCTAssertNil(SpeechTranscriber.sanitizeFileName("///:::..."))
    }
}
