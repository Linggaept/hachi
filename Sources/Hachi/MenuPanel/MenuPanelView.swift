import SwiftUI

struct MenuActions {
    var capture: () -> Void
    var edit: (TaskItem) -> Void
    var settings: () -> Void
    var quit: () -> Void
}

/// Keadaan tampilan panel. Disimpan di luar view karena `@State` butuh plugin macro Xcode.
@MainActor
final class MenuPanelState: ObservableObject {
    @Published var showDone = false
    @Published var welcome: Bool
    /// Tugas yang baru dicentang: masih di tempatnya sampai jeda habis, klik lagi = batal.
    @Published private(set) var pending: Set<Int64> = []

    static let undoDelay: TimeInterval = 3

    private let store: TaskStore
    private var waits: [Int64: Task<Void, Never>] = [:]

    init(store: TaskStore, settings: AppSettings) {
        self.store = store
        welcome = !settings.onboarded
    }

    func toggleComplete(_ id: Int64) {
        if pending.contains(id) {
            cancel(id)
            return
        }
        pending.insert(id)
        // Task, bukan Timer: Timer biasa bisa tertahan selama panel menu bar terbuka.
        waits[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoDelay))
            guard !Task.isCancelled else { return }
            self?.commit(id)
        }
    }

    func cancel(_ id: Int64) {
        waits.removeValue(forKey: id)?.cancel()
        pending.remove(id)
    }

    /// Dipanggil sebelum keluar supaya centang yang masih dalam jeda tidak hilang.
    func commitAll() {
        for id in pending { commit(id) }
    }

    private func commit(_ id: Int64) {
        cancel(id)
        store.complete(id)
    }
}

struct MenuPanelView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: MenuPanelState
    let actions: MenuActions

    var body: some View {
        VStack(spacing: 0) {
            Button(action: actions.capture) {
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                    Text("Catat tugas…")
                    Spacer()
                    Text(settings.hotkey.label).foregroundStyle(.secondary).font(.callout)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()

            if state.welcome {
                welcomeCard
                Divider()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if state.showDone {
                        section("Selesai · \(TaskStore.doneWindowDays) hari terakhir", store.done, tint: .secondary)
                        if store.done.isEmpty { empty("Belum ada tugas yang selesai.") }
                    } else {
                        section("Terlambat", store.overdue, tint: .red)
                        section("Hari ini", store.today, tint: .primary)
                        section("Akan datang", store.upcoming, tint: .primary)
                        section("Tanpa tanggal", store.someday, tint: .primary)
                        if store.open.isEmpty {
                            empty("Belum ada tugas. Tekan \(settings.hotkey.label) untuk mencatat.")
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(minHeight: 120, maxHeight: 460)

            Divider()

            HStack(spacing: 14) {
                Button {
                    state.showDone.toggle()
                } label: {
                    if state.showDone {
                        Label("Daftar tugas", systemImage: "chevron.left")
                    } else {
                        HStack(spacing: 4) {
                            Label("Selesai hari ini (\(store.doneTodayCount))", systemImage: "checkmark.circle")
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                    }
                }
                .help(state.showDone ? "Kembali ke daftar tugas" : "Lihat dan batalkan tugas yang sudah selesai")
                Spacer()
                Button(action: actions.settings) { Image(systemName: "gearshape") }
                    .help("Pengaturan")
                Button(action: actions.quit) { Image(systemName: "power") }
                    .help("Keluar dari Hachi")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: 360)
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Selamat datang di Hachi").font(.headline)
            Text("Tekan \(settings.hotkey.label) dari aplikasi mana pun untuk mencatat. Tahan shortcut-nya untuk bicara. Aplikasi menyala otomatis saat login; bisa dimatikan di Pengaturan.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Mengerti") {
                settings.onboarded = true
                state.welcome = false
            }
            .padding(.top, 2)
        }
        .padding(14)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [TaskItem], tint: Color) -> some View {
        if !items.isEmpty {
            Text("\(title.uppercased()) (\(items.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint == .red ? Color.red : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(items) { task in
                TaskRow(task: task, store: store, state: state, onEdit: { actions.edit(task) })
            }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(24)
    }
}

private struct TaskRow: View {
    let task: TaskItem
    @ObservedObject var store: TaskStore
    @ObservedObject var state: MenuPanelState
    let onEdit: () -> Void

    private var checked: Bool { task.isDone || state.pending.contains(task.id) }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                task.isDone ? store.uncomplete(task.id) : state.toggleComplete(task.id)
            } label: {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(checked ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(checked ? "Batal selesai" : "Tandai selesai")

            // Area ubah dipisah dari tombol ✓ supaya klik di ✓ tidak tertelan gerakan baris.
            Button(action: onEdit) {
                HStack(spacing: 4) {
                    Text(task.title)
                        .strikethrough(checked)
                        .foregroundStyle(checked ? .secondary : .primary)
                        .lineLimit(2)
                    if task.rule != nil {
                        Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary)
                    }
                    if task.notes != nil {
                        Image(systemName: "text.alignleft").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(Formatting.dueLabel(for: task, now: store.now))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(task.isOverdue(now: store.now) ? Color.red : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(checked)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contextMenu {
            if task.isDone {
                Button("Batal selesai") { store.uncomplete(task.id) }
            } else if state.pending.contains(task.id) {
                Button("Batal selesai") { state.cancel(task.id) }
            } else {
                Button("Ubah…", action: onEdit)
                Button("Pindah ke besok") { store.moveToTomorrow(task.id) }
                Button("Tandai selesai") { state.toggleComplete(task.id) }
            }
            Divider()
            Button("Hapus", role: .destructive) {
                state.cancel(task.id)
                store.delete(task.id)
            }
        }
    }
}
