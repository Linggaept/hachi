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

private func en(_ text: String, now: Date = friday10, monthFirst: Bool = false) -> ParsedTask {
    TaskParser(settings: ParserSettings(preferredLanguage: .english, monthFirst: monthFirst), calendar: calendar)
        .parse(text, now: now)
}

// MARK: - Tanggal dan jam

@Test func besokJamSore() {
    let t = en("tomorrow 3pm call client")
    #expect(t.title == "Call client")
    #expect(t.due == at(2026, 10, 24, 15))
    #expect(t.allDay == false)
}

@Test func hariIniMalam() {
    let t = en("call mom tonight")
    #expect(t.title == "Call mom")
    #expect(t.due == at(2026, 10, 23, 20))
}

@Test func lusa() {
    let t = en("day after tomorrow pay rent")
    #expect(t.title == "Pay rent")
    #expect(t.due == at(2026, 10, 25))
    #expect(t.allDay)
}

@Test func namaHari() {
    let t = en("friday deadline proposal")
    #expect(t.title == "Deadline proposal")
    #expect(t.due == at(2026, 10, 23))
    #expect(t.allDay)
}

@Test func hariDepan() {
    let t = en("next friday deadline proposal")
    #expect(t.title == "Deadline proposal")
    #expect(t.due == at(2026, 10, 30))
}

@Test func singkatanHari() {
    let t = en("wed standup at 9")
    #expect(t.title == "Standup")
    #expect(t.due == at(2026, 10, 28, 9))
}

@Test func tanggalNamaBulan() {
    #expect(en("oct 25 pay electricity").due == at(2026, 10, 25))
    let t = en("25th october pay electricity")
    #expect(t.title == "Pay electricity")
    #expect(t.due == at(2026, 10, 25))
    #expect(t.allDay)
}

@Test func tanggalKe() {
    let t = en("on the 5th renew domain")
    #expect(t.title == "Renew domain")
    #expect(t.due == at(2026, 11, 5))
}

@Test func tanggalIso() {
    let t = en("2026-12-01 submit report")
    #expect(t.title == "Submit report")
    #expect(t.due == at(2026, 12, 1))
}

@Test func tanggalAngkaBulanDulu() {
    let t = en("12/1 submit report", monthFirst: true)
    #expect(t.title == "Submit report")
    #expect(t.due == at(2026, 12, 1))
}

@Test func tanggalAngkaHariDulu() {
    #expect(en("12/1 submit report", monthFirst: false).due == at(2027, 1, 12))
}

@Test func jamTitikDua() {
    let t = en("standup at 15:30")
    #expect(t.title == "Standup")
    #expect(t.due == at(2026, 10, 23, 15, 30))
}

@Test func jamTanpaAmPm() {
    #expect(en("at 3 gym").due == at(2026, 10, 23, 15))
    #expect(en("at 8 read").due == at(2026, 10, 23, 20))
}

@Test func siangTengahMalam() {
    #expect(en("lunch at noon").due == at(2026, 10, 23, 12))
    #expect(en("deploy at midnight").due == at(2026, 10, 24, 0))
}

@Test func setengahLewat() {
    let t = en("half past 4 pick up kids")
    #expect(t.title == "Pick up kids")
    #expect(t.due == at(2026, 10, 23, 16, 30))
    #expect(en("quarter to 5 call").due == at(2026, 10, 23, 16, 45))
}

@Test func bagianHari() {
    let run = en("tomorrow morning run")
    #expect(run.title == "Run")
    #expect(run.due == at(2026, 10, 24, 8))
    let dinner = en("this evening dinner with Sam")
    #expect(dinner.title == "Dinner with Sam")
    #expect(dinner.due == at(2026, 10, 23, 20))
}

@Test func dariSekarang() {
    let t = en("in 30 minutes take out laundry")
    #expect(t.title == "Take out laundry")
    #expect(t.due == at(2026, 10, 23, 10, 30))
    #expect(en("in an hour call").due == at(2026, 10, 23, 11))
    #expect(en("in half an hour call").due == at(2026, 10, 23, 10, 30))
    let days = en("in 3 days call")
    #expect(days.due == at(2026, 10, 26))
    #expect(days.allDay)
    #expect(en("30 minutes from now call").due == at(2026, 10, 23, 10, 30))
}

@Test func mingguBulanDepan() {
    #expect(en("next week dentist").due == at(2026, 10, 30))
    #expect(en("next month renew insurance").due == at(2026, 11, 23))
}

@Test func duaBelasAmPm() {
    #expect(en("12am backup").due == at(2026, 10, 24, 0))
    #expect(en("12pm lunch").due == at(2026, 10, 23, 12))
}

@Test func bulanSebagaiKataBiasa() {
    let t = en("may need to buy milk")
    #expect(t.title == "May need to buy milk")
    #expect(t.due == nil)
    #expect(en("march on").due == nil)
}
