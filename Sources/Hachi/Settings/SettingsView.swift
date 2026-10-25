import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsState: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
    @Published var notificationsDenied = false
    @Published var dataMessage: String?
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: SettingsState
    let store: TaskStore
    let briefing: BriefingService
    let scheduler: ReminderScheduler

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: $state.launchAtLogin)
                    .onChange(of: state.launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError = state.loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
                Picker("Quick capture shortcut", selection: $settings.hotkey) {
                    ForEach(HotkeyChoice.allCases) { Text(verbatim: $0.label).tag($0) }
                }
                Text("Press to add a task, hold to speak.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Morning summary") {
                Toggle("Send a summary once a day", isOn: $settings.briefingEnabled)
                Picker("Starting from", selection: $settings.briefingHour) {
                    ForEach(0..<12, id: \.self) { Text(verbatim: Formatting.hour($0)).tag($0) }
                }
                .disabled(!settings.briefingEnabled)
                Toggle("Ask about undated tasks untouched for \(TaskStore.staleDays) days", isOn: $settings.nudgeEnabled)
                Button("Send summary now") { briefing.sendBriefing() }
            }

            Section {
                hourPicker("Morning (pagi)", $settings.morningHour, 4..<12)
                hourPicker("Midday (siang)", $settings.noonHour, 10..<15)
                hourPicker("Afternoon (sore)", $settings.afternoonHour, 14..<19)
                hourPicker("Evening (malam)", $settings.eveningHour, 18..<24)
            } header: {
                Text("Parts of the day")
            } footer: {
                Text("Used when a sentence only says \"besok pagi\", \"nanti malam\", and so on. All-day task reminders use the morning time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                if state.notificationsDenied {
                    Label("Notifications are off, so reminders won't appear.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Label("Notifications are on", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Notification Settings…") { open("x-apple.systempreferences:com.apple.Notifications-Settings.extension") }
                    Button("Microphone…") { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") }
                }
            }

            Section("Data") {
                Text(TaskStore.databaseURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Button("Export…", action: exportData)
                    Button("Import…", action: importData)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([TaskStore.databaseURL])
                    }
                }
                if let dataMessage = state.dataMessage {
                    Text(dataMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .task { state.notificationsDenied = await scheduler.authorizationDenied() }
    }

    private func hourPicker(_ label: LocalizedStringKey, _ value: Binding<Int>, _ range: Range<Int>) -> some View {
        Picker(label, selection: value) {
            ForEach(range, id: \.self) { Text(verbatim: Formatting.hour($0)).tag($0) }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            state.loginError = nil
        } catch {
            state.loginError = String(localized: "Failed: \(error.localizedDescription). Make sure Hachi is in the Applications folder.")
        }
        state.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "hachi-\(Date().formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportJSON().write(to: url, options: .atomic)
            state.dataMessage = String(localized: "Saved to \(url.lastPathComponent).")
        } catch {
            state.dataMessage = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let added = try store.importJSON(Data(contentsOf: url))
            state.dataMessage = String(localized: "Tasks added: \(added)")
        } catch {
            state.dataMessage = String(localized: "Import failed: this file isn't a Hachi export.")
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeView: () -> SettingsView

    init(makeView: @escaping () -> SettingsView) {
        self.makeView = makeView
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeView().environment(\.locale, Formatting.locale)))
            window.title = String(localized: "Hachi Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
