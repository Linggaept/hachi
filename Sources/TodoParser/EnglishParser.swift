import Foundation

/// Membaca kalimat sehari-hari berbahasa Inggris menjadi tugas.
struct EnglishParser: LanguageParser {
    let core: ParserCore

    func parse(_ text: String, now: Date) -> (task: ParsedTask, consumed: Int) {
        let cursor = Cursor(text)
        let calendar = core.calendar
        let today = calendar.startOfDay(for: now)
        var p = ParserCore.Pieces()

        // Pengingat.
        if let m = cursor.take(EnglishPatterns.remindAmount) ?? cursor.take(EnglishPatterns.amountBefore) {
            p.remindOffset = Self.amountSeconds(m[1], number: m[2], unit: m[3])
            p.explicitRemind = true
        }
        if cursor.take(EnglishPatterns.remindWord) != nil {
            p.explicitRemind = true
        }

        // Berulang.
        if cursor.take(EnglishPatterns.everyWeekday) != nil {
            p.rule = .weekly(every: 1, weekdays: RepeatRule.workdays)
        } else if let m = cursor.take(EnglishPatterns.everyDays) {
            p.rule = .weekly(every: 1, weekdays: Self.weekdays(in: m[1]))
        } else if let m = cursor.take(EnglishPatterns.everyN) {
            let n = max(1, Self.number(m[1]) ?? 1)
            p.rule = Self.unit(m[2]) == .day ? .daily(every: n) : .weekly(every: n, weekdays: [])
        } else if let m = cursor.take(EnglishPatterns.everyMonthOnDay) {
            p.rule = .monthly(day: min(31, max(1, Int(m[1] ?? m[2] ?? m[3] ?? "") ?? 1)))
        } else if cursor.take(EnglishPatterns.everyDay) != nil {
            p.rule = .daily(every: 1)
        } else if cursor.take(EnglishPatterns.everyWeek) != nil {
            p.rule = .weekly(every: 1, weekdays: [])
        } else if let m = cursor.take(EnglishPatterns.everyDayPart) {
            p.rule = .daily(every: 1)
            p.dayPart = Self.dayPart(m[1])
        } else if cursor.take(EnglishPatterns.everyMonth) != nil {
            p.rule = .monthly(day: 1)
            p.monthlyFromDue = true
        } else if cursor.take(EnglishPatterns.everyYear) != nil {
            p.rule = .yearly
        }

        // Dari sekarang.
        if let m = cursor.take(EnglishPatterns.fromNow) ?? cursor.take(EnglishPatterns.fromNowSuffix) {
            let amount = m[1] ?? "", unit = Self.unit(m[3])
            if amount.hasPrefix("half") {
                p.exactDue = now.addingTimeInterval(1800)
            } else if let n = Self.number(m[2]) {
                switch unit {
                case .day: p.date = calendar.date(byAdding: .day, value: n, to: today)
                case .week: p.date = calendar.date(byAdding: .weekOfYear, value: n, to: today)
                case .month: p.date = calendar.date(byAdding: .month, value: n, to: today)
                case .minute, .hour: p.exactDue = now.addingTimeInterval(Self.seconds(n, unit))
                case nil: break
                }
            }
        }

        // Tanggal.
        var dateRanges: [NSRange] = []
        func setDate(_ d: Date?, _ range: NSRange) {
            if p.date == nil, let d { p.date = d }
            dateRanges.append(range)
        }
        if let m = cursor.take(EnglishPatterns.tonight) {
            setDate(today, m.range)
            p.dayPart = .malam
        }
        if let m = cursor.take(EnglishPatterns.today) { setDate(today, m.range) }
        if let m = cursor.take(EnglishPatterns.dayAfterTomorrow) { setDate(core.add(2, to: today), m.range) }
        if let m = cursor.take(EnglishPatterns.tomorrow) { setDate(core.add(1, to: today), m.range) }
        if let m = cursor.take(EnglishPatterns.nextWeek) { setDate(core.add(7, to: today), m.range) }
        if let m = cursor.take(EnglishPatterns.nextMonth) { setDate(calendar.date(byAdding: .month, value: 1, to: today), m.range) }
        if let m = cursor.take(EnglishPatterns.weekday) {
            setDate(core.weekday(Self.weekdays(in: m[2]).first ?? 2, next: m[1] == "next", today: today), m.range)
            p.pickedWeekday = true
        }
        if let m = cursor.take(EnglishPatterns.isoDate) {
            setDate(core.calendarDate(day: Int(m[3] ?? ""), month: Int(m[2] ?? ""), year: Int(m[1] ?? ""), today: today), m.range)
        }
        if let m = cursor.take(EnglishPatterns.monthDay) {
            setDate(core.calendarDate(day: Int(m[2] ?? ""), month: m[1].flatMap(Self.month), year: m[3].flatMap { Int($0) }, today: today), m.range)
        }
        if let m = cursor.take(EnglishPatterns.dayMonth) {
            setDate(core.calendarDate(day: Int(m[1] ?? ""), month: m[2].flatMap(Self.month), year: m[3].flatMap { Int($0) }, today: today), m.range)
        }
        if let m = cursor.take(EnglishPatterns.ordinalDay) {
            setDate(core.calendarDate(day: Int(m[1] ?? ""), month: nil, year: nil, today: today), m.range)
        }
        if let m = cursor.take(EnglishPatterns.slashDate) {
            var year = m[3].flatMap { Int($0) }
            if let y = year, y < 100 { year = 2000 + y }
            let first = Int(m[1] ?? ""), second = Int(m[2] ?? "")
            let (day, month) = core.settings.monthFirst ? (second, first) : (first, second)
            setDate(core.calendarDate(day: day, month: month, year: year, today: today), m.range)
        }

        // Jam.
        if let m = cursor.take(EnglishPatterns.amPm) {
            let hour = Int(m[1] ?? "") ?? 0, minute = min(Int(m[2] ?? "") ?? 0, 59)
            let pm = m[3]?.hasPrefix("p") == true
            let h = hour % 12 + (pm ? 12 : 0)
            p.fixedTime = ParserCore.Resolved(time: (h, minute), shift: 0, alternative: nil)
        } else if let m = cursor.take(EnglishPatterns.noonMidnight) {
            p.fixedTime = m[1] == "midnight"
                ? ParserCore.Resolved(time: (0, 0), shift: 1, alternative: nil)
                : ParserCore.Resolved(time: (12, 0), shift: 0, alternative: nil)
        } else if let m = cursor.take(EnglishPatterns.pastTo) {
            let hour = Self.number(m[3]) ?? 0
            let minutes = m[1] == "half" ? 30 : 15
            let (h, minute) = m[2] == "to" ? (hour - 1, 60 - minutes) : (hour, minutes)
            p.clock = ParserCore.Clock(hourText: String(h), hour: h, minute: minute)
        } else if let m = cursor.take(EnglishPatterns.atClock) ?? cursor.take(EnglishPatterns.bareClock) {
            p.clock = ParserCore.Clock(hourText: m[1] ?? "", hour: Self.number(m[1]) ?? 0, minute: Int(m[2] ?? "") ?? 0)
        }

        // Bagian hari. Kata seperti "morning" hanya dibaca bila menempel ke kata waktu,
        // supaya "morning run" atau "dinner" tetap judul.
        if let m = cursor.take(EnglishPatterns.dayPartThis) {
            p.dayPart = p.dayPart ?? Self.dayPart(m[1])
            if p.date == nil, p.rule == nil { p.date = today }
        }
        if let m = cursor.take(EnglishPatterns.dayPartPhrase) {
            p.dayPart = p.dayPart ?? Self.dayPart(m[1] ?? m[2])
        }
        if let m = cursor.take(EnglishPatterns.dayPart, where: { m in
            dateRanges.contains { cursor.onlySpaceBetween($0, m.range) }
        }) {
            p.dayPart = p.dayPart ?? Self.dayPart(m[1])
        }

        let title = ParserCore.cleanTitle(cursor.remaining, fallback: text, edge: Self.edge)
        return (core.assemble(p, title: title, now: now), cursor.consumed)
    }

    // MARK: - Kata

    static let edge = #"(?i)^(?:and|at|on|by|to|the|,|-|:)\s+|\s+(?:and|at|on|by|to|the|,|-|:)$|^[,\-:]+|[,\-:]+$"#

    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40,
        "fifty": 50,
    ]

    static func number(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let text = raw.lowercased().replacingOccurrences(of: "-", with: " ")
        if let n = Int(text) { return n }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count == 2, let tens = numberWords[words[0]], tens >= 20, let unit = numberWords[words[1]], unit < 10 {
            return tens + unit
        }
        return words.count == 1 ? numberWords[words[0]] : nil
    }

    enum Unit { case minute, hour, day, week, month }

    static func unit(_ raw: String?) -> Unit? {
        guard let raw = raw?.lowercased() else { return nil }
        if raw.hasPrefix("min") { return .minute }
        if raw.hasPrefix("h") { return .hour }
        if raw.hasPrefix("d") { return .day }
        if raw.hasPrefix("w") { return .week }
        if raw.hasPrefix("mo") { return .month }
        return nil
    }

    static func amountSeconds(_ amount: String?, number: String?, unit: String?) -> TimeInterval? {
        if amount?.lowercased().hasPrefix("half") == true { return 1800 }
        guard let n = Self.number(number), let unit = Self.unit(unit), unit != .week, unit != .month else { return nil }
        return seconds(n, unit)
    }

    static func seconds(_ n: Int, _ unit: Unit?) -> TimeInterval {
        switch unit {
        case .minute: TimeInterval(n * 60)
        case .hour: TimeInterval(n * 3600)
        case .day: TimeInterval(n * 86400)
        default: 0
        }
    }

    static let weekdayWords: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6,
    ]

    static func weekdays(in text: String?) -> [Int] {
        guard let text else { return [] }
        var result: [Int] = []
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let day = weekdayWords[String(word)], !result.contains(day) { result.append(day) }
        }
        return RepeatRule.mondayFirst(result)
    }

    static func month(_ text: String) -> Int? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return months.firstIndex(of: String(text.lowercased().prefix(3))).map { $0 + 1 }
    }

    static func dayPart(_ word: String?) -> DayPart? {
        switch word?.lowercased() {
        case "morning": .pagi
        case "afternoon": .sore
        case "evening", "night": .malam
        default: nil
        }
    }
}

// MARK: - Pola

enum EnglishPatterns {
    static let num = #"(?:\d{1,3}|(?:twenty|thirty|forty|fifty)(?:[\s-](?:one|two|three|four|five|six|seven|eight|nine))?|fifteen|twelve|eleven|ten|one|two|three|four|five|six|seven|eight|nine)"#
    static let amountNum = "(?:\(num)|an?)"
    static let unit = #"(minutes?|mins?|hours?|hrs?|h|days?|weeks?|months?)"#
    static let day = #"(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tues?|wed|thu(?:rs?)?|fri)"#
    static let month = #"(?:january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept?|oct|nov|dec)"#
    static let ordinal = #"(?:st|nd|rd|th)"#

    static let amount = "(half\\s+an\\s+hour|(\(amountNum))\\s*\(unit))"
    static let before = #"(?:before(?:hand)?|earlier)"#
    static let remindAmount = regex("\\bremind\\s+me\\s+\(amount)\\s+\(before)\\b")
    static let amountBefore = regex("\\b\(amount)\\s+\(before)\\b")
    static let remindWord = regex(#"\bremind\s+me\b"#)

    static let dayList = "\(day)(?:\\s*(?:,|and|&)\\s*\(day))*"
    static let everyWeekday = regex(#"\bevery\s+weekday\b"#)
    static let everyDays = regex("\\bevery\\s+(\(dayList))\\b")
    static let everyN = regex("\\bevery\\s+(\(num))\\s+(days?|weeks?)\\b")
    static let everyMonthOnDay = regex(
        "\\bevery\\s+month\\s+on\\s+the\\s+(\\d{1,2})\(ordinal)?\\b"
            + "|\\b(?:on\\s+)?the\\s+(\\d{1,2})\(ordinal)\\s+of\\s+(?:every|each)\\s+month\\b"
            + "|\\bevery\\s+(\\d{1,2})\(ordinal)\\b"
    )
    static let everyDay = regex(#"\b(?:every\s+day|daily)\b"#)
    static let everyWeek = regex(#"\b(?:every\s+week|weekly)\b"#)
    static let everyDayPart = regex(#"\bevery\s+(morning|afternoon|evening|night)\b"#)
    static let everyMonth = regex(#"\b(?:every\s+month|monthly)\b"#)
    static let everyYear = regex(#"\b(?:every\s+year|yearly|annually)\b"#)

    static let fromNow = regex("\\bin\\s+(half\\s+an\\s+hour|(\(amountNum))\\s*\(unit))\\b")
    static let fromNowSuffix = regex("\\b((\(amountNum))\\s*\(unit))\\s+from\\s+now\\b")

    static let tonight = regex(#"\btonight\b"#)
    static let today = regex(#"\btoday\b"#)
    static let dayAfterTomorrow = regex(#"\b(?:the\s+)?day\s+after\s+tomorrow\b"#)
    static let tomorrow = regex(#"\b(?:tomorrow|tmrw?|tmr)\b"#)
    static let nextWeek = regex(#"\bnext\s+week\b"#)
    static let nextMonth = regex(#"\bnext\s+month\b"#)
    static let weekday = regex("\\b(?:(this|next|on)\\s+)?(\(day))\\b")
    static let isoDate = regex(#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#)
    static let monthDay = regex("\\b(?:on\\s+)?(\(month))\\.?\\s+(\\d{1,2})\(ordinal)?(?:,?\\s+(\\d{4}))?\\b")
    static let dayMonth = regex("\\b(?:on\\s+)?(?:the\\s+)?(\\d{1,2})\(ordinal)?\\s+(?:of\\s+)?(\(month))(?:,?\\s+(\\d{4}))?\\b")
    static let ordinalDay = regex("\\b(?:on\\s+)?(?:the\\s+)?(\\d{1,2})\(ordinal)\\b")
    static let slashDate = regex(#"\b(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?\b"#)

    static let amPm = regex(#"\b(?:at\s+)?(\d{1,2})(?:[:.](\d{2}))?\s*([ap])\.?m\.?(?![a-z])"#)
    static let noonMidnight = regex(#"\b(?:at\s+)?(noon|midday|midnight)\b"#)
    static let pastTo = regex("\\b(?:at\\s+)?(half|quarter)\\s+(past|to)\\s+(\(num))\\b")
    static let atClock = regex("\\bat\\s+(\(num))(?:[:.](\\d{2}))?\\b")
    static let bareClock = regex(#"\b(\d{1,2}):(\d{2})\b"#)

    static let dayPartThis = regex(#"\bthis\s+(morning|afternoon|evening)\b"#)
    static let dayPartPhrase = regex(#"\b(?:in\s+the\s+(morning|afternoon|evening)|at\s+(night))\b"#)
    static let dayPart = regex(#"\b(morning|afternoon|evening|night)\b"#)
}
