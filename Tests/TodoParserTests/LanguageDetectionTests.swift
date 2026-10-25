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

@Test func inggrisDikenaliOtomatis() {
    let t = parse("tomorrow 3pm call client", prefer: .indonesian)
    #expect(t.title == "Call client")
    #expect(t.due == at(2026, 10, 24, 15))
}

@Test func indonesiaDikenaliOtomatis() {
    let t = parse("besok jam 3 sore call client", prefer: .english)
    #expect(t.title == "Call client")
    #expect(t.due == at(2026, 10, 24, 15))
}

@Test func pemenangKarakterTerbanyak() {
    let t = parse("meeting at 15.30", prefer: .indonesian)
    #expect(t.title == "Meeting")
    #expect(t.due == at(2026, 10, 23, 15, 30))
}

@Test func kataInggrisDiKalimatIndonesia() {
    let meeting = parse("meeting tiap senin jam 9", prefer: .english)
    #expect(meeting.title == "Meeting")
    #expect(meeting.repeatRule == .weekly(every: 1, weekdays: [2]))
    #expect(meeting.due == at(2026, 10, 26, 9))
    let deadline = parse("deadline proposal jumat depan", prefer: .english)
    #expect(deadline.title == "Deadline proposal")
    #expect(deadline.due == at(2026, 10, 30))
}
