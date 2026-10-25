import Foundation
import TodoParser

/// Label tanggal, jam, dan durasi dalam bahasa tampilan app, dengan format wilayah dari pengaturan Mac.
enum Formatting {
    /// Bahasa mengikuti terjemahan yang dipilih macOS untuk app ini; wilayah dan format jam dari pengaturan Mac.
    static let locale: Locale = {
        var components = Locale.Components(locale: .autoupdatingCurrent)
        if let language = Bundle.main.preferredLocalizations.first {
            components.languageComponents.languageCode = Locale.LanguageCode(language)
        }
        return Locale(components: components)
    }()

    private static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let time = formatter("jmm")
    private static let shortDay = formatter("EEE")
    private static let dayMonth = formatter("dMMM")
    private static let dayMonthYear = formatter("dMMMyyyy")
    private static let longDay = formatter("EEEEdMMM")
    private static let longDayYear = formatter("EEEEdMMMyyyy")

    private static let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.calendar = calendar
        return f
    }()

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        return f
    }()

    static func clock(_ date: Date) -> String { time.string(from: date) }

    /// Jam bulat untuk pilihan di Pengaturan dan form, mis. "08.00" atau "8:00 AM".
    static func hour(_ hour: Int) -> String {
        clock(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!)
    }

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
        case -1: day = String(localized: "Yesterday")
        case 1: day = String(localized: "Tomorrow")
        case ..<(-1): day = relative.localizedString(from: DateComponents(day: diff))
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
        case 0: day = String(localized: "Today")
        case 1: day = String(localized: "Tomorrow")
        case -1: day = String(localized: "Yesterday")
        default:
            day = calendar.isDate(due, equalTo: now, toGranularity: .year)
                ? longDay.string(from: due) : longDayYear.string(from: due)
        }
        return day + " · " + (allDay ? String(localized: "All day") : time.string(from: due))
    }

    static func offsetLabel(_ offset: Double?) -> String {
        guard let offset else { return String(localized: "No reminder") }
        if offset == 0 { return String(localized: "On time") }
        return String(localized: "\(duration(offset)) before")
    }

    /// "30 menit", "1 jam, 5 menit", "2 hari".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((abs(seconds) / 60).rounded())
        let f = durationFormatter
        f.allowedUnits = minutes < 1440 ? [.hour, .minute] : [.day]
        let value = minutes < 1440 ? Double(minutes * 60) : Double(minutes / 1440 * 86400)
        return f.string(from: value) ?? ""
    }

    static func repeatLabel(_ rule: RepeatRule) -> String {
        switch rule {
        case .daily(1): return String(localized: "Every day")
        case .daily(let every): return String(localized: "Every \(every) days")
        case .weekly(_, let days) where days.sorted() == RepeatRule.workdays: return String(localized: "Every weekday")
        case .weekly(1, let days) where days.isEmpty: return String(localized: "Every week")
        case .weekly(let every, let days) where days.isEmpty: return String(localized: "Every \(every) weeks")
        case .weekly(_, let days):
            let names = RepeatRule.mondayFirst(days).map { calendar.standaloneWeekdaySymbols[$0 - 1] }
            return String(localized: "Every \(names.joined(separator: " & "))")
        case .monthly(let day): return String(localized: "Monthly on day \(day)")
        case .yearly: return String(localized: "Every year")
        }
    }

    /// Isi notifikasi pengingat.
    static func reminderBody(for task: TaskItem, at moment: Date, calendar: Calendar = .current) -> String {
        guard let due = task.due else { return String(localized: "Reminder") }
        if task.allDay {
            let diff = dayDiff(due, from: moment, calendar: calendar)
            switch diff {
            case 0: return String(localized: "Today")
            case 1: return String(localized: "Tomorrow")
            default: return longDue(due, allDay: true, now: moment, calendar: calendar)
            }
        }
        let gap = due.timeIntervalSince(moment)
        let prefix = calendar.isDate(due, inSameDayAs: moment)
            ? String(localized: "At \(time.string(from: due))")
            : longDue(due, allDay: false, now: moment, calendar: calendar)
        if abs(gap) < 60 { return String(localized: "\(prefix) · now") }
        return gap > 0
            ? String(localized: "\(prefix) · in \(duration(gap))")
            : String(localized: "\(prefix) · \(duration(gap)) ago")
    }
}
