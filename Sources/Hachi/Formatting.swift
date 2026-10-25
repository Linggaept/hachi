import Foundation

/// Label tanggal dan jam berbahasa Indonesia.
enum Formatting {
    static let locale = Locale(identifier: "id_ID")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        return f
    }

    private static let time = formatter("HH.mm")
    private static let shortDay = formatter("EEE")
    private static let dayMonth = formatter("d MMM")
    private static let dayMonthYear = formatter("d MMM yyyy")
    private static let longDay = formatter("EEEE, d MMM")
    private static let longDayYear = formatter("EEEE, d MMM yyyy")

    static func clock(_ date: Date) -> String { time.string(from: date) }

    private static func dayDiff(_ date: Date, from now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Label pendek di baris daftar: "15.00", "Besok 09.00", "Sen", "26 Okt".
    static func dueLabel(for task: TaskItem, now: Date, calendar: Calendar = .current) -> String {
        guard let due = task.due else { return "" }
        let diff = dayDiff(due, from: now, calendar: calendar)
        let clock = task.allDay ? "" : time.string(from: due)
        let day: String
        switch diff {
        case 0: day = ""
        case -1: day = "Kemarin"
        case 1: day = "Besok"
        case ..<(-1): day = "\(-diff) hari lalu"
        case 2...6: day = shortDay.string(from: due)
        default:
            day = calendar.isDate(due, equalTo: now, toGranularity: .year)
                ? dayMonth.string(from: due) : dayMonthYear.string(from: due)
        }
        if diff < -1 { return day }
        return [day, clock].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Label panjang di pratinjau: "Hari ini · 15.00", "Jumat, 24 Okt · Seharian".
    static func longDue(_ due: Date, allDay: Bool, now: Date, calendar: Calendar = .current) -> String {
        let diff = dayDiff(due, from: now, calendar: calendar)
        let day: String
        switch diff {
        case 0: day = "Hari ini"
        case 1: day = "Besok"
        case -1: day = "Kemarin"
        default:
            day = calendar.isDate(due, equalTo: now, toGranularity: .year)
                ? longDay.string(from: due) : longDayYear.string(from: due)
        }
        return day + " · " + (allDay ? "Seharian" : time.string(from: due))
    }

    static func offsetLabel(_ offset: Double?) -> String {
        guard let offset else { return "Tanpa pengingat" }
        if offset == 0 { return "Tepat waktu" }
        let minutes = Int(offset / 60)
        if minutes % 1440 == 0 { return "\(minutes / 1440) hari sebelumnya" }
        if minutes % 60 == 0 { return "\(minutes / 60) jam sebelumnya" }
        return "\(minutes) menit sebelumnya"
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int((abs(seconds) / 60).rounded())
        if minutes < 60 { return "\(minutes) menit" }
        if minutes < 1440 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h) jam" : "\(h) jam \(m) menit"
        }
        return "\(minutes / 1440) hari"
    }

    /// Isi notifikasi pengingat.
    static func reminderBody(for task: TaskItem, at moment: Date, calendar: Calendar = .current) -> String {
        guard let due = task.due else { return "Pengingat" }
        if task.allDay {
            let diff = dayDiff(due, from: moment, calendar: calendar)
            switch diff {
            case 0: return "Hari ini"
            case 1: return "Besok"
            default: return longDue(due, allDay: true, now: moment, calendar: calendar)
            }
        }
        let gap = due.timeIntervalSince(moment)
        let prefix = calendar.isDate(due, inSameDayAs: moment) ? "Jam \(time.string(from: due))" : longDue(due, allDay: false, now: moment, calendar: calendar)
        if abs(gap) < 60 { return prefix + " · sekarang" }
        return gap > 0 ? prefix + " · \(duration(gap)) lagi" : prefix + " · lewat \(duration(gap))"
    }
}
