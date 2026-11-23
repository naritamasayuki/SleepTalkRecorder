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
}
