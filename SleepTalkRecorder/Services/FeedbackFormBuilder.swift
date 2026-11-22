import Foundation
import UIKit

/// フィードバックの種別
enum FeedbackCategory: String, CaseIterable, Identifiable, Sendable {
    case bugReport
    case featureRequest
    case other

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .bugReport:
            return String(localized: "Bug Report")
        case .featureRequest:
            return String(localized: "Feature Request")
        case .other:
            return String(localized: "Other Feedback")
        }
    }

    var subjectTag: String {
        switch self {
        case .bugReport: return "[Bug]"
        case .featureRequest: return "[Feature]"
        case .other: return "[Feedback]"
        }
    }
}

/// フィードバックに添付する端末・アプリ環境情報
struct FeedbackDeviceInfo: Equatable, Sendable {
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let deviceModel: String
    let localeIdentifier: String

    @MainActor
    static var current: FeedbackDeviceInfo {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return FeedbackDeviceInfo(
            appVersion: version,
            buildNumber: build,
            osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            deviceModel: UIDevice.current.model,
            localeIdentifier: Locale.current.identifier
        )
    }

    var formattedBlock: String {
        """
        ---
        App: SleepTalk \(appVersion) (\(buildNumber))
        OS: \(osVersion)
        Device: \(deviceModel)
        Locale: \(localeIdentifier)
        """
    }
}

/// ユーザーからの要望・バグ報告の送信URLおよび本文を組み立てるビルダー
enum FeedbackFormBuilder {
    static let supportEmail = "doronko.narunaru@gmail.com"
    static let githubIssuesNewURL = "https://github.com/naritamasayuki/SleepTalkRecorder/issues/new"

    /// 送信用の件名と本文を組み立てる（メッセージが空の場合は nil）
    static func buildContent(
        category: FeedbackCategory,
        message: String,
        includeDeviceInfo: Bool,
        deviceInfo: FeedbackDeviceInfo
    ) -> (subject: String, body: String)? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let subject = "\(category.subjectTag) SleepTalk \(category.localizedTitle)"
        let body: String
        if includeDeviceInfo {
            body = "\(trimmed)\n\n\(deviceInfo.formattedBlock)"
        } else {
            body = trimmed
        }
        return (subject, body)
    }

    /// メールアプリ起動用の mailto URL を生成する
    static func makeMailtoURL(
        to recipient: String = supportEmail,
        category: FeedbackCategory,
        message: String,
        includeDeviceInfo: Bool,
        deviceInfo: FeedbackDeviceInfo
    ) -> URL? {
        guard let content = buildContent(
            category: category,
            message: message,
            includeDeviceInfo: includeDeviceInfo,
            deviceInfo: deviceInfo
        ) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: content.subject),
            URLQueryItem(name: "body", value: content.body)
        ]
        return components.url
    }

    /// GitHub Issues 新規作成ページ用の URL を生成する
    static func makeGitHubIssueURL(
        baseURL: String = githubIssuesNewURL,
        category: FeedbackCategory,
        message: String,
        includeDeviceInfo: Bool,
        deviceInfo: FeedbackDeviceInfo
    ) -> URL? {
        guard let content = buildContent(
            category: category,
            message: message,
            includeDeviceInfo: includeDeviceInfo,
            deviceInfo: deviceInfo
        ),
        var components = URLComponents(string: baseURL) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "title", value: content.subject),
            URLQueryItem(name: "body", value: content.body)
        ]
        return components.url
    }
}
