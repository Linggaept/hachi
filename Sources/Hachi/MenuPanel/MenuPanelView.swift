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
                    Text("Add a task…")
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
                        section(String(localized: "Done · last \(TaskStore.doneWindowDays) days"), store.done, tint: .secondary)
                        if store.done.isEmpty { empty(String(localized: "No completed tasks yet.")) }
                    } else {
                        section(String(localized: "Overdue"), store.overdue, tint: .red)
                        section(String(localized: "Today"), store.today, tint: .primary)
                        section(String(localized: "Upcoming"), store.upcoming, tint: .primary)
                        section(String(localized: "No date"), store.someday, tint: .primary)
                        if store.open.isEmpty {
                            empty(String(localized: "No tasks yet. Press \(settings.hotkey.label) to add one."))
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
                        Label("Task list", systemImage: "chevron.left")
                    } else {
                        HStack(spacing: 4) {
                            Label("Done today (\(store.doneTodayCount))", systemImage: "checkmark.circle")
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                    }
                }
                .help(state.showDone ? String(localized: "Back to the task list") : String(localized: "See and undo completed tasks"))
                Spacer()
                Button(action: actions.settings) { Image(systemName: "gearshape") }
                    .help("Settings")
                Button(action: actions.quit) { Image(systemName: "power") }
                    .help("Quit Hachi")
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
            Text("Welcome to Hachi").font(.headline)
            Text("Press \(settings.hotkey.label) from any app to add a task. Hold the shortcut to speak. Hachi starts automatically at login; you can turn this off in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Got it") {
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
            Text(verbatim: "\(title.uppercased(with: Formatting.locale)) (\(items.count))")
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
            .help(checked ? String(localized: "Mark as not done") : String(localized: "Mark as done"))

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
                Button("Mark as not done") { store.uncomplete(task.id) }
            } else if state.pending.contains(task.id) {
                Button("Mark as not done") { state.cancel(task.id) }
            } else {
                Button("Edit…", action: onEdit)
                Button("Move to tomorrow") { store.moveToTomorrow(task.id) }
                Button("Mark as done") { state.toggleComplete(task.id) }
            }
            Divider()
            Button("Delete", role: .destructive) {
                state.cancel(task.id)
                store.delete(task.id)
            }
        }
    }
}
