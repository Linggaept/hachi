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

private func parse(_ text: String, now: Date = friday10) -> ParsedTask {
    TaskParser(calendar: calendar).parse(text, now: now)
}

// MARK: - Contoh utama

@Test func contohUtama() {
    let t = parse("besok jam 3 sore call client ingetin 30 menit sebelumnya")
    #expect(t.title == "Call client")
    #expect(t.due == at(2026, 10, 24, 15))
    #expect(t.allDay == false)
    #expect(t.remindOffset == 1800)
}

@Test func tanpaWaktu() {
    let t = parse("beli kopi")
    #expect(t.title == "Beli kopi")
    #expect(t.due == nil)
    #expect(t.remindOffset == nil)
    #expect(t.repeatRule == nil)
}

@Test func tiapSeninJam9() {
    let t = parse("tiap senin jam 9 cek backup server")
    #expect(t.title == "Cek backup server")
    #expect(t.due == at(2026, 10, 26, 9))
    #expect(t.repeatRule == .weekly(every: 1, weekdays: [2]))
    #expect(t.remindOffset == 0)
}

@Test func menitLagi() {
    let t = parse("30 menit lagi angkat jemuran")
    #expect(t.title == "Angkat jemuran")
    #expect(t.due == at(2026, 10, 23, 10, 30))
    #expect(t.allDay == false)
}

@Test func jumatDepanSeharian() {
    let t = parse("jumat depan deadline proposal")
    #expect(t.title == "Deadline proposal")
    #expect(t.due == at(2026, 10, 30))
    #expect(t.allDay)
    #expect(t.remindOffset == nil)
}

// MARK: - Jam

@Test func jamKecilDianggapSiang() {
    #expect(parse("jam 3 rapat").due == at(2026, 10, 23, 15))
}

@Test func jamPagiYangLewatPindahKeMalam() {
    // Pukul 10.00, "jam 8" pagi sudah lewat, jadi diambil 20.00 hari ini.
    #expect(parse("jam 8 nonton").due == at(2026, 10, 23, 20))
}

@Test func jamPagiBelumLewat() {
    #expect(parse("jam 7 lari", now: at(2026, 10, 23, 6)).due == at(2026, 10, 23, 7))
}

@Test func jamSamaDenganSekarangDianggapLewat() {
    #expect(parse("jam 10 meeting").due == at(2026, 10, 23, 22))
}

@Test func jamTegasYangLewatPindahBesok() {
    #expect(parse("jam 09.30 standup").due == at(2026, 10, 24, 9, 30))
}

@Test func jamDenganTitik() {
    let t = parse("jam 15.30 meeting")
    #expect(t.title == "Meeting")
    #expect(t.due == at(2026, 10, 23, 15, 30))
}

@Test func jamTanpaKataJam() {
    #expect(parse("meeting 14:15").due == at(2026, 10, 23, 14, 15))
}

@Test func angkaKataDanPagi() {
    let t = parse("lusa jam sembilan pagi bayar tagihan internet")
    #expect(t.title == "Bayar tagihan internet")
    #expect(t.due == at(2026, 10, 25, 9))
}

@Test func setengah() {
    let t = parse("jam setengah lima jemput adik")
    #expect(t.title == "Jemput adik")
    #expect(t.due == at(2026, 10, 23, 16, 30))
}

@Test func lewatMenit() {
    let t = parse("jam 7 lewat 15 malam makan")
    #expect(t.title == "Makan")
    #expect(t.due == at(2026, 10, 23, 19, 15))
}

@Test func kurangSeperempat() {
    #expect(parse("jam 5 kurang seperempat sore pulang").due == at(2026, 10, 23, 16, 45))
}

@Test func jamDuaBelasMalam() {
    #expect(parse("jam 12 malam deploy").due == at(2026, 10, 24, 0))
}

@Test func jamSatuSiang() {
    #expect(parse("jam 1 siang makan").due == at(2026, 10, 23, 13))
}

@Test func jamDuaPuluhSatu() {
    #expect(parse("jam dua puluh satu tidur").due == at(2026, 10, 23, 21))
}

@Test func pukul() {
    #expect(parse("pukul 14 bayar").due == at(2026, 10, 23, 14))
}

// MARK: - Bagian hari

@Test func nantiMalam() {
    let t = parse("nanti malam telpon ibu")
    #expect(t.title == "Telpon ibu")
    #expect(t.due == at(2026, 10, 23, 20))
}

@Test func besokPagi() {
    let t = parse("besok pagi beli roti")
    #expect(t.title == "Beli roti")
    #expect(t.due == at(2026, 10, 24, 8))
}

@Test func soreIni() {
    let t = parse("sore ini servis motor")
    #expect(t.title == "Servis motor")
    #expect(t.due == at(2026, 10, 23, 16))
}

@Test func bagianHariDiTengahJudulDibiarkan() {
    let t = parse("makan malam bareng tim")
    #expect(t.title == "Makan malam bareng tim")
    #expect(t.due == nil)
}

@Test func besokSoreJam4() {
    #expect(parse("besok sore jam 4 futsal").due == at(2026, 10, 24, 16))
}

@Test func jamBagianHariDariPengaturan() {
    let settings = ParserSettings(morningHour: 7, noonHour: 12, afternoonHour: 15, eveningHour: 19)
    let t = TaskParser(settings: settings, calendar: calendar).parse("besok pagi lari", now: friday10)
    #expect(t.due == at(2026, 10, 24, 7))
}

// MARK: - Tanggal

@Test func hariIni() {
    let t = parse("hari ini jam 14 bayar")
    #expect(t.title == "Bayar")
    #expect(t.due == at(2026, 10, 23, 14))
}

@Test func hariIniSeharian() {
    let t = parse("kirim berkas hari ini")
    #expect(t.title == "Kirim berkas")
    #expect(t.due == at(2026, 10, 23))
    #expect(t.allDay)
}

@Test func tanggalBulanIni() {
    let t = parse("tgl 25 bayar listrik")
    #expect(t.title == "Bayar listrik")
    #expect(t.due == at(2026, 10, 25))
    #expect(t.allDay)
}

@Test func tanggalYangLewatKeBulanDepan() {
    #expect(parse("tanggal 5 bayar kos").due == at(2026, 11, 5))
}

@Test func tanggalDenganNamaBulan() {
    let t = parse("1 nov ulang tahun ibu")
    #expect(t.title == "Ulang tahun ibu")
    #expect(t.due == at(2026, 11, 1))
}

@Test func tanggalNamaBulanPanjangDanTahun() {
    #expect(parse("rapat 3 maret 2027").due == at(2027, 3, 3))
}

@Test func tanggalGarisMiringLewatKeTahunDepan() {
    #expect(parse("15/1 perpanjang sim").due == at(2027, 1, 15))
}

@Test func tanggalGarisMiringDenganTahun() {
    #expect(parse("ujian 2/11/2026 jam 8 pagi").due == at(2026, 11, 2, 8))
}

@Test func namaHariTerdekat() {
    #expect(parse("senin presentasi").due == at(2026, 10, 26))
}

@Test func namaHariDepanBerartiMingguDepan() {
    #expect(parse("senin depan presentasi").due == at(2026, 10, 26))
    #expect(parse("rabu depan presentasi").due == at(2026, 10, 28))
}

@Test func namaHariIni() {
    #expect(parse("sabtu ini jam 10 pagi cuci mobil").due == at(2026, 10, 24, 10))
}

@Test func hariMingguBukanPekan() {
    let t = parse("hari minggu futsal")
    #expect(t.title == "Futsal")
    #expect(t.due == at(2026, 10, 25))
}

@Test func mingguDepan() {
    let t = parse("minggu depan liburan")
    #expect(t.title == "Liburan")
    #expect(t.due == at(2026, 10, 30))
}

@Test func hariIniYangJamnyaLewatPindahPekanDepan() {
    // Jumat 10.00, "jumat jam 9" sudah lewat, jadi Jumat berikutnya.
    #expect(parse("jumat jam 9 pagi jumatan").due == at(2026, 10, 30, 9))
}

@Test func bulanDepan() {
    #expect(parse("bulan depan servis ac").due == at(2026, 11, 23))
}

@Test func hariLagi() {
    let t = parse("3 hari lagi kirim laporan")
    #expect(t.title == "Kirim laporan")
    #expect(t.due == at(2026, 10, 26))
    #expect(t.allDay)
}

@Test func jamLagi() {
    #expect(parse("2 jam lagi cek oven").due == at(2026, 10, 23, 12))
    #expect(parse("setengah jam lagi istirahat").due == at(2026, 10, 23, 10, 30))
    #expect(parse("sejam lagi angkat telepon").due == at(2026, 10, 23, 11))
}

// MARK: - Pengingat

@Test func ingetinTanpaJumlah() {
    let t = parse("ingetin aku jam 4 sore angkat jemuran")
    #expect(t.title == "Angkat jemuran")
    #expect(t.due == at(2026, 10, 23, 16))
    #expect(t.remindOffset == 0)
}

@Test func pengingatSehari() {
    let t = parse("besok rapat ingatkan 1 hari sebelumnya")
    #expect(t.title == "Rapat")
    #expect(t.allDay)
    #expect(t.remindOffset == 86400)
}

@Test func pengingatTanpaKataIngetin() {
    let t = parse("jam 3 meeting 15 menit sebelumnya")
    #expect(t.title == "Meeting")
    #expect(t.remindOffset == 900)
}

@Test func pengingatSetengahJam() {
    #expect(parse("jam 3 meeting ingetin setengah jam sebelumnya").remindOffset == 1800)
}

// MARK: - Berulang

@Test func tiapHari() {
    let t = parse("tiap hari jam 7 minum vitamin")
    #expect(t.title == "Minum vitamin")
    #expect(t.repeatRule == .daily(every: 1))
    #expect(t.due == at(2026, 10, 24, 7))
}

@Test func tiapTanggal() {
    let t = parse("tiap tanggal 1 bayar internet")
    #expect(t.title == "Bayar internet")
    #expect(t.repeatRule == .monthly(day: 1))
    #expect(t.due == at(2026, 11, 1))
    #expect(t.allDay)
}

@Test func tiapDuaHari() {
    let t = parse("tiap senin dan kamis gym")
    #expect(t.title == "Gym")
    #expect(t.repeatRule == .weekly(every: 1, weekdays: [2, 5]))
    #expect(t.due == at(2026, 10, 26))
}

@Test func tiapMingguBerartiPekanan() {
    let t = parse("tiap minggu bersihin kamar")
    #expect(t.title == "Bersihin kamar")
    #expect(t.repeatRule == .weekly(every: 1, weekdays: []))
    #expect(t.due == at(2026, 10, 23))
}

@Test func tiapHariMinggu() {
    let t = parse("setiap hari minggu cuci motor")
    #expect(t.repeatRule == .weekly(every: 1, weekdays: [1]))
    #expect(t.due == at(2026, 10, 25))
}

@Test func tiapHariKerja() {
    let t = parse("tiap hari kerja jam 9 pagi absen")
    #expect(t.repeatRule == .weekly(every: 1, weekdays: [2, 3, 4, 5, 6]))
    #expect(t.due == at(2026, 10, 26, 9))
}

@Test func tiapDuaMinggu() {
    let t = parse("tiap 2 minggu potong rambut")
    #expect(t.title == "Potong rambut")
    #expect(t.repeatRule == .weekly(every: 2, weekdays: []))
}

@Test func tiapPagi() {
    let t = parse("tiap pagi siram tanaman")
    #expect(t.title == "Siram tanaman")
    #expect(t.repeatRule == .daily(every: 1))
    #expect(t.due == at(2026, 10, 24, 8))
}

@Test func tiapBulan() {
    let t = parse("tiap bulan bayar kartu kredit")
    #expect(t.repeatRule == .monthly(day: 23))
    #expect(t.due == at(2026, 10, 23))
}

// MARK: - Judul

@Test func kataYangMemuatJamTidakTerbaca() {
    let t = parse("kembalikan buku pinjam")
    #expect(t.title == "Kembalikan buku pinjam")
    #expect(t.due == nil)
}

@Test func hurufBesarDipertahankan() {
    #expect(parse("Besok jam 10 call Andi soal API").title == "Call Andi soal API")
}

@Test func kataPenghubungDiUjungDibuang() {
    #expect(parse("bayar kos pada tgl 5").title == "Bayar kos")
}

@Test func kalimatHanyaWaktuTetapPunyaJudul() {
    #expect(parse("besok jam 3").title == "Besok jam 3")
}

// MARK: - Aturan berulang

@Test func berikutnyaMingguan() {
    let rule = RepeatRule.weekly(every: 1, weekdays: [2, 5])
    #expect(rule.next(after: at(2026, 10, 26, 9), calendar: calendar) == at(2026, 10, 29, 9))
    #expect(rule.next(after: at(2026, 10, 29, 9), calendar: calendar) == at(2026, 11, 2, 9))
}

@Test func berikutnyaBulananAkhirBulan() {
    let rule = RepeatRule.monthly(day: 31)
    #expect(rule.next(after: at(2027, 1, 31), calendar: calendar) == at(2027, 2, 28))
    #expect(rule.next(after: at(2027, 2, 28), calendar: calendar) == at(2027, 3, 31))
}

@Test func berikutnyaDuaMinggu() {
    let rule = RepeatRule.weekly(every: 2, weekdays: [])
    #expect(rule.next(after: at(2026, 10, 23, 8), calendar: calendar) == at(2026, 11, 6, 8))
}

@Test func berikutnyaMelewatiYangTerlewat() {
    let rule = RepeatRule.daily(every: 1)
    let next = rule.next(after: at(2026, 10, 20, 7), notBefore: friday10, calendar: calendar)
    #expect(next == at(2026, 10, 24, 7))
}

@Test func simpanDanBacaAturan() {
    let rules: [RepeatRule] = [
        .daily(every: 1), .daily(every: 3), .weekly(every: 1, weekdays: [2, 5]),
        .weekly(every: 2, weekdays: []), .monthly(day: 15), .yearly,
    ]
    for rule in rules {
        #expect(RepeatRule(storage: rule.storage) == rule)
    }
}

@Test func labelAturan() {
    #expect(RepeatRule.daily(every: 1).label == "Tiap hari")
    #expect(RepeatRule.weekly(every: 1, weekdays: [2, 5]).label == "Tiap Senin & Kamis")
    #expect(RepeatRule.weekly(every: 1, weekdays: [2, 3, 4, 5, 6]).label == "Tiap hari kerja")
    #expect(RepeatRule.monthly(day: 1).label == "Tiap tanggal 1")
}
