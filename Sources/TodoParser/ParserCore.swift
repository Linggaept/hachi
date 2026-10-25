import Foundation

/// Logika tanggal dan jam yang sama untuk semua bahasa.
struct ParserCore {
    let settings: ParserSettings
    let calendar: Calendar


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

    /// Tanpa keterangan: hari itu yang terdekat (bisa hari ini).
    /// `next` ("depan", "next"): hari itu di minggu depan (minggu dimulai Senin).
    func weekday(_ wanted: Int, next: Bool, today: Date) -> Date {
        let todayIndex = (calendar.component(.weekday, from: today) + 5) % 7
        let wantedIndex = (wanted + 5) % 7
        if next {
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

    // MARK: - Gabungkan

    /// Bagian kalimat yang sudah dikenali, sebelum digabung jadi waktu tugas.
    struct Pieces {
        var remindOffset: TimeInterval?
        var explicitRemind = false
        var rule: RepeatRule?
        var monthlyFromDue = false
        var exactDue: Date?
        var date: Date?
        var pickedWeekday = false
        var clock: Clock?
        /// Jam pasti (am/pm, noon, midnight) yang tidak perlu ditebak pagi atau malam.
        var fixedTime: Resolved?
        var dayPart: DayPart?
    }

    func assemble(_ p: Pieces, title: String, now: Date) -> ParsedTask {
        let today = calendar.startOfDay(for: now)
        let resolved = p.fixedTime ?? p.clock.map { resolve($0, dayPart: p.dayPart) }
        var rule = p.rule
        var due: Date?
        var allDay = false
        if let exactDue = p.exactDue {
            due = exactDue
        } else if let baseRule = rule {
            var finalRule = baseRule
            let time = resolved?.time ?? p.dayPart.map { (settings.hour(for: $0), 0) }
            let anchor = p.date ?? today
            if p.monthlyFromDue { finalRule = .monthly(day: calendar.component(.day, from: anchor)) }
            due = firstOccurrence(of: finalRule, from: anchor, time: time, now: now)
            allDay = time == nil
            rule = finalRule
        } else if resolved != nil || p.dayPart != nil {
            let resolved = resolved ?? Resolved(time: (settings.hour(for: p.dayPart!), 0), shift: 0, alternative: nil)
            let base = p.date ?? today
            var candidate = at(resolved.time, on: add(resolved.shift, to: base))
            if candidate <= now {
                if p.date == nil {
                    if let alt = resolved.alternative, at(alt, on: base) > now {
                        candidate = at(alt, on: base)
                    } else {
                        candidate = add(1, to: candidate)
                    }
                } else if p.pickedWeekday {
                    candidate = add(7, to: candidate)
                }
            }
            due = candidate
        } else if let date = p.date {
            due = date
            allDay = true
        }

        var remindOffset = p.remindOffset
        if due == nil {
            remindOffset = nil
        } else if !allDay || p.explicitRemind {
            remindOffset = remindOffset ?? 0
        }
        return ParsedTask(title: title, due: due, allDay: allDay, remindOffset: remindOffset, repeatRule: rule)
    }

    /// Merapikan sisa kalimat jadi judul. `edge` = pola kata sambung yang dibuang dari ujung judul.
    static func cleanTitle(_ remaining: String, fallback: String, edge: String) -> String {
        var title = remaining
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        while let range = title.range(of: edge, options: .regularExpression) {
            title.removeSubrange(range)
            title = title.trimmingCharacters(in: .whitespaces)
        }
        if title.isEmpty { title = fallback.trimmingCharacters(in: .whitespaces) }
        guard let first = title.first else { return title }
        return first.uppercased() + title.dropFirst()
    }
}

/// Membuat regex tanpa membedakan huruf besar/kecil.
func regex(_ pattern: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
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
    /// Jumlah karakter yang sudah dibaca sebagai bagian waktu; dipakai memilih bahasa.
    private(set) var consumed = 0

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
            consumed += result.range.length
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
