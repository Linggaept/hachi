import Foundation
import TodoParser

struct TaskItem: Identifiable, Equatable, Codable {
    var id: Int64
    var title: String
    var notes: String?
    var due: Date?
    var allDay: Bool
    /// Detik sebelum `due`; `nil` = tanpa pengingat.
    var remindOffset: Double?
    /// Waktu pengingat berikutnya (bisa digeser oleh tunda).
    var remindAt: Date?
    var repeatRule: String?
    var completedAt: Date?
    /// Tugas berulang berikutnya yang dibuat saat tugas ini diselesaikan.
    var spawnedID: Int64?
    var createdAt: Date
    var updatedAt: Date
    var lastNudgedAt: Date?

    var rule: RepeatRule? { repeatRule.flatMap(RepeatRule.init(storage:)) }
    var isDone: Bool { completedAt != nil }

    func isOverdue(now: Date, calendar: Calendar = .current) -> Bool {
        guard let due, !isDone else { return false }
        return allDay ? due < calendar.startOfDay(for: now) : due < now
    }
}

/// Isian tugas dari catat cepat atau form ubah.
struct TaskDraft: Equatable {
    var title: String
    var notes: String = ""
    var due: Date?
    var allDay: Bool = false
    var remindOffset: Double?
    var rule: RepeatRule?

    init(title: String, notes: String = "", due: Date? = nil, allDay: Bool = false, remindOffset: Double? = nil, rule: RepeatRule? = nil) {
        self.title = title
        self.notes = notes
        self.due = due
        self.allDay = allDay
        self.remindOffset = remindOffset
        self.rule = rule
    }

    init(parsed: ParsedTask) {
        self.init(title: parsed.title, due: parsed.due, allDay: parsed.allDay, remindOffset: parsed.remindOffset, rule: parsed.repeatRule)
    }

    init(task: TaskItem) {
        self.init(title: task.title, notes: task.notes ?? "", due: task.due, allDay: task.allDay, remindOffset: task.remindOffset, rule: task.rule)
    }
}
