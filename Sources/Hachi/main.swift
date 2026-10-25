import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var store: TaskStore!
    private var scheduler: ReminderScheduler!
    private var briefing: BriefingService!
    private var capture: CapturePanelController!
    private var statusBar: StatusBarController!
    private var settingsWindow: SettingsWindowController!
    private let hotkey = HotKey()
    private var bag: Set<AnyCancellable> = []

    // Tekan = buka catat cepat, tahan = langsung bicara.
    private var pressed = false
    private var holding = false
    private var wasVisible = false
    private var holdTimer: Timer?
    private static let holdDelay: TimeInterval = 0.35

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = AppSettings()
        do {
            store = try TaskStore(settings: settings)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Hachi tidak bisa membuka database"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        scheduler = ReminderScheduler(store: store)
        store.onChange = { [weak self] in self?.scheduler.sync() }
        briefing = BriefingService(store: store, settings: settings, scheduler: scheduler)
        capture = CapturePanelController(store: store, settings: settings)
        settingsWindow = SettingsWindowController { [unowned self] in
            SettingsView(settings: settings, state: SettingsState(), store: store, briefing: briefing, scheduler: scheduler)
        }
        statusBar = StatusBarController(store: store, settings: settings, actions: MenuActions(
            capture: { [weak self] in self?.capture.showNew() },
            edit: { [weak self] task in self?.capture.showEdit(task) },
            settings: { [weak self] in self?.settingsWindow.show() },
            quit: { NSApp.terminate(nil) }
        ))
        scheduler.onOpen = { [weak self] in self?.statusBar.show() }

        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.hotkeyReleased() }
        settings.$hotkey
            .sink { [weak self] choice in self?.hotkey.register(choice) }
            .store(in: &bag)

        Task {
            _ = await scheduler.requestAuthorization()
            scheduler.sync()
            briefing.start()
        }

        if !settings.onboarded {
            if Bundle.main.bundleURL.path.hasPrefix("/Applications"), SMAppService.mainApp.status != .enabled {
                try? SMAppService.mainApp.register()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.statusBar.show() }
        }
    }

    private func hotkeyPressed() {
        guard !pressed else { return }
        pressed = true
        holding = false
        wasVisible = capture.isVisible
        if !wasVisible { capture.showNew() }
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.pressed else { return }
                self.holding = true
                self.capture.model.startVoice()
            }
        }
    }

    private func hotkeyReleased() {
        pressed = false
        holdTimer?.invalidate()
        holdTimer = nil
        if holding {
            holding = false
            capture.model.stopVoice()
        } else if wasVisible {
            capture.hide()
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
