// Membuat iconset dari Resources/AppIcon.png (dipanggil build-app.sh bila AppIcon.icns belum ada atau kalah baru).
// Bagian squircle di gambar sumber dipotong, lalu dipasang ulang ke bentuk dan ukuran grid ikon macOS
// (badan 824 px di kanvas 1024 px, sudut melengkung halus, bayangan tipis).
import AppKit

let source = CommandLine.arguments[1]
let out = CommandLine.arguments[2]
let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
    ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
]

let rep = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: source)))!
let w = rep.pixelsWide, h = rep.pixelsHigh
func opaque(_ x: Int, _ y: Int) -> Bool { rep.colorAt(x: x, y: y)!.alphaComponent > 0.95 }
let row = (0..<w).filter { opaque($0, h / 2) }
let top = (0..<h).first { opaque(w / 2, $0) }!
// Sedikit ke dalam supaya tepi lembut gambar sumber tidak ikut.
let inset = Int(Double(row.last! - row.first!) * 0.01)
let side = row.last! - row.first! + 1 - inset * 2
let body = rep.cgImage!.cropping(to: CGRect(x: row.first! + inset, y: top + inset, width: side, height: side))!
let base = rep.colorAt(x: row.first! + inset + 4, y: h / 2)!.withAlphaComponent(1)

/// Superelips (n = 5), mendekati bentuk ikon macOS.
func squircle(in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    let n = 5.0, steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let point = NSPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        i == 0 ? path.move(to: point) : path.line(to: point)
    }
    path.close()
    return path
}

try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in sizes {
    let s = CGFloat(px)
    let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
    NSGraphicsContext.current?.imageInterpolation = .high
    let rect = NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let shape = squircle(in: rect)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 12 / 1024
    shadow.shadowOffset = NSSize(width: 0, height: -s * 6 / 1024)
    shadow.set()
    base.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    shape.addClip()
    // Sudut squircle sumber lebih bulat daripada bentuk macOS; gambar diperbesar sedikit supaya sudutnya tertutup.
    NSImage(cgImage: body, size: NSSize(width: side, height: side)).draw(in: rect.insetBy(dx: -rect.width * 0.04, dy: -rect.height * 0.04))
    NSGraphicsContext.restoreGraphicsState()
    try canvas.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
