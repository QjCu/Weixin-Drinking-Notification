import Foundation
import UserNotifications

struct ScheduleResult {
    var dates: [Date]
    var assignments: [NoteAssignment]
    var status: String
}

final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    override init() {
        super.init()
        center.delegate = self
    }
    func requestPermission() async throws {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        if !granted { throw AppError(message: "通知权限未开启，请到系统设置中允许通知") }
    }
    func rebuild(plan: ReminderPlan, notes: [FriendNote]) async throws -> ScheduleResult {
        let settings = await center.notificationSettings()
        let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        let dates = allowed ? ScheduleEngine.dates(plan: plan, after: Date()) : []
        let existing = await center.pendingNotificationRequests()
        var desired = Set<String>()
        var assignments: [NoteAssignment] = []
        // Remove the old queue first: it may already contain 60 requests, near iOS's limit.
        center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.identifier.hasPrefix("water-") }.map(\.identifier))
        do {
            for (index, date) in dates.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "到喝水时间了 💧"
                content.body = "趁课间休息，喝几口水吧。"
                content.sound = .default
                content.threadIdentifier = "water"
                if index < notes.count {
                    let note = notes[index]
                    content.body += "\n\(note.senderName)：\(note.text)"
                    assignments.append(NoteAssignment(noteID: note.id, date: date))
                }
                let components = ScheduleEngine.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let id = "water-\(Int(date.timeIntervalSince1970))"
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                desired.insert(id)
            }
        } catch {
            // Never retain a partly rebuilt queue with ambiguous note assignments.
            center.removePendingNotificationRequests(withIdentifiers: Array(desired))
            throw error
        }
        let status = !allowed ? "请开启通知权限" : !plan.enabled ? "提醒已暂停" : dates.isEmpty ? "暂无提醒，请检查学期日期和提醒计划" : "已安排 \(dates.count) 条提醒"
        return ScheduleResult(dates: dates, assignments: assignments, status: status)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
