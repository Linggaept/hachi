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
            Section("Umum") {
                Toggle("Nyalakan saat login", isOn: $state.launchAtLogin)
                    .onChange(of: state.launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError = state.loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
                Picker("Shortcut catat cepat", selection: $settings.hotkey) {
                    ForEach(HotkeyChoice.allCases) { Text($0.label).tag($0) }
                }
                Text("Tekan untuk mencatat, tahan untuk bicara.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ringkasan pagi") {
                Toggle("Kirim ringkasan sekali sehari", isOn: $settings.briefingEnabled)
                Picker("Mulai dari jam", selection: $settings.briefingHour) {
                    ForEach(0..<12, id: \.self) { Text(String(format: "%02d.00", $0)).tag($0) }
                }
                .disabled(!settings.briefingEnabled)
                Toggle("Tanyakan tugas tanpa tanggal yang \(TaskStore.staleDays) hari tidak disentuh", isOn: $settings.nudgeEnabled)
                Button("Kirim ringkasan sekarang") { briefing.sendBriefing() }
            }

            Section {
                hourPicker("Pagi", $settings.morningHour, 4..<12)
                hourPicker("Siang", $settings.noonHour, 10..<15)
                hourPicker("Sore", $settings.afternoonHour, 14..<19)
                hourPicker("Malam", $settings.eveningHour, 18..<24)
            } header: {
                Text("Jam bagian hari")
            } footer: {
                Text("Dipakai saat kalimat hanya menyebut \"besok pagi\", \"nanti malam\", dst. Pengingat tugas seharian memakai jam pagi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Izin") {
                if state.notificationsDenied {
                    Label("Notifikasi dimatikan, jadi pengingat tidak akan muncul.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Label("Notifikasi menyala", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Pengaturan Notifikasi…") { open("x-apple.systempreferences:com.apple.Notifications-Settings.extension") }
                    Button("Mikrofon…") { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") }
                }
            }

            Section("Data") {
                Text(TaskStore.databaseURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Button("Ekspor…", action: exportData)
                    Button("Impor…", action: importData)
                    Button("Tampilkan di Finder") {
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

    private func hourPicker(_ label: String, _ value: Binding<Int>, _ range: Range<Int>) -> some View {
        Picker(label, selection: value) {
            ForEach(range, id: \.self) { Text(String(format: "%02d.00", $0)).tag($0) }
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
            state.loginError = "Gagal: \(error.localizedDescription). Pastikan aplikasi ada di folder Applications."
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
            state.dataMessage = "Tersimpan di \(url.lastPathComponent)."
        } catch {
            state.dataMessage = "Ekspor gagal: \(error.localizedDescription)"
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let added = try store.importJSON(Data(contentsOf: url))
            state.dataMessage = "\(added) tugas ditambahkan."
        } catch {
            state.dataMessage = "Impor gagal: berkas bukan hasil ekspor Hachi."
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
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeView()))
            window.title = "Pengaturan Hachi"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
