import AppKit
import Combine
import SwiftUI

/// Ikon di menu bar. Angka di sebelah ikon = jumlah tugas terlambat.
@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: TaskStore
    private let state: MenuPanelState
    private var bag: Set<AnyCancellable> = []

    init(store: TaskStore, settings: AppSettings, actions: MenuActions) {
        self.store = store
        let state = MenuPanelState(store: store, settings: settings)
        self.state = state
        super.init()

        var wrapped = actions
        wrapped.capture = { [weak self] in
            self?.close()
            actions.capture()
        }
        wrapped.edit = { [weak self] task in
            self?.close()
            actions.edit(task)
        }
        wrapped.settings = { [weak self] in
            self?.close()
            actions.settings()
        }

        wrapped.quit = {
            state.commitAll()
            actions.quit()
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: MenuPanelView(store: store, settings: settings, state: state, actions: wrapped)
                .environment(\.locale, Formatting.locale)
        )

        if let button = item.button {
            button.image = MenuBarIcon.make()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle)
        }

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshBadge() }
            .store(in: &bag)
        refreshBadge()
    }

    private func refreshBadge() {
        let overdue = store.overdue.count
        item.button?.title = overdue > 0 ? " \(overdue)" : ""
        item.button?.toolTip = overdue > 0 ? String(localized: "Overdue: \(overdue)") : "Hachi"
    }

    @objc func toggle() {
        popover.isShown ? close() : show()
    }

    func show() {
        guard let button = item.button else { return }
        store.tick()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }

    /// Centang yang masih dalam jeda batal disimpan sebelum app keluar.
    func commitPending() {
        state.commitAll()
    }
}
