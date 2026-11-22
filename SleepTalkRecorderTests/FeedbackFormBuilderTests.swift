import XCTest
@testable import SleepTalkRecorder

final class FeedbackFormBuilderTests: XCTestCase {
    private let sampleInfo = FeedbackDeviceInfo(
        appVersion: "1.0",
        buildNumber: "3",
        osVersion: "iOS 18.0",
        deviceModel: "iPhone",
        localeIdentifier: "ja_JP"
    )

    func testEmptyMessageReturnsNil() {
        XCTAssertNil(
            FeedbackFormBuilder.makeMailtoURL(
                category: .bugReport,
                message: "   \n ",
                includeDeviceInfo: true,
                deviceInfo: sampleInfo
            )
        )
        XCTAssertNil(
            FeedbackFormBuilder.makeGitHubIssueURL(
                category: .featureRequest,
                message: "",
                includeDeviceInfo: false,
                deviceInfo: sampleInfo
            )
        )
    }

    func testMakeMailtoURLIncludesEncodedSubjectBodyAndDeviceInfo() throws {
        let url = try XCTUnwrap(
            FeedbackFormBuilder.makeMailtoURL(
                to: "support@example.com",
                category: .bugReport,
                message: "録音が途中で止まりました",
                includeDeviceInfo: true,
                deviceInfo: sampleInfo
            )
        )

        XCTAssertEqual(url.scheme, "mailto")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "support@example.com")

        let subject = components.queryItems?.first(where: { $0.name == "subject" })?.value
        let body = components.queryItems?.first(where: { $0.name == "body" })?.value
        XCTAssertTrue(subject?.contains("[Bug]") == true)
        XCTAssertTrue(body?.contains("録音が途中で止まりました") == true)
        XCTAssertTrue(body?.contains("App: SleepTalk 1.0 (3)") == true)
    }

    func testMakeGitHubIssueURLExcludesDeviceInfoWhenDisabled() throws {
        let url = try XCTUnwrap(
            FeedbackFormBuilder.makeGitHubIssueURL(
                category: .featureRequest,
                message: "ダークテーマの色を増やしてほしい",
                includeDeviceInfo: false,
                deviceInfo: sampleInfo
            )
        )

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let title = components.queryItems?.first(where: { $0.name == "title" })?.value
        let body = components.queryItems?.first(where: { $0.name == "body" })?.value
        XCTAssertTrue(title?.contains("[Feature]") == true)
        XCTAssertEqual(body, "ダークテーマの色を増やしてほしい")
    }
}
