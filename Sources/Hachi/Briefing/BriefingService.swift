import AppKit
import Foundation

/// Ringkasan pagi (sekali sehari saat Mac dipakai setelah jam yang diatur)
/// dan pertanyaan "masih mau dikerjakan?" untuk tugas lama tanpa tanggal.
@MainActor
final class BriefingService {
    private let store: TaskStore
    private let settings: AppSettings
    private let scheduler: ReminderScheduler
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(store: TaskStore, settings: AppSettings, scheduler: ReminderScheduler) {
        self.store = store
        self.settings = settings
        self.scheduler = scheduler
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.wake() }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    private func wake() {
        store.tick()
        // Pengingat yang lewat saat Mac tidur sudah dikirim sistem; jadwal sisanya disegarkan.
        scheduler.sync()
        check()
    }

    private static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func check(now: Date = Date()) {
        let calendar = Calendar.current
        let todayKey = Self.dayKey.string(from: now)
        guard settings.lastBriefingDay != todayKey,
              calendar.component(.hour, from: now) >= settings.briefingHour
        else { return }
        settings.lastBriefingDay = todayKey

        if settings.briefingEnabled {
            sendBriefing(now: now)
        }
        if settings.nudgeEnabled, let stale = store.staleTask() {
            store.markNudged(stale.id)
            scheduler.sendNow(
                id: "nudge-\(stale.id)",
                title: String(localized: "Still want to do this?"),
                body: String(localized: "\(stale.title) · added \(Formatting.duration(now.timeIntervalSince(stale.createdAt))) ago"),
                category: .nudge,
                taskID: stale.id
            )
        }
    }

    func sendBriefing(now: Date = Date()) {
        store.tick()
        let today = store.today.count
        let overdue = store.overdue.count
        var parts: [String] = []
        parts.append(today == 0 ? String(localized: "No tasks today") : String(localized: "Tasks today: \(today)"))
        if overdue > 0 { parts.append(String(localized: "Overdue: \(overdue)")) }
        let first = (store.overdue + store.today).first.map { String(localized: "First up: \($0.title)") }
        scheduler.sendNow(
            id: "briefing-\(Self.dayKey.string(from: now))",
            title: String(localized: "Good morning"),
            body: ([parts.joined(separator: " · ")] + [first].compactMap { $0 }).joined(separator: "\n"),
            category: .briefing
        )
    }
}
