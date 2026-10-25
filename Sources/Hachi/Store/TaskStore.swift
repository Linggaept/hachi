import Foundation
import TodoParser

/// Sumber data tugas. Semua perubahan lewat sini, lalu `onChange` dipanggil (menjadwalkan ulang pengingat).
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    /// Diperbarui berkala supaya label "terlambat" dan "30 menit lagi" ikut bergeser.
    @Published private(set) var now = Date()

    var onChange: (() -> Void)?

    let settings: AppSettings
    private let db: Database
    private var calendar: Calendar { settings.parser.calendar }
    private var timer: Timer?

    /// Tugas selesai yang dimuat untuk daftar "Selesai".
    static let doneWindowDays = 30
    static let staleDays = 14

    nonisolated static var databaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hachi", isDirectory: true)
            .appendingPathComponent("todo.sqlite")
    }

    init(settings: AppSettings, url: URL = TaskStore.databaseURL) throws {
        self.settings = settings
        db = try Database(url: url)
        try migrate()
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func tick() {
        now = Date()
    }

    // MARK: - Kelompok

    var open: [TaskItem] { tasks.filter { !$0.isDone } }

    var overdue: [TaskItem] { open.filter { $0.isOverdue(now: now, calendar: calendar) }.sorted(by: Self.byDue) }

    var today: [TaskItem] {
        open.filter { task in
            guard let due = task.due, !task.isOverdue(now: now, calendar: calendar) else { return false }
            return calendar.isDate(due, inSameDayAs: now)
        }.sorted(by: Self.byDue)
    }

    var upcoming: [TaskItem] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return open.filter { ($0.due ?? .distantPast) >= tomorrow }.sorted(by: Self.byDue)
    }

    var someday: [TaskItem] { open.filter { $0.due == nil }.sorted { $0.createdAt > $1.createdAt } }

    var done: [TaskItem] { tasks.filter(\.isDone).sorted { $0.completedAt! > $1.completedAt! } }

    var doneTodayCount: Int { done.filter { calendar.isDate($0.completedAt!, inSameDayAs: now) }.count }

    private static func byDue(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch (a.due, b.due) {
        case let (x?, y?) where x != y:
            return x < y
        case _ where a.allDay != b.allDay:
            return a.allDay
        default:
            return a.createdAt < b.createdAt
        }
    }

    func task(_ id: Int64) -> TaskItem? { tasks.first { $0.id == id } }

    /// Tugas tanpa tanggal yang lama tidak disentuh dan belum ditanyakan lagi.
    func staleTask() -> TaskItem? {
        let limit = now.addingTimeInterval(-Double(Self.staleDays) * 86400)
        return someday
            .filter { $0.updatedAt < limit && ($0.lastNudgedAt ?? .distantPast) < limit }
            .min { $0.updatedAt < $1.updatedAt }
    }

    // MARK: - Ubah

    @discardableResult
    func add(_ draft: TaskDraft) -> Int64? {
        let stamp = Date()
        let saved = perform {
            try insert(draft, createdAt: stamp)
            return db.lastInsertID
        }
        return saved
    }

    func update(_ id: Int64, with draft: TaskDraft) {
        perform {
            try db.execute(
                """
                UPDATE tasks SET title = ?, notes = ?, due = ?, all_day = ?, remind_offset = ?, remind_at = ?,
                    repeat_rule = ?, updated_at = ? WHERE id = ?
                """,
                [
                    .text(draft.title), .string(draft.notes.isEmpty ? nil : draft.notes), .date(draft.due),
                    .int(draft.allDay ? 1 : 0), .number(draft.remindOffset),
                    .date(reminderDate(due: draft.due, allDay: draft.allDay, offset: draft.remindOffset)),
                    .string(draft.rule?.storage), .date(Date()), .int(id),
                ]
            )
        }
    }

    /// Menandai selesai. Tugas berulang langsung dibuatkan jadwal berikutnya.
    func complete(_ id: Int64) {
        guard let task = task(id), !task.isDone else { return }
        let stamp = Date()
        perform {
            try db.transaction {
                var spawned: Int64?
                if let rule = task.rule {
                    let base = task.due ?? calendar.startOfDay(for: stamp)
                    let next = task.allDay
                        ? rule.nextDay(after: base, notBeforeDayOf: stamp, calendar: calendar)
                        : rule.next(after: base, notBefore: stamp, calendar: calendar)
                    var draft = TaskDraft(task: task)
                    draft.due = next
                    try insert(draft, createdAt: stamp)
                    spawned = db.lastInsertID
                }
                try db.execute(
                    "UPDATE tasks SET completed_at = ?, spawned_id = ?, updated_at = ? WHERE id = ?",
                    [.date(stamp), spawned.map { .int($0) } ?? .null, .date(stamp), .int(id)]
                )
            }
        }
    }

    /// Batal selesai. Jadwal berikutnya yang belum disentuh ikut dibuang.
    func uncomplete(_ id: Int64) {
        guard let task = task(id), task.isDone else { return }
        perform {
            try db.transaction {
                if let spawned = task.spawnedID {
                    try db.execute("DELETE FROM tasks WHERE id = ? AND completed_at IS NULL", [.int(spawned)])
                }
                try db.execute(
                    "UPDATE tasks SET completed_at = NULL, spawned_id = NULL, updated_at = ? WHERE id = ?",
                    [.date(Date()), .int(id)]
                )
            }
        }
    }

    func delete(_ id: Int64) {
        perform { try db.execute("DELETE FROM tasks WHERE id = ?", [.int(id)]) }
    }

    func snooze(_ id: Int64, minutes: Int) {
        perform {
            try db.execute(
                "UPDATE tasks SET remind_at = ?, updated_at = ? WHERE id = ?",
                [.date(Date().addingTimeInterval(Double(minutes) * 60)), .date(Date()), .int(id)]
            )
        }
    }

    /// Pindah ke besok, jam tetap sama. Tugas tanpa tanggal menjadi tugas seharian besok.
    func moveToTomorrow(_ id: Int64) {
        guard let task = task(id) else { return }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        var draft = TaskDraft(task: task)
        if let due = task.due {
            let time = calendar.dateComponents([.hour, .minute], from: due)
            draft.due = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: tomorrow)
        } else {
            draft.due = tomorrow
            draft.allDay = true
        }
        update(id, with: draft)
    }

    func markNudged(_ id: Int64) {
        perform { try db.execute("UPDATE tasks SET last_nudged_at = ? WHERE id = ?", [.date(Date()), .int(id)]) }
    }

    /// Tugas yang "masih mau dikerjakan" dianggap baru disentuh.
    func touch(_ id: Int64) {
        perform {
            try db.execute("UPDATE tasks SET updated_at = ?, last_nudged_at = ? WHERE id = ?", [.date(Date()), .date(Date()), .int(id)])
        }
    }

    /// Pengingat untuk tugas: tugas seharian diingatkan dari jam pagi di Pengaturan.
    func reminderDate(due: Date?, allDay: Bool, offset: Double?) -> Date? {
        guard let due, let offset else { return nil }
        let base = allDay
            ? calendar.date(bySettingHour: settings.morningHour, minute: 0, second: 0, of: due)!
            : due
        return base.addingTimeInterval(-offset)
    }

    // MARK: - Ekspor / impor

    func exportJSON() throws -> Data {
        let all = try db.query("SELECT \(Self.columns) FROM tasks ORDER BY id", row: Self.decode)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(all)
    }

    /// Menambahkan tugas dari berkas ekspor. Tugas yang sudah ada (judul + waktu dibuat sama) dilewati.
    @discardableResult
    func importJSON(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let incoming = try decoder.decode([TaskItem].self, from: data)
        let existing = try db.query("SELECT title, created_at FROM tasks") { row in
            "\(row.text(0) ?? "")|\(Int(row.double(1) ?? 0))"
        }
        var known = Set(existing)
        var added = 0
        try db.transaction {
            for task in incoming {
                let key = "\(task.title)|\(Int(task.createdAt.timeIntervalSince1970))"
                guard !known.contains(key) else { continue }
                known.insert(key)
                try db.execute(
                    """
                    INSERT INTO tasks (title, notes, due, all_day, remind_offset, remind_at, repeat_rule,
                        completed_at, created_at, updated_at, last_nudged_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(task.title), .string(task.notes), .date(task.due), .int(task.allDay ? 1 : 0),
                        .number(task.remindOffset), .date(task.remindAt), .string(task.repeatRule),
                        .date(task.completedAt), .date(task.createdAt), .date(task.updatedAt), .date(task.lastNudgedAt),
                    ]
                )
                added += 1
            }
        }
        reload()
        onChange?()
        return added
    }

    // MARK: - Database

    private static let columns =
        "id, title, notes, due, all_day, remind_offset, remind_at, repeat_rule, completed_at, spawned_id, created_at, updated_at, last_nudged_at"

    private static func decode(_ row: Database.Row) -> TaskItem {
        TaskItem(
            id: row.int64(0),
            title: row.text(1) ?? "",
            notes: row.text(2),
            due: row.date(3),
            allDay: row.int(4) == 1,
            remindOffset: row.double(5),
            remindAt: row.date(6),
            repeatRule: row.text(7),
            completedAt: row.date(8),
            spawnedID: row.int(9).map(Int64.init),
            createdAt: row.date(10) ?? Date(),
            updatedAt: row.date(11) ?? Date(),
            lastNudgedAt: row.date(12)
        )
    }

    private func insert(_ draft: TaskDraft, createdAt: Date) throws {
        try db.execute(
            """
            INSERT INTO tasks (title, notes, due, all_day, remind_offset, remind_at, repeat_rule, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(draft.title), .string(draft.notes.isEmpty ? nil : draft.notes), .date(draft.due),
                .int(draft.allDay ? 1 : 0), .number(draft.remindOffset),
                .date(reminderDate(due: draft.due, allDay: draft.allDay, offset: draft.remindOffset)),
                .string(draft.rule?.storage), .date(createdAt), .date(createdAt),
            ]
        )
    }

    func reload() {
        let since = Date().addingTimeInterval(-Double(Self.doneWindowDays) * 86400).timeIntervalSince1970
        tasks = (try? db.query(
            "SELECT \(Self.columns) FROM tasks WHERE completed_at IS NULL OR completed_at >= ?",
            [.double(since)],
            row: Self.decode
        )) ?? []
        now = Date()
    }

    @discardableResult
    private func perform<T>(_ work: () throws -> T) -> T? {
        do {
            let result = try work()
            reload()
            onChange?()
            return result
        } catch {
            NSLog("Hachi: \(error)")
            return nil
        }
    }

    private func migrate() throws {
        if db.userVersion < 1 {
            try db.execute(
                """
                CREATE TABLE IF NOT EXISTS tasks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT NOT NULL,
                    notes TEXT,
                    due REAL,
                    all_day INTEGER NOT NULL DEFAULT 0,
                    remind_offset REAL,
                    remind_at REAL,
                    repeat_rule TEXT,
                    completed_at REAL,
                    spawned_id INTEGER,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    last_nudged_at REAL
                )
                """
            )
            try db.execute("CREATE INDEX IF NOT EXISTS tasks_completed_at ON tasks (completed_at)")
            db.userVersion = 1
        }
    }
}
