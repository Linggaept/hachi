import AppKit

/// Siluet kepala Shiba untuk menu bar. Gambar template satu warna, jadi ikut mode terang/gelap.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()

            let head = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.0, width: 15, height: 11.5))
            head.fill()
            for ear in [
                [NSPoint(x: 2.6, y: 8.0), NSPoint(x: 4.0, y: 16.4), NSPoint(x: 8.2, y: 11.8)],
                [NSPoint(x: 15.4, y: 8.0), NSPoint(x: 14.0, y: 16.4), NSPoint(x: 9.8, y: 11.8)],
            ] {
                let path = NSBezierPath()
                path.move(to: ear[0])
                path.line(to: ear[1])
                path.line(to: ear[2])
                path.close()
                path.lineJoinStyle = .round
                path.lineWidth = 1.2
                path.fill()
                NSColor.black.setStroke()
                path.stroke()
            }

            // Mata dan moncong dilubangi supaya wajahnya terbaca sebagai anjing di ukuran kecil.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 4.9, y: 7.6, width: 1.9, height: 2.1)).fill()
            NSBezierPath(ovalIn: NSRect(x: 11.2, y: 7.6, width: 1.9, height: 2.1)).fill()
            NSBezierPath(ovalIn: NSRect(x: 5.4, y: 1.9, width: 7.2, height: 5.0)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: NSRect(x: 7.6, y: 4.3, width: 2.8, height: 1.9)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Hachi"
        return image
    }
}
