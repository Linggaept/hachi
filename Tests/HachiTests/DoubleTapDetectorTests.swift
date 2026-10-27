import AppKit
import Testing
@testable import Hachi

private let none: NSEvent.ModifierFlags = []
private let option: NSEvent.ModifierFlags = [.option]

/// Pembungkus supaya `#expect` bisa memanggil detektor yang `mutating`.
private final class Keys {
    var detector = DoubleTapDetector()

    func change(_ flags: NSEvent.ModifierFlags, at time: TimeInterval) -> Bool {
        detector.modifiersChanged(flags, at: time)
    }

    func interrupt() { detector.interrupt() }

    /// Satu ketukan ⌥: tekan di `down`, lepas di `up`. True bila ketukan ini melengkapi ketuk dua kali.
    @discardableResult
    func tap(_ down: TimeInterval, _ up: TimeInterval) -> Bool {
        #expect(!change(option, at: down))
        return change(none, at: up)
    }
}

@Test func ketukDuaKaliCepat() {
    let d = Keys()
    #expect(!d.tap(0, 0.08))
    #expect(d.tap(0.25, 0.33))
}

@Test func ketukanLambatTidakDihitung() {
    let d = Keys()
    d.tap(0, 0.08)
    #expect(!d.tap(0.8, 0.88))
}

@Test func ketukanKeduaJadiAwalPasanganBaru() {
    let d = Keys()
    d.tap(0, 0.08)
    d.tap(0.8, 0.88)
    #expect(d.tap(1.0, 1.08))
}

@Test func tahanLamaBukanKetukan() {
    let d = Keys()
    d.tap(0, 0.08)
    #expect(!d.tap(0.2, 1.2))
    #expect(!d.tap(1.3, 1.38))
}

@Test func ketukTigaKaliHanyaSekali() {
    let d = Keys()
    d.tap(0, 0.08)
    #expect(d.tap(0.2, 0.28))
    #expect(!d.tap(0.4, 0.48))
}

@Test func optionDenganTombolLainBatal() {
    let d = Keys()
    d.tap(0, 0.08)
    #expect(!d.change(option, at: 0.2))
    d.interrupt() // ⌥E, ⌥Space, dan sejenisnya
    #expect(!d.change(none, at: 0.28))
    #expect(!d.tap(0.4, 0.48))
}

@Test func tombolLainDiAntaraKetukanBatal() {
    let d = Keys()
    d.tap(0, 0.08)
    d.interrupt()
    #expect(!d.tap(0.2, 0.28))
}

@Test func optionBersamaModifierLainBatal() {
    let d = Keys()
    d.tap(0, 0.08)
    #expect(!d.change(option, at: 0.2))
    #expect(!d.change([.option, .command], at: 0.22))
    #expect(!d.change(option, at: 0.25))
    #expect(!d.change(none, at: 0.28))
    #expect(!d.tap(0.35, 0.4))
}

@Test func lepasModifierLainMenyisakanOptionBukanKetukan() {
    let d = Keys()
    #expect(!d.change([.command], at: 0))
    #expect(!d.change([.option, .command], at: 0.05))
    #expect(!d.change(option, at: 0.1))
    #expect(!d.change(none, at: 0.15))
    #expect(!d.tap(0.25, 0.3))
}

@Test func capsLockDanFnDiabaikan() {
    let d = Keys()
    #expect(!d.change([.option, .capsLock], at: 0))
    #expect(!d.change([.capsLock], at: 0.08))
    #expect(!d.change([.option, .capsLock, .function], at: 0.25))
    #expect(d.change([.capsLock], at: 0.33))
}

@Test func capsLockSaatOptionDitahanTidakMembatalkan() {
    let d = Keys()
    d.tap(0, 0.08)
    #expect(!d.change(option, at: 0.2))
    #expect(!d.change([.option, .capsLock], at: 0.22))
    #expect(d.change([.capsLock], at: 0.28))
}

@Test func modifierLainDiAntaraKetukanBatal() {
    let d = Keys()
    d.tap(0, 0.08)
    #expect(!d.change([.command], at: 0.12))
    #expect(!d.change(none, at: 0.16))
    #expect(!d.tap(0.2, 0.28))
}
