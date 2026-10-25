import Foundation
import UserNotifications

/// Menjadwalkan pengingat ke Notification Center macOS dan menjawab tombol di notifikasi.
/// Notifikasi dijadwalkan ke sistem, jadi tetap muncul walau aplikasi sedang tidak berjalan.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let store: TaskStore
    /// Membuka panel menu bar (klik notifikasi).
    var onOpen: (() -> Void)?

    /// macOS membatasi 64 notifikasi terjadwal per aplikasi.
    private static let maxScheduled = 50
    private static let taskPrefix = "task-"

    enum Action: String {
        case done = "DONE", snooze10 = "SNOOZE10", snooze60 = "SNOOZE60", tomorrow = "TOMORROW"
        case keep = "KEEP", delete = "DELETE"
    }

    enum Category: String {
        case task = "TASK", nudge = "NUDGE", briefing = "BRIEFING"
    }

    init(store: TaskStore) {
        self.store = store
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.task.rawValue, actions: [
                UNNotificationAction(identifier: Action.done.rawValue, title: String(localized: "Done")),
                UNNotificationAction(identifier: Action.snooze10.rawValue, title: String(localized: "Snooze 10 min")),
                UNNotificationAction(identifier: Action.snooze60.rawValue, title: String(localized: "Snooze 1 hour")),
                UNNotificationAction(identifier: Action.tomorrow.rawValue, title: String(localized: "Tomorrow")),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.nudge.rawValue, actions: [
                UNNotificationAction(identifier: Action.keep.rawValue, title: String(localized: "Still on it")),
                UNNotificationAction(identifier: Action.done.rawValue, title: String(localized: "Already done")),
                UNNotificationAction(identifier: Action.delete.rawValue, title: String(localized: "Delete"), options: [.destructive]),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.briefing.rawValue, actions: [], intentIdentifiers: []),
        ])
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// Menyamakan notifikasi terjadwal dengan isi database.
    func sync() {
        let now = Date()
        let upcoming = store.open
            .filter { ($0.remindAt ?? .distantPast) > now }
            .sorted { $0.remindAt! < $1.remindAt! }
            .prefix(Self.maxScheduled)

        Task {
            let pending = await center.pendingNotificationRequests()
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.taskPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            for task in upcoming {
                try? await center.add(request(for: task))
            }
        }
    }

    /// Notifikasi yang sudah tampil untuk tugas yang selesai/dihapus ikut dibersihkan.
    func clearDelivered(taskID: Int64) {
        center.removeDeliveredNotifications(withIdentifiers: [Self.taskPrefix + String(taskID)])
    }

    private func request(for task: TaskItem) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = Formatting.reminderBody(for: task, at: task.remindAt!)
        content.sound = .default
        content.categoryIdentifier = Category.task.rawValue
        content.userInfo = ["taskID": task.id]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: task.remindAt!)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: Self.taskPrefix + String(task.id), content: content, trigger: trigger)
    }

    func sendNow(id: String, title: String, body: String, category: Category, taskID: Int64? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.rawValue
        if let taskID { content.userInfo = ["taskID": taskID] }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let taskID = (response.notification.request.content.userInfo["taskID"] as? NSNumber)?.int64Value
        await MainActor.run { self.handle(action: action, taskID: taskID) }
    }

    private func handle(action: String, taskID: Int64?) {
        guard let taskID, let parsed = Action(rawValue: action) else {
            onOpen?()
            return
        }
        switch parsed {
        case .done: store.complete(taskID)
        case .snooze10: store.snooze(taskID, minutes: 10)
        case .snooze60: store.snooze(taskID, minutes: 60)
        case .tomorrow: store.moveToTomorrow(taskID)
        case .keep: store.touch(taskID)
        case .delete: store.delete(taskID)
        }
    }
}
