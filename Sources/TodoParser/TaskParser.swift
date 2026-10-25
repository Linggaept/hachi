import Foundation

public enum DayPart: String, Sendable, CaseIterable {
    case subuh, pagi, siang, sore, malam
}

/// Jam bawaan saat kalimat hanya menyebut bagian hari ("besok pagi").
public struct ParserSettings: Equatable, Sendable {
    public var morningHour: Int
    public var noonHour: Int
    public var afternoonHour: Int
    public var eveningHour: Int

    public init(morningHour: Int = 8, noonHour: Int = 12, afternoonHour: Int = 16, eveningHour: Int = 20) {
        self.morningHour = morningHour
        self.noonHour = noonHour
        self.afternoonHour = afternoonHour
        self.eveningHour = eveningHour
    }

    public func hour(for part: DayPart) -> Int {
        switch part {
        case .subuh: 5
        case .pagi: morningHour
        case .siang: noonHour
        case .sore: afternoonHour
        case .malam: eveningHour
        }
    }
}

public struct ParsedTask: Equatable, Sendable {
    public var title: String
    /// Waktu tugas. Untuk tugas seharian: awal hari itu.
    public var due: Date?
    public var allDay: Bool
    /// Detik sebelum `due`. `nil` = tanpa pengingat sendiri (tugas seharian cukup masuk ringkasan pagi).
    public var remindOffset: TimeInterval?
    public var repeatRule: RepeatRule?

    public init(title: String, due: Date? = nil, allDay: Bool = false, remindOffset: TimeInterval? = nil, repeatRule: RepeatRule? = nil) {
        self.title = title
        self.due = due
        self.allDay = allDay
        self.remindOffset = remindOffset
        self.repeatRule = repeatRule
    }
}

/// Membaca kalimat sehari-hari berbahasa Indonesia menjadi tugas, tanpa AI.
/// Bagian yang dikenali sebagai waktu dibuang dari judul.
public struct TaskParser: Sendable {
    public var settings: ParserSettings
    public var calendar: Calendar

    public init(settings: ParserSettings = ParserSettings(), calendar: Calendar = .current) {
        self.settings = settings
        self.calendar = calendar
    }

    public func parse(_ text: String, now: Date) -> ParsedTask {
        let cursor = Cursor(text)
        let today = calendar.startOfDay(for: now)

        // Pengingat.
        var remindOffset: TimeInterval?
        var explicitRemind = false
        if let m = cursor.take(Patterns.remindAmount) ?? cursor.take(Patterns.amountBefore) {
            remindOffset = Self.seconds(amount: m[1], number: m[2], unit: m[3])
            explicitRemind = true
        }
        if cursor.take(Patterns.remindWord) != nil {
            explicitRemind = true
        }

        // Berulang.
        var rule: RepeatRule?
        var monthlyFromDue = false
        var dayPart: DayPart?
        if cursor.take(Patterns.everyWorkday) != nil {
            rule = .weekly(every: 1, weekdays: RepeatRule.workdays)
        } else if let m = cursor.take(Patterns.everyDayNamed) {
            rule = .weekly(every: 1, weekdays: Self.weekdays(in: m[1]))
        } else if let m = cursor.take(Patterns.everyN) {
            let n = max(1, Self.number(m[1]) ?? 1)
            rule = m[2] == "hari" ? .daily(every: n) : .weekly(every: n, weekdays: [])
        } else if cursor.take(Patterns.everyWeek) != nil {
            rule = .weekly(every: 1, weekdays: [])
        } else if let m = cursor.take(Patterns.everyDays) {
            rule = .weekly(every: 1, weekdays: Self.weekdays(in: m[1]))
        } else if cursor.take(Patterns.everyDay) != nil {
            rule = .daily(every: 1)
        } else if let m = cursor.take(Patterns.everyDayPart) {
            rule = .daily(every: 1)
            dayPart = m[1].flatMap(DayPart.init(rawValue:))
        } else if let m = cursor.take(Patterns.everyDate) {
            rule = .monthly(day: min(31, max(1, Int(m[1] ?? "") ?? 1)))
        } else if cursor.take(Patterns.everyMonth) != nil {
            rule = .monthly(day: 1)
            monthlyFromDue = true
        } else if cursor.take(Patterns.everyYear) != nil {
            rule = .yearly
        }

        // Dari sekarang.
        var exactDue: Date?
        var date: Date?
        if let m = cursor.take(Patterns.fromNow) {
            let unit = m[3]
            if unit == "hari" || unit == "minggu" || unit == "bulan" {
                let n = Self.number(m[2]) ?? 1
                let component: Calendar.Component = unit == "hari" ? .day : unit == "minggu" ? .weekOfYear : .month
                date = calendar.date(byAdding: component, value: n, to: today)
            } else if let seconds = Self.seconds(amount: m[1], number: m[2], unit: unit) {
                exactDue = now.addingTimeInterval(seconds)
            }
        }

        // Tanggal.
        var dateRanges: [NSRange] = []
        var pickedWeekday = false
        func setDate(_ d: Date?, _ range: NSRange) {
            if date == nil, let d { date = d }
            dateRanges.append(range)
        }
        if let m = cursor.take(Patterns.today) { setDate(today, m.range) }
        if let m = cursor.take(Patterns.dayAfterTomorrow) { setDate(add(2, to: today), m.range) }
        if let m = cursor.take(Patterns.tomorrow) { setDate(add(1, to: today), m.range) }
        if let m = cursor.take(Patterns.sundayExplicit) {
            setDate(weekday(1, qualifier: m[1], today: today), m.range)
            pickedWeekday = true
        }
        if let m = cursor.take(Patterns.nextWeek) { setDate(add(7, to: today), m.range) }
        if let m = cursor.take(Patterns.nextMonth) { setDate(calendar.date(byAdding: .month, value: 1, to: today), m.range) }
        if let m = cursor.take(Patterns.weekday) {
            setDate(weekday(Self.weekdays(in: m[1]).first ?? 2, qualifier: m[2], today: today), m.range)
            pickedWeekday = true
        }
        if let m = cursor.take(Patterns.dateKeyword) {
            let month = m[2].flatMap(Self.month) ?? m[3].flatMap { Int($0) }
            setDate(calendarDate(day: Int(m[1] ?? ""), month: month, year: m[4].flatMap { Int($0) }, today: today), m.range)
        }
        if let m = cursor.take(Patterns.dayMonthName) {
            setDate(calendarDate(day: Int(m[1] ?? ""), month: m[2].flatMap(Self.month), year: m[3].flatMap { Int($0) }, today: today), m.range)
        }
        if let m = cursor.take(Patterns.slashDate) {
            var year = m[3].flatMap { Int($0) }
            if let y = year, y < 100 { year = 2000 + y }
            setDate(calendarDate(day: Int(m[1] ?? ""), month: Int(m[2] ?? ""), year: year, today: today), m.range)
        }

        // Jam.
        var clock: Clock?
        var nanti = false
        if cursor.take(Patterns.nantiBeforeClock) != nil { nanti = true }
        if let m = cursor.take(Patterns.clock) {
            clock = Clock(
                hourText: m[2] ?? "",
                hour: Self.number(m[2]) ?? 0,
                minute: Int(m[3] ?? "") ?? 0,
                half: m[1] != nil,
                op: m[4],
                opMinutes: m[5] == "seperempat" ? 15 : Self.number(m[5]) ?? 0
            )
            if let part = m[6].flatMap(DayPart.init(rawValue:)) { dayPart = part }
        } else if let m = cursor.take(Patterns.bareClock) {
            clock = Clock(hourText: m[1] ?? "", hour: Int(m[1] ?? "") ?? 0, minute: Int(m[2] ?? "") ?? 0)
            if let part = m[3].flatMap(DayPart.init(rawValue:)) { dayPart = part }
        }
        if let m = cursor.take(Patterns.dayPartThis) {
            dayPart = dayPart ?? m[1].flatMap(DayPart.init(rawValue:))
            nanti = true
        }
        // Bagian hari hanya dibaca bila menempel ke kata waktu ("besok pagi", "nanti malam"),
        // supaya "makan malam" tetap judul.
        if let m = cursor.take(Patterns.dayPart, where: { m in
            m.group(1) != nil || dateRanges.contains { cursor.onlySpaceBetween($0, m.range) }
        }) {
            if m[1] != nil { nanti = true }
            dayPart = dayPart ?? m[2].flatMap(DayPart.init(rawValue:))
        }
        if nanti, date == nil, rule == nil { date = today }

        // Gabungkan.
        var due: Date?
        var allDay = false
        if let exactDue {
            due = exactDue
        } else if let baseRule = rule {
            var finalRule = baseRule
            let time = clock.map { resolve($0, dayPart: dayPart) }?.time ?? dayPart.map { (settings.hour(for: $0), 0) }
            let anchor = date ?? today
            if monthlyFromDue { finalRule = .monthly(day: calendar.component(.day, from: anchor)) }
            due = firstOccurrence(of: finalRule, from: anchor, time: time, now: now)
            allDay = time == nil
            rule = finalRule
        } else if clock != nil || dayPart != nil {
            let resolved = clock.map { resolve($0, dayPart: dayPart) }
                ?? Resolved(time: (settings.hour(for: dayPart!), 0), shift: 0, alternative: nil)
            let base = date ?? today
            var candidate = at(resolved.time, on: add(resolved.shift, to: base))
            if candidate <= now {
                if date == nil {
                    if let alt = resolved.alternative, at(alt, on: base) > now {
                        candidate = at(alt, on: base)
                    } else {
                        candidate = add(1, to: candidate)
                    }
                } else if pickedWeekday {
                    candidate = add(7, to: candidate)
                }
            }
            due = candidate
        } else if let date {
            due = date
            allDay = true
        }

        if due == nil {
            remindOffset = nil
        } else if !allDay {
            remindOffset = remindOffset ?? 0
        } else if explicitRemind {
            remindOffset = remindOffset ?? 0
        }

        return ParsedTask(
            title: Self.cleanTitle(cursor.remaining, fallback: text),
            due: due,
            allDay: allDay,
            remindOffset: remindOffset,
            repeatRule: rule
        )
    }

    // MARK: - Jam

    struct Clock {
        var hourText: String
        var hour: Int
        var minute: Int
        var half = false
        var op: String?
        var opMinutes = 0
    }

    struct Resolved {
        var time: (Int, Int)
        /// Hari yang ditambahkan, mis. "jam 12 malam" = besok 00.00.
        var shift: Int
        /// Jam lain bila jam ditulis tanpa pagi/sore dan pilihan pertama sudah lewat.
        var alternative: (Int, Int)?
    }

    func resolve(_ clock: Clock, dayPart: DayPart?) -> Resolved {
        var h = clock.hour
        var m = clock.minute
        if clock.half {
            h -= 1
            m = 30
        }
        switch clock.op {
        case "lewat", "lebih": m = clock.opMinutes
        case "kurang":
            h -= 1
            m = 60 - clock.opMinutes
        default: break
        }
        if h <= 0, clock.half || clock.op == "kurang" { h += 12 }
        m = min(max(m, 0), 59)

        if h >= 24 { return Resolved(time: (0, m), shift: 1, alternative: nil) }
        if h >= 13 { return Resolved(time: (h, m), shift: 0, alternative: nil) }

        if let dayPart {
            switch dayPart {
            case .subuh, .pagi:
                return Resolved(time: (h == 12 ? 0 : h, m), shift: 0, alternative: nil)
            case .siang:
                return Resolved(time: (h <= 5 ? h + 12 : h, m), shift: 0, alternative: nil)
            case .sore:
                return Resolved(time: (h < 12 ? h + 12 : h, m), shift: 0, alternative: nil)
            case .malam:
                if h == 12 { return Resolved(time: (0, m), shift: 1, alternative: nil) }
                if h < 6 { return Resolved(time: (h, m), shift: 1, alternative: nil) }
                return Resolved(time: (h + 12, m), shift: 0, alternative: nil)
            }
        }

        // Tanpa pagi/sore. "09.30" (nol di depan) berarti jam 24.
        if clock.hourText.hasPrefix("0") || h == 0 {
            return Resolved(time: (h, m), shift: 0, alternative: nil)
        }
        switch h {
        case 1...6: return Resolved(time: (h + 12, m), shift: 0, alternative: nil)
        case 7...11: return Resolved(time: (h, m), shift: 0, alternative: (h + 12, m))
        default: return Resolved(time: (12, m), shift: 0, alternative: nil)
        }
    }

    // MARK: - Tanggal

    func add(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    func at(_ time: (Int, Int), on day: Date) -> Date {
        calendar.date(bySettingHour: time.0, minute: time.1, second: 0, of: day)!
    }

    /// Tanpa keterangan atau "ini": hari itu yang terdekat (bisa hari ini).
    /// "depan": hari itu di minggu depan (minggu dimulai Senin).
    func weekday(_ wanted: Int, qualifier: String?, today: Date) -> Date {
        let todayIndex = (calendar.component(.weekday, from: today) + 5) % 7
        let wantedIndex = (wanted + 5) % 7
        if qualifier == "depan" {
            return add(7 - todayIndex + wantedIndex, to: today)
        }
        return add((wantedIndex - todayIndex + 7) % 7, to: today)
    }

    /// Tanggal tanpa tahun/bulan yang sudah lewat dipindah ke bulan/tahun berikutnya.
    func calendarDate(day: Int?, month: Int?, year: Int?, today: Date) -> Date? {
        guard let day, (1...31).contains(day) else { return nil }
        let now = calendar.dateComponents([.year, .month], from: today)
        if let month {
            guard (1...12).contains(month) else { return nil }
            var y = year ?? now.year!
            var d = calendar.date(from: DateComponents(year: y, month: month, day: day))
            if year == nil, let candidate = d, candidate < today {
                y += 1
                d = calendar.date(from: DateComponents(year: y, month: month, day: day))
            }
            return d
        }
        var components = DateComponents(year: now.year, month: now.month, day: day)
        var d = calendar.date(from: components)
        if let candidate = d, candidate < today {
            components.month! += 1
            d = calendar.date(from: components)
        }
        return d
    }

    func firstOccurrence(of rule: RepeatRule, from anchor: Date, time: (Int, Int)?, now: Date) -> Date {
        var day = anchor
        for _ in 0..<800 {
            if rule.matches(day, anchor: anchor, calendar: calendar) {
                if let time {
                    let candidate = at(time, on: day)
                    if candidate > now { return candidate }
                } else if day >= calendar.startOfDay(for: now) {
                    return day
                }
            }
            day = add(1, to: day)
        }
        return anchor
    }

    // MARK: - Angka dan kata

    static let units = ["satu": 1, "dua": 2, "tiga": 3, "empat": 4, "lima": 5, "enam": 6, "tujuh": 7, "delapan": 8, "sembilan": 9]

    static func number(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let words = raw.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count == 1, let n = Int(words[0]) { return n }
        switch words.count {
        case 1:
            if words[0] == "sepuluh" { return 10 }
            if words[0] == "sebelas" { return 11 }
            return units[words[0]]
        case 2 where words[1] == "belas":
            return units[words[0]].map { 10 + $0 }
        case 2 where words[1] == "puluh":
            return units[words[0]].map { $0 * 10 }
        case 3 where words[1] == "puluh":
            guard let tens = units[words[0]], let unit = units[words[2]] else { return nil }
            return tens * 10 + unit
        default:
            return nil
        }
    }

    static func seconds(amount: String?, number: String?, unit: String?) -> TimeInterval? {
        let amount = amount?.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if amount == "setengah jam" { return 1800 }
        if amount == "sejam" { return 3600 }
        guard let n = Self.number(number) else { return nil }
        switch unit {
        case "menit", "mnt": return TimeInterval(n * 60)
        case "jam": return TimeInterval(n * 3600)
        case "hari": return TimeInterval(n * 86400)
        default: return nil
        }
    }

    static let weekdayWords: [String: Int] = [
        "minggu": 1, "ahad": 1, "senin": 2, "selasa": 3, "rabu": 4, "kamis": 5, "jumat": 6, "jum'at": 6, "sabtu": 7,
    ]

    static func weekdays(in text: String?) -> [Int] {
        guard let text else { return [] }
        var result: [Int] = []
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }) {
            if let day = weekdayWords[String(word)], !result.contains(day) { result.append(day) }
        }
        return RepeatRule.mondayFirst(result)
    }

    static func month(_ text: String) -> Int? {
        let prefix = String(text.lowercased().prefix(3))
        let months = ["jan", "feb", "mar", "apr", "mei", "jun", "jul", "agu", "sep", "okt", "nov", "des"]
        if let i = months.firstIndex(of: prefix) { return i + 1 }
        if prefix == "agt" || prefix == "ags" { return 8 }
        return nil
    }

    static func cleanTitle(_ remaining: String, fallback: String) -> String {
        var title = remaining
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let edge = #"(?i)^(?:dan|,|-|pada|tgl|tanggal|jam|pukul|nanti)\s+|\s+(?:dan|pada|tgl|tanggal|jam|pukul|nanti|di|,|-)$|^[,\-]+|[,\-]+$"#
        while let range = title.range(of: edge, options: .regularExpression) {
            title.removeSubrange(range)
            title = title.trimmingCharacters(in: .whitespaces)
        }
        if title.isEmpty { title = fallback.trimmingCharacters(in: .whitespaces) }
        guard let first = title.first else { return title }
        return first.uppercased() + title.dropFirst()
    }
}

// MARK: - Pola

enum Patterns {
    static let num = #"(?:\d{1,3}|(?:dua|tiga|empat|lima)\s+puluh(?:\s+(?:satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan))?|(?:dua|tiga|empat|lima|enam|tujuh|delapan|sembilan)\s+belas|sebelas|sepuluh|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan)"#
    static let day = #"(?:senin|selasa|rabu|kamis|jum'?at|sabtu|minggu|ahad)"#
    static let dayList = "\(day)(?:\\s*(?:,|dan|&)\\s*\(day))*"
    static let month = #"(?:januari|februari|maret|april|mei|juni|juli|agustus|september|oktober|november|desember|jan|feb|mar|apr|jun|jul|agu|agt|ags|sep|sept|okt|nov|des)"#
    static let part = #"(pagi|siang|sore|malam|subuh)"#
    static let amount = "(setengah\\s+jam|sejam|(\(num))\\s*(menit|mnt|jam|hari))"
    static let remindVerb = #"(?:ingetin|ingatkan|ingatin|ingetkan|remind(?:er)?)(?:\s+(?:aku|saya|gue|gw))?"#

    static let remindAmount = re("\\b\(remindVerb)\\s+\(amount)\\s+(?:sebelum(?:nya)?|sblm(?:nya)?)\\b")
    static let amountBefore = re("\\b\(amount)\\s+(?:sebelum(?:nya)?|sblm(?:nya)?)\\b")
    static let remindWord = re("\\b\(remindVerb)\\b")

    static let everyWorkday = re(#"\b(?:tiap|setiap)\s+hari\s+kerja\b"#)
    static let everyDayNamed = re("\\b(?:tiap|setiap)\\s+hari\\s+(\(dayList))\\b")
    static let everyN = re("\\b(?:tiap|setiap)\\s+(\(num))\\s+(hari|minggu)\\b")
    static let everyWeek = re(#"\b(?:tiap|setiap)\s+(?:minggu|pekan)\b(?!\s*(?:,|dan|&))"#)
    static let everyDays = re("\\b(?:tiap|setiap)\\s+(\(dayList))\\b")
    static let everyDay = re(#"\b(?:tiap|setiap)\s+hari\b"#)
    static let everyDayPart = re("\\b(?:tiap|setiap)\\s+\(part)\\b")
    static let everyDate = re(#"\b(?:tiap|setiap)\s+(?:tanggal|tgl)\s*(\d{1,2})\b"#)
    static let everyMonth = re(#"\b(?:tiap|setiap)\s+bulan\b"#)
    static let everyYear = re(#"\b(?:tiap|setiap)\s+tahun\b"#)

    static let fromNow = re("\\b(?:dalam\\s+)?(setengah\\s+jam|sejam|(\(num))\\s*(menit|mnt|jam|hari|minggu|bulan))\\s+lagi\\b")

    static let today = re(#"\bhari\s+ini\b"#)
    static let dayAfterTomorrow = re(#"\blusa\b"#)
    static let tomorrow = re(#"\b(?:besok|besuk|bsk)\b"#)
    static let sundayExplicit = re(#"\bhari\s+minggu(?:\s+(depan|ini))?\b"#)
    static let nextWeek = re(#"\b(?:minggu|pekan)\s+depan\b"#)
    static let nextMonth = re(#"\bbulan\s+depan\b"#)
    static let weekday = re("\\b(?:hari\\s+)?(\(day))(?:\\s+(depan|ini))?\\b")
    static let dateKeyword = re("\\b(?:tgl|tanggal)\\.?\\s*(\\d{1,2})(?:\\s+(\(month))|[/-](\\d{1,2}))?(?:\\s+(\\d{4}))?\\b")
    static let dayMonthName = re("\\b(\\d{1,2})\\s+(\(month))(?:\\s+(\\d{4}))?\\b")
    static let slashDate = re(#"\b(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?\b"#)

    static let nantiBeforeClock = re(#"\bnanti\b(?=\s+(?:jam|pukul|pkl)\b)"#)
    static let clock = re("\\b(?:jam|pukul|pkl)\\s+(setengah\\s+)?(\(num))(?:\\s*[.:]\\s*(\\d{2})|\\s+(lewat|lebih|kurang)\\s+(seperempat|\(num))(?:\\s*menit)?)?(?:\\s+(?:nanti\\s+)?\(part))?\\b")
    static let bareClock = re("\\b(\\d{1,2})[.:](\\d{2})\\b(?:\\s+\(part)\\b)?")
    static let dayPartThis = re("\\b\(part)\\s+ini\\b")
    static let dayPart = re("\\b(nanti\\s+)?\(part)\\b")

    static func re(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}

// MARK: - Penanda teks yang sudah dibaca

final class Cursor {
    struct Match {
        let result: NSTextCheckingResult
        let source: NSString
        var range: NSRange { result.range }

        func group(_ i: Int) -> String? {
            guard i < result.numberOfRanges else { return nil }
            let r = result.range(at: i)
            guard r.location != NSNotFound else { return nil }
            return source.substring(with: r).lowercased()
        }

        subscript(_ i: Int) -> String? { group(i) }
    }

    private let original: NSString
    private let working: NSMutableString

    init(_ text: String) {
        original = text as NSString
        working = NSMutableString(string: text)
    }

    /// Teks yang belum dibaca. Bagian yang sudah dibaca menjadi spasi.
    var remaining: String { working as String }

    /// Mengambil kecocokan pertama yang diterima, lalu menghapusnya dari teks.
    func take(_ regex: NSRegularExpression, where accept: ((Match) -> Bool)? = nil) -> Match? {
        let matches = regex.matches(in: working as String, range: NSRange(location: 0, length: working.length))
        for result in matches {
            let match = Match(result: result, source: original)
            guard accept?(match) ?? true else { continue }
            working.replaceCharacters(in: result.range, with: String(repeating: " ", count: result.range.length))
            return match
        }
        return nil
    }

    /// Hanya spasi di antara dua bagian (di teks asli, urutan bebas).
    func onlySpaceBetween(_ a: NSRange, _ b: NSRange) -> Bool {
        let (first, second) = a.location < b.location ? (a, b) : (b, a)
        let start = first.location + first.length
        guard second.location >= start else { return false }
        let gap = original.substring(with: NSRange(location: start, length: second.location - start))
        return gap.allSatisfy(\.isWhitespace)
    }
}
