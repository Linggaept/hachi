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
            Group {
                if model.editingID == nil { Text("New task") } else { Text("Edit task") }
            }
            .font(.headline)

            TextField("Title", text: $model.draft.title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($titleFocused)
                .onSubmit { model.save() }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Date").foregroundStyle(.secondary)
                    HStack {
                        Toggle("Has a date", isOn: hasDue).toggleStyle(.checkbox)
                        if model.draft.due != nil {
                            DatePicker("", selection: due, displayedComponents: model.draft.allDay ? [.date] : [.date, .hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.field)
                            Toggle("All day", isOn: allDay).toggleStyle(.checkbox)
                        }
                    }
                }
                if model.draft.due != nil {
                    GridRow {
                        Text("Reminder").foregroundStyle(.secondary)
                        Picker("", selection: $model.draft.remindOffset) {
                            ForEach(reminderOptions, id: \.self) { option in
                                Text(verbatim: reminderLabel(option)).tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                    GridRow {
                        Text("Repeat").foregroundStyle(.secondary)
                        Picker("", selection: $model.draft.rule) {
                            ForEach(ruleOptions, id: \.self) { option in
                                Text(verbatim: option.map(Formatting.repeatLabel) ?? String(localized: "Never")).tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                }
                GridRow(alignment: .top) {
                    Text("Notes").foregroundStyle(.secondary)
                    TextField("Optional", text: $model.draft.notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                }
            }

            HStack {
                if model.editingID != nil {
                    // Konfirmasi di tempat: dialog terpisah membuat panel kehilangan fokus dan tertutup.
                    if model.confirmDelete {
                        Button("Delete for sure?", role: .destructive) { model.delete() }
                            .foregroundStyle(.red)
                        Button("No") { model.confirmDelete = false }
                    } else {
                        Button("Delete", role: .destructive) { model.confirmDelete = true }
                    }
                }
                Spacer()
                Button("Cancel") { model.close() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { model.save() }
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
            case nil: return String(localized: "Only in the morning summary")
            case 0: return String(localized: "At \(Formatting.hour(model.settings.morningHour)) that day")
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
