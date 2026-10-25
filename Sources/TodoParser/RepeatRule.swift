import Foundation

/// Aturan tugas berulang. Hari memakai nomor `Calendar` (1 = Minggu ... 7 = Sabtu).
public enum RepeatRule: Equatable, Hashable, Sendable {
    case daily(every: Int)
    /// `weekdays` kosong berarti mengikuti hari dari tanggal tugasnya.
    case weekly(every: Int, weekdays: [Int])
    case monthly(day: Int)
    case yearly

    public static let workdays = [2, 3, 4, 5, 6]

    // MARK: Simpan

    public var storage: String {
        switch self {
        case .daily(let every): "daily:\(every)"
        case .weekly(let every, let days): "weekly:\(every):" + days.map(String.init).joined(separator: ",")
        case .monthly(let day): "monthly:\(day)"
        case .yearly: "yearly"
        }
    }

    public init?(storage: String) {
        let parts = storage.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "daily":
            guard parts.count == 2, let every = Int(parts[1]), every > 0 else { return nil }
            self = .daily(every: every)
        case "weekly":
            guard parts.count == 3, let every = Int(parts[1]), every > 0 else { return nil }
            let days = parts[2].split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) }
            self = .weekly(every: every, weekdays: days)
        case "monthly":
            guard parts.count == 2, let day = Int(parts[1]), (1...31).contains(day) else { return nil }
            self = .monthly(day: day)
        case "yearly":
            self = .yearly
        default:
            return nil
        }
    }

    /// Hari diurutkan mulai Senin, untuk label.
    public static func mondayFirst(_ days: [Int]) -> [Int] {
        days.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
    }

    // MARK: Jadwal

    /// Apakah `day` (awal hari) termasuk jadwal, dihitung dari tanggal pertama `anchor` (awal hari).
    func matches(_ day: Date, anchor: Date, calendar: Calendar) -> Bool {
        switch self {
        case .daily(let every):
            let diff = calendar.dateComponents([.day], from: anchor, to: day).day ?? 0
            return diff >= 0 && diff % every == 0
        case .weekly(let every, let days):
            let weekday = calendar.component(.weekday, from: day)
            if days.isEmpty {
                let diff = calendar.dateComponents([.day], from: anchor, to: day).day ?? 0
                return diff >= 0 && diff % (7 * every) == 0
            }
            return days.contains(weekday)
        case .monthly(let wanted):
            let dayOfMonth = calendar.component(.day, from: day)
            let length = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
            return dayOfMonth == min(wanted, length)
        case .yearly:
            let a = calendar.dateComponents([.month, .day], from: anchor)
            let d = calendar.dateComponents([.month, .day], from: day)
            return a == d
        }
    }

    /// Jadwal berikutnya setelah `date`, jam tetap sama.
    public func next(after date: Date, calendar: Calendar = .current) -> Date {
        let anchor = calendar.startOfDay(for: date)
        let time = calendar.dateComponents([.hour, .minute], from: date)
        var day = anchor
        for _ in 0..<800 {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
            if matches(day, anchor: anchor, calendar: calendar) {
                return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day)!
            }
        }
        return calendar.date(byAdding: .day, value: 1, to: date)!
    }

    /// Jadwal berikutnya setelah `date` yang tidak sebelum `notBefore`.
    /// Tugas berulang yang telat diselesaikan tidak menumpuk jadwal yang sudah lewat.
    public func next(after date: Date, notBefore: Date, calendar: Calendar = .current) -> Date {
        var next = self.next(after: date, calendar: calendar)
        while next < notBefore {
            next = self.next(after: next, calendar: calendar)
        }
        return next
    }

    /// Untuk tugas seharian: jadwal berikutnya yang harinya belum lewat.
    public func nextDay(after date: Date, notBeforeDayOf now: Date, calendar: Calendar = .current) -> Date {
        next(after: date, notBefore: calendar.startOfDay(for: now), calendar: calendar)
    }
}
