import XCTest
@testable import SleepTalkRecorder

final class AmazonSleepGoodsServiceTests: XCTestCase {
    func testJapaneseLocaleIncludesAssociateTagAndAmazonCoJp() throws {
        let items = AmazonSleepGoodsService.recommendations(for: .rest)
        XCTAssertEqual(items.count, 3)

        let url = try XCTUnwrap(
            AmazonSleepGoodsService.searchURL(for: items[0], locale: Locale(identifier: "ja_JP"))
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.amazon.co.jp")
        XCTAssertEqual(components.path, "/s")

        let tag = components.queryItems?.first(where: { $0.name == "tag" })?.value
        let keyword = components.queryItems?.first(where: { $0.name == "k" })?.value
        XCTAssertEqual(tag, "shirokumacamp-22")
        XCTAssertEqual(keyword, items[0].searchKeywordJa)
    }

    func testEnglishLocaleUsesAmazonComWithoutJapanTag() throws {
        let items = AmazonSleepGoodsService.recommendations(for: .relief)
        let url = try XCTUnwrap(
            AmazonSleepGoodsService.searchURL(for: items[0], locale: Locale(identifier: "en_US"))
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "www.amazon.com")
        XCTAssertEqual(components.path, "/s")
        XCTAssertNil(components.queryItems?.first(where: { $0.name == "tag" }))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "k" })?.value, items[0].searchKeywordEn)
    }

    func testAllPsychologicalNeedsReturnRecommendations() {
        for need in PsychologicalNeedType.allCases {
            XCTAssertEqual(AmazonSleepGoodsService.recommendations(for: need).count, 3)
        }
        XCTAssertEqual(AmazonSleepGoodsService.recommendations(for: nil).count, 3)
    }
}
