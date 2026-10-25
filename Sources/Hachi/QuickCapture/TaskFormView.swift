import SwiftUI
import TodoParser

/// Form detail tugas: dipakai untuk "Atur detail" dan untuk mengubah tugas yang sudah ada.
struct TaskFormView: View {
    @ObservedObject var model: CaptureModel
    @ObservedObject var store: TaskStore
    @FocusState private var titleFocused: Bool

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.editingID == nil ? "Tugas baru" : "Ubah tugas")
                .font(.headline)

            TextField("Judul", text: $model.draft.title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($titleFocused)
                .onSubmit { model.save() }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Tanggal").foregroundStyle(.secondary)
                    HStack {
                        Toggle("Pakai tanggal", isOn: hasDue).toggleStyle(.checkbox)
                        if model.draft.due != nil {
                            DatePicker("", selection: due, displayedComponents: model.draft.allDay ? [.date] : [.date, .hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.field)
                            Toggle("Seharian", isOn: allDay).toggleStyle(.checkbox)
                        }
                    }
                }
                if model.draft.due != nil {
                    GridRow {
                        Text("Pengingat").foregroundStyle(.secondary)
                        Picker("", selection: $model.draft.remindOffset) {
                            ForEach(reminderOptions, id: \.self) { option in
                                Text(reminderLabel(option)).tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                    GridRow {
                        Text("Ulangi").foregroundStyle(.secondary)
                        Picker("", selection: $model.draft.rule) {
                            ForEach(ruleOptions, id: \.self) { option in
                                Text(option?.label ?? "Tidak").tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                }
                GridRow(alignment: .top) {
                    Text("Catatan").foregroundStyle(.secondary)
                    TextField("Opsional", text: $model.draft.notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                }
            }

            HStack {
                if model.editingID != nil {
                    // Konfirmasi di tempat: dialog terpisah membuat panel kehilangan fokus dan tertutup.
                    if model.confirmDelete {
                        Button("Yakin hapus?", role: .destructive) { model.delete() }
                            .foregroundStyle(.red)
                        Button("Tidak") { model.confirmDelete = false }
                    } else {
                        Button("Hapus", role: .destructive) { model.confirmDelete = true }
                    }
                }
                Spacer()
                Button("Batal") { model.close() }
                    .keyboardShortcut(.cancelAction)
                Button("Simpan") { model.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
        }
        .onAppear { titleFocused = true }
        .onChange(of: model.focusToken) { titleFocused = true }
    }

    // MARK: - Binding

    private var hasDue: Binding<Bool> {
        Binding {
            model.draft.due != nil
        } set: { on in
            if on {
                let next = calendar.nextDate(after: store.now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? store.now
                model.draft.due = next
                model.draft.allDay = false
                model.draft.remindOffset = 0
            } else {
                model.draft.due = nil
                model.draft.rule = nil
                model.draft.remindOffset = nil
            }
        }
    }

    private var due: Binding<Date> {
        Binding {
            model.draft.due ?? store.now
        } set: { value in
            model.draft.due = model.draft.allDay ? calendar.startOfDay(for: value) : value
        }
    }

    private var allDay: Binding<Bool> {
        Binding {
            model.draft.allDay
        } set: { on in
            guard let current = model.draft.due else { return }
            model.draft.allDay = on
            if on {
                model.draft.due = calendar.startOfDay(for: current)
                if model.draft.remindOffset == 0 { model.draft.remindOffset = nil }
            } else {
                model.draft.due = calendar.date(bySettingHour: model.settings.morningHour, minute: 0, second: 0, of: current)
                if model.draft.remindOffset == nil { model.draft.remindOffset = 0 }
            }
        }
    }

    // MARK: - Pilihan

    private var reminderOptions: [Double?] {
        var options: [Double?] = model.draft.allDay
            ? [nil, 0, 86400]
            : [nil, 0, 300, 600, 900, 1800, 3600, 86400]
        if !options.contains(model.draft.remindOffset) { options.append(model.draft.remindOffset) }
        return options
    }

    private func reminderLabel(_ offset: Double?) -> String {
        if model.draft.allDay {
            switch offset {
            case nil: return "Cukup di ringkasan pagi"
            case 0: return "Jam \(model.settings.morningHour).00 hari itu"
            default: return Formatting.offsetLabel(offset)
            }
        }
        return Formatting.offsetLabel(offset)
    }

    private var ruleOptions: [RepeatRule?] {
        let day = calendar.component(.day, from: model.draft.due ?? store.now)
        var options: [RepeatRule?] = [
            nil, .daily(every: 1), .weekly(every: 1, weekdays: RepeatRule.workdays),
            .weekly(every: 1, weekdays: []), .weekly(every: 2, weekdays: []), .monthly(day: day), .yearly,
        ]
        if !options.contains(model.draft.rule) { options.append(model.draft.rule) }
        return options
    }
}
