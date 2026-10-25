import AppKit
import SwiftUI

/// Panel tanpa bingkai yang tetap bisa menerima ketikan tanpa mengaktifkan aplikasi (mirip Spotlight).
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    let model: CaptureModel
    private let panel: KeyPanel
    /// Tepi atas panel dijaga tetap saat tingginya berubah (pratinjau/form muncul).
    private var topY: CGFloat = 0

    init(store: TaskStore, settings: AppSettings) {
        model = CaptureModel(store: store, settings: settings)
        panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 80),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self

        let host = NSHostingController(rootView: CaptureView(model: model, store: store))
        host.sizingOptions = [.preferredContentSize]
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        panel.contentViewController = host

        model.onClose = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel.isVisible }

    func showNew() {
        model.newTask()
        present()
    }

    func showEdit(_ task: TaskItem) {
        model.edit(task)
        present()
    }

    func hide() {
        model.voice.cancel()
        panel.orderOut(nil)
    }

    private func present() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            topY = visible.minY + visible.height * 0.72
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: topY - size.height))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard topY > 0 else { return }
        var frame = panel.frame
        frame.origin.y = topY - frame.height
        panel.setFrame(frame, display: true)
    }

    /// Klik di luar panel menutupnya, kecuali sedang merekam suara.
    func windowDidResignKey(_ notification: Notification) {
        guard !model.voice.isActive else { return }
        hide()
    }
}
