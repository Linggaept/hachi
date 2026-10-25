import Foundation
import Testing
@testable import TodoParser

private let jakarta = TimeZone(identifier: "Asia/Jakarta")!

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = jakarta
    c.firstWeekday = 2
    return c
}

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

/// Jumat, 23 Oktober 2026 pukul 10.00.
private let friday10 = at(2026, 10, 23, 10, 0)

private func parse(_ text: String, prefer language: ParserLanguage = .indonesian) -> ParsedTask {
    TaskParser(settings: ParserSettings(preferredLanguage: language), calendar: calendar).parse(text, now: friday10)
}

@Test func seriPakaiBahasaPilihan() {
    let t = parse("beli kopi", prefer: .english)
    #expect(t.title == "Beli kopi")
    #expect(t.due == nil)
}
