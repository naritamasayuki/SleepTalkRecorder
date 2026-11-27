import Foundation
import OSLog
import UserNotifications

/// 毎晩の就寝前に寝言モニタリングの開始を促すローカル通知を管理するサービス
enum BedtimeReminderManager {
    static let notificationIdentifier = "com.sleeptalkrecorder.bedtimeReminder"
    private static let logger = Logger(subsystem: "com.sleeptalkrecorder.app", category: "BedtimeReminderManager")

    /// 通知権限を確認・リクエストして許可されているか返す
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                logger.error("通知権限リクエストエラー: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// 指定した時・分で毎日の就寝リマインダー通知をスケジュールする
    @discardableResult
    static func scheduleDailyReminder(hour: Int, minute: Int) async -> Bool {
        let granted = await requestAuthorizationIfNeeded()
        guard granted else {
            cancelReminder()
            return false
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time for Sleep Monitor")
        content.body = String(localized: "Plug in your charger and start recording tonight's sleep talk.")
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = min(max(hour, 0), 23)
        dateComponents.minute = min(max(minute, 0), 59)

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            logger.info("就寝リマインダーを設定しました: \(dateComponents.hour ?? 0):\(dateComponents.minute ?? 0)")
            return true
        } catch {
            logger.error("就寝リマインダーの登録に失敗しました: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 登録済みの就寝リマインダー通知をキャンセルする
    static func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        logger.info("就寝リマインダーを解除しました")
    }

    /// 録音監視が割り込み後に復帰できなかった場合にユーザーへ知らせるローカル通知を送る
    static func sendInterruptionFailureNotification() {
        Task {
            await postImmediateNotification(
                identifier: "com.sleeptalkrecorder.interruptionFailure",
                title: String(localized: "Sleep Recording Interrupted"),
                body: String(localized: "Monitoring could not automatically resume after an interruption. Open the app to restart.")
            )
        }
    }

    /// ストレージ空き容量不足で監視を停止した場合にローカル通知を送る
    static func sendLowStorageStoppedNotification() {
        Task {
            await postImmediateNotification(
                identifier: "com.sleeptalkrecorder.lowStorageStopped",
                title: String(localized: "Sleep Recording Stopped"),
                body: String(localized: "Monitoring was stopped because device storage is running low.")
            )
        }
    }

    /// 自動終了タイマーで録音が完了した朝にサマリー通知を送る
    static func sendMorningSummaryNotification(detectedCount: Int) {
        Task {
            let body: String
            if detectedCount > 0 {
                body = String(localized: "Detected \(detectedCount) sleep-talk clip(s) overnight. Tap to listen and view your report.")
            } else {
                body = String(localized: "Overnight monitoring finished. No sleep talk was detected last night.")
            }
            await postImmediateNotification(
                identifier: "com.sleeptalkrecorder.morningSummary",
                title: String(localized: "Good Morning!"),
                body: body
            )
        }
    }

    private static func postImmediateNotification(identifier: String, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            logger.error("ローカル通知の送信に失敗しました: \(error.localizedDescription, privacy: .public)")
        }
    }
}
