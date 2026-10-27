import AppKit
import ApplicationServices

/// Mengenali ketuk ⌥ dua kali dari urutan perubahan modifier. Tanpa AppKit event, jadi bisa dites.
/// Satu ketukan = ⌥ saja ditekan lalu dilepas dalam `maxTapDuration`; ketukan kedua harus mulai paling
/// lambat `maxGap` setelah yang pertama dilepas. ⌥ bersama tombol atau modifier lain membatalkan.
struct DoubleTapDetector {
    var maxTapDuration: TimeInterval = 0.3
    var maxGap: TimeInterval = 0.4

    private static let relevant: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
    private var previous: NSEvent.ModifierFlags = []
    private var pressedAt: TimeInterval?
    private var lastTap: TimeInterval?

    /// Mengembalikan true saat ketukan kedua selesai.
    mutating func modifiersChanged(_ flags: NSEvent.ModifierFlags, at time: TimeInterval) -> Bool {
        let now = flags.intersection(Self.relevant) // Caps Lock dan Fn diabaikan
        defer { previous = now }

        if now == [.option] {
            // ⌥ yang tersisa setelah modifier lain dilepas bukan ketukan; keadaannya sudah direset di bawah.
            if previous.isEmpty {
                pressedAt = time
                if let lastTap, time - lastTap > maxGap { self.lastTap = nil }
            }
            return false
        }

        if now.isEmpty, previous == [.option], let pressedAt {
            self.pressedAt = nil
            guard time - pressedAt <= maxTapDuration else {
                lastTap = nil
                return false
            }
            if lastTap != nil {
                lastTap = nil
                return true
            }
            lastTap = time
            return false
        }

        pressedAt = nil
        if !now.isEmpty { lastTap = nil }
        return false
    }

    /// Tombol biasa atau klik selama/di antara ketukan: bukan ketuk dua kali.
    mutating func interrupt() {
        pressedAt = nil
        lastTap = nil
    }
}

/// Ketuk ⌥ dua kali dari aplikasi mana pun. Membaca tombol di luar Hachi butuh izin Aksesibilitas;
/// tanpa izin itu macOS tidak mengirim event-nya, dan shortcut lain tetap jalan.
@MainActor
final class DoubleTapOption {
    var onDoubleTap: (() -> Void)?

    private var detector = DoubleTapDetector()
    private var monitors: [Any] = []
    private static let watched: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Dikirim macOS saat daftar izin Aksesibilitas berubah.
    static let trustChanged = Notification.Name("com.apple.accessibility.api")

    /// Memunculkan permintaan izin dari macOS bila belum diberi.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func start() {
        stop()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.watched, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        // Event saat Hachi sendiri aktif (kotak catat atau Pengaturan terbuka) tidak lewat monitor global.
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.watched, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        detector.interrupt()
    }

    /// Dipanggil saat shortcut catat cepat ditekan; tombolnya tidak terlihat oleh monitor.
    func interrupt() {
        detector.interrupt()
    }

    private func handle(_ event: NSEvent) {
        if event.type == .flagsChanged {
            if detector.modifiersChanged(event.modifierFlags, at: event.timestamp) { onDoubleTap?() }
        } else {
            detector.interrupt()
        }
    }
}
