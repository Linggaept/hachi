import Foundation

public enum DayPart: String, Sendable, CaseIterable {
    case subuh, pagi, siang, sore, malam
}

public enum ParserLanguage: Sendable {
    case indonesian, english
}

public struct ParserSettings: Equatable, Sendable {
    /// Jam bawaan saat kalimat hanya menyebut bagian hari ("besok pagi").
    public var morningHour: Int
    public var noonHour: Int
    public var afternoonHour: Int
    public var eveningHour: Int
    /// Bahasa yang dipakai bila kedua parser sama kuat (mis. "beli kopi"); app mengisinya dari bahasa tampilan.
    public var preferredLanguage: ParserLanguage
    /// Tanggal angka bahasa Inggris dibaca bulan/tanggal ("10/25"), mengikuti wilayah Mac.
    public var monthFirst: Bool

    public init(
        morningHour: Int = 8, noonHour: Int = 12, afternoonHour: Int = 16, eveningHour: Int = 20,
        preferredLanguage: ParserLanguage = .indonesian, monthFirst: Bool = false
    ) {
        self.morningHour = morningHour
        self.noonHour = noonHour
        self.afternoonHour = afternoonHour
        self.eveningHour = eveningHour
        self.preferredLanguage = preferredLanguage
        self.monthFirst = monthFirst
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

protocol LanguageParser {
    /// `consumed` = jumlah karakter yang dikenali sebagai bagian waktu.
    func parse(_ text: String, now: Date) -> (task: ParsedTask, consumed: Int)
}

/// Membaca kalimat sehari-hari menjadi tugas, tanpa AI. Kalimat dibaca parser Indonesia dan Inggris;
/// yang mengenali bagian waktu paling panjang dipakai, seri memakai `preferredLanguage`.
/// Bagian yang dikenali sebagai waktu dibuang dari judul.
public struct TaskParser: Sendable {
    public var settings: ParserSettings
    public var calendar: Calendar

    public init(settings: ParserSettings = ParserSettings(), calendar: Calendar = .current) {
        self.settings = settings
        self.calendar = calendar
    }

    public func parse(_ text: String, now: Date) -> ParsedTask {
        let core = ParserCore(settings: settings, calendar: calendar)
        let indonesian = IndonesianParser(core: core).parse(text, now: now)
        let english = EnglishParser(core: core).parse(text, now: now)
        if indonesian.consumed != english.consumed {
            return indonesian.consumed > english.consumed ? indonesian.task : english.task
        }
        return settings.preferredLanguage == .english ? english.task : indonesian.task
    }
}
