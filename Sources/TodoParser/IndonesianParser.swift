import Foundation

/// Membaca kalimat sehari-hari berbahasa Indonesia menjadi tugas.
struct IndonesianParser: LanguageParser {
    let core: ParserCore

    func parse(_ text: String, now: Date) -> (task: ParsedTask, consumed: Int) {
        let cursor = Cursor(text)
        let today = core.calendar.startOfDay(for: now)

        // Pengingat.
        var remindOffset: TimeInterval?
        var explicitRemind = false
        if let m = cursor.take(IndonesianPatterns.remindAmount) ?? cursor.take(IndonesianPatterns.amountBefore) {
            remindOffset = Self.seconds(amount: m[1], number: m[2], unit: m[3])
            explicitRemind = true
        }
        if cursor.take(IndonesianPatterns.remindWord) != nil {
            explicitRemind = true
        }

        // Berulang.
        var rule: RepeatRule?
        var monthlyFromDue = false
        var dayPart: DayPart?
        if cursor.take(IndonesianPatterns.everyWorkday) != nil {
            rule = .weekly(every: 1, weekdays: RepeatRule.workdays)
        } else if let m = cursor.take(IndonesianPatterns.everyDayNamed) {
            rule = .weekly(every: 1, weekdays: Self.weekdays(in: m[1]))
        } else if let m = cursor.take(IndonesianPatterns.everyN) {
            let n = max(1, Self.number(m[1]) ?? 1)
            rule = m[2] == "hari" ? .daily(every: n) : .weekly(every: n, weekdays: [])
        } else if cursor.take(IndonesianPatterns.everyWeek) != nil {
            rule = .weekly(every: 1, weekdays: [])
        } else if let m = cursor.take(IndonesianPatterns.everyDays) {
            rule = .weekly(every: 1, weekdays: Self.weekdays(in: m[1]))
        } else if cursor.take(IndonesianPatterns.everyDay) != nil {
            rule = .daily(every: 1)
        } else if let m = cursor.take(IndonesianPatterns.everyDayPart) {
            rule = .daily(every: 1)
            dayPart = m[1].flatMap(DayPart.init(rawValue:))
        } else if let m = cursor.take(IndonesianPatterns.everyDate) {
            rule = .monthly(day: min(31, max(1, Int(m[1] ?? "") ?? 1)))
        } else if cursor.take(IndonesianPatterns.everyMonth) != nil {
            rule = .monthly(day: 1)
            monthlyFromDue = true
        } else if cursor.take(IndonesianPatterns.everyYear) != nil {
            rule = .yearly
        }

        // Dari sekarang.
        var exactDue: Date?
        var date: Date?
        if let m = cursor.take(IndonesianPatterns.fromNow) {
            let unit = m[3]
            if unit == "hari" || unit == "minggu" || unit == "bulan" {
                let n = Self.number(m[2]) ?? 1
                let component: Calendar.Component = unit == "hari" ? .day : unit == "minggu" ? .weekOfYear : .month
                date = core.calendar.date(byAdding: component, value: n, to: today)
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
        if let m = cursor.take(IndonesianPatterns.today) { setDate(today, m.range) }
        if let m = cursor.take(IndonesianPatterns.dayAfterTomorrow) { setDate(core.add(2, to: today), m.range) }
        if let m = cursor.take(IndonesianPatterns.tomorrow) { setDate(core.add(1, to: today), m.range) }
        if let m = cursor.take(IndonesianPatterns.sundayExplicit) {
            setDate(core.weekday(1, next: m[1] == "depan", today: today), m.range)
            pickedWeekday = true
        }
        if let m = cursor.take(IndonesianPatterns.nextWeek) { setDate(core.add(7, to: today), m.range) }
        if let m = cursor.take(IndonesianPatterns.nextMonth) { setDate(core.calendar.date(byAdding: .month, value: 1, to: today), m.range) }
        if let m = cursor.take(IndonesianPatterns.weekday) {
            setDate(core.weekday(Self.weekdays(in: m[1]).first ?? 2, next: m[2] == "depan", today: today), m.range)
            pickedWeekday = true
        }
        if let m = cursor.take(IndonesianPatterns.dateKeyword) {
            let month = m[2].flatMap(Self.month) ?? m[3].flatMap { Int($0) }
            setDate(core.calendarDate(day: Int(m[1] ?? ""), month: month, year: m[4].flatMap { Int($0) }, today: today), m.range)
        }
        if let m = cursor.take(IndonesianPatterns.dayMonthName) {
            setDate(core.calendarDate(day: Int(m[1] ?? ""), month: m[2].flatMap(Self.month), year: m[3].flatMap { Int($0) }, today: today), m.range)
        }
        if let m = cursor.take(IndonesianPatterns.slashDate) {
            var year = m[3].flatMap { Int($0) }
            if let y = year, y < 100 { year = 2000 + y }
            setDate(core.calendarDate(day: Int(m[1] ?? ""), month: Int(m[2] ?? ""), year: year, today: today), m.range)
        }

        // Jam.
        var clock: ParserCore.Clock?
        var nanti = false
        if cursor.take(IndonesianPatterns.nantiBeforeClock) != nil { nanti = true }
        if let m = cursor.take(IndonesianPatterns.clock) {
            clock = ParserCore.Clock(
                hourText: m[2] ?? "",
                hour: Self.number(m[2]) ?? 0,
                minute: Int(m[3] ?? "") ?? 0,
                half: m[1] != nil,
                op: m[4],
                opMinutes: m[5] == "seperempat" ? 15 : Self.number(m[5]) ?? 0
            )
            if let part = m[6].flatMap(DayPart.init(rawValue:)) { dayPart = part }
        } else if let m = cursor.take(IndonesianPatterns.bareClock) {
            clock = ParserCore.Clock(hourText: m[1] ?? "", hour: Int(m[1] ?? "") ?? 0, minute: Int(m[2] ?? "") ?? 0)
            if let part = m[3].flatMap(DayPart.init(rawValue:)) { dayPart = part }
        }
        if let m = cursor.take(IndonesianPatterns.dayPartThis) {
            dayPart = dayPart ?? m[1].flatMap(DayPart.init(rawValue:))
            nanti = true
        }
        // Bagian hari hanya dibaca bila menempel ke kata waktu ("besok pagi", "nanti malam"),
        // supaya "makan malam" tetap judul.
        if let m = cursor.take(IndonesianPatterns.dayPart, where: { m in
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
            let time = clock.map { core.resolve($0, dayPart: dayPart) }?.time ?? dayPart.map { (core.settings.hour(for: $0), 0) }
            let anchor = date ?? today
            if monthlyFromDue { finalRule = .monthly(day: core.calendar.component(.day, from: anchor)) }
            due = core.firstOccurrence(of: finalRule, from: anchor, time: time, now: now)
            allDay = time == nil
            rule = finalRule
        } else if clock != nil || dayPart != nil {
            let resolved = clock.map { core.resolve($0, dayPart: dayPart) }
                ?? ParserCore.Resolved(time: (core.settings.hour(for: dayPart!), 0), shift: 0, alternative: nil)
            let base = date ?? today
            var candidate = core.at(resolved.time, on: core.add(resolved.shift, to: base))
            if candidate <= now {
                if date == nil {
                    if let alt = resolved.alternative, core.at(alt, on: base) > now {
                        candidate = core.at(alt, on: base)
                    } else {
                        candidate = core.add(1, to: candidate)
                    }
                } else if pickedWeekday {
                    candidate = core.add(7, to: candidate)
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

        let task = ParsedTask(
            title: ParserCore.cleanTitle(cursor.remaining, fallback: text, edge: Self.edge),
            due: due,
            allDay: allDay,
            remindOffset: remindOffset,
            repeatRule: rule
        )
        return (task, cursor.consumed)
    }


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

    static let edge = #"(?i)^(?:dan|,|-|pada|tgl|tanggal|jam|pukul|nanti)\s+|\s+(?:dan|pada|tgl|tanggal|jam|pukul|nanti|di|,|-)$|^[,\-]+|[,\-]+$"#
}

enum IndonesianPatterns {
    static let num = #"(?:\d{1,3}|(?:dua|tiga|empat|lima)\s+puluh(?:\s+(?:satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan))?|(?:dua|tiga|empat|lima|enam|tujuh|delapan|sembilan)\s+belas|sebelas|sepuluh|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan)"#
    static let day = #"(?:senin|selasa|rabu|kamis|jum'?at|sabtu|minggu|ahad)"#
    static let dayList = "\(day)(?:\\s*(?:,|dan|&)\\s*\(day))*"
    static let month = #"(?:januari|februari|maret|april|mei|juni|juli|agustus|september|oktober|november|desember|jan|feb|mar|apr|jun|jul|agu|agt|ags|sep|sept|okt|nov|des)"#
    static let part = #"(pagi|siang|sore|malam|subuh)"#
    static let amount = "(setengah\\s+jam|sejam|(\(num))\\s*(menit|mnt|jam|hari))"
    static let remindVerb = #"(?:ingetin|ingatkan|ingatin|ingetkan|remind(?:er)?)(?:\s+(?:aku|saya|gue|gw))?"#

    static let remindAmount = regex("\\b\(remindVerb)\\s+\(amount)\\s+(?:sebelum(?:nya)?|sblm(?:nya)?)\\b")
    static let amountBefore = regex("\\b\(amount)\\s+(?:sebelum(?:nya)?|sblm(?:nya)?)\\b")
    static let remindWord = regex("\\b\(remindVerb)\\b")

    static let everyWorkday = regex(#"\b(?:tiap|setiap)\s+hari\s+kerja\b"#)
    static let everyDayNamed = regex("\\b(?:tiap|setiap)\\s+hari\\s+(\(dayList))\\b")
    static let everyN = regex("\\b(?:tiap|setiap)\\s+(\(num))\\s+(hari|minggu)\\b")
    static let everyWeek = regex(#"\b(?:tiap|setiap)\s+(?:minggu|pekan)\b(?!\s*(?:,|dan|&))"#)
    static let everyDays = regex("\\b(?:tiap|setiap)\\s+(\(dayList))\\b")
    static let everyDay = regex(#"\b(?:tiap|setiap)\s+hari\b"#)
    static let everyDayPart = regex("\\b(?:tiap|setiap)\\s+\(part)\\b")
    static let everyDate = regex(#"\b(?:tiap|setiap)\s+(?:tanggal|tgl)\s*(\d{1,2})\b"#)
    static let everyMonth = regex(#"\b(?:tiap|setiap)\s+bulan\b"#)
    static let everyYear = regex(#"\b(?:tiap|setiap)\s+tahun\b"#)

    static let fromNow = regex("\\b(?:dalam\\s+)?(setengah\\s+jam|sejam|(\(num))\\s*(menit|mnt|jam|hari|minggu|bulan))\\s+lagi\\b")

    static let today = regex(#"\bhari\s+ini\b"#)
    static let dayAfterTomorrow = regex(#"\blusa\b"#)
    static let tomorrow = regex(#"\b(?:besok|besuk|bsk)\b"#)
    static let sundayExplicit = regex(#"\bhari\s+minggu(?:\s+(depan|ini))?\b"#)
    static let nextWeek = regex(#"\b(?:minggu|pekan)\s+depan\b"#)
    static let nextMonth = regex(#"\bbulan\s+depan\b"#)
    static let weekday = regex("\\b(?:hari\\s+)?(\(day))(?:\\s+(depan|ini))?\\b")
    static let dateKeyword = regex("\\b(?:tgl|tanggal)\\.?\\s*(\\d{1,2})(?:\\s+(\(month))|[/-](\\d{1,2}))?(?:\\s+(\\d{4}))?\\b")
    static let dayMonthName = regex("\\b(\\d{1,2})\\s+(\(month))(?:\\s+(\\d{4}))?\\b")
    static let slashDate = regex(#"\b(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?\b"#)

    static let nantiBeforeClock = regex(#"\bnanti\b(?=\s+(?:jam|pukul|pkl)\b)"#)
    static let clock = regex("\\b(?:jam|pukul|pkl)\\s+(setengah\\s+)?(\(num))(?:\\s*[.:]\\s*(\\d{2})|\\s+(lewat|lebih|kurang)\\s+(seperempat|\(num))(?:\\s*menit)?)?(?:\\s+(?:nanti\\s+)?\(part))?\\b")
    static let bareClock = regex("\\b(\\d{1,2})[.:](\\d{2})\\b(?:\\s+\(part)\\b)?")
    static let dayPartThis = regex("\\b\(part)\\s+ini\\b")
    static let dayPart = regex("\\b(nanti\\s+)?\(part)\\b")
}

