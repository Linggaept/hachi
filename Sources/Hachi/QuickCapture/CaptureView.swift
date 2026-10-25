import SwiftUI
import TodoParser

struct CaptureView: View {
    @ObservedObject var model: CaptureModel
    @ObservedObject var store: TaskStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.mode == .quick {
                quick
            } else {
                TaskFormView(model: model, store: store)
                    .padding(18)
            }
        }
        .frame(width: 580)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.6)))
        .onExitCommand { model.close() }
    }

    // MARK: - Catat cepat

    private var quick: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Add a task… e.g. tomorrow 3pm call client", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .onSubmit { model.save() }
                    .disabled(model.voice.isActive)
                micButton
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            if let status = voiceStatus {
                Divider()
                status
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }

            if !model.text.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider()
                preview
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }

            Divider()
            hints
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        }
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { focused = true }
    }

    private var micButton: some View {
        Button {
            model.toggleVoice()
        } label: {
            Image(systemName: model.voice.isActive ? "stop.circle.fill" : "mic.circle")
                .font(.system(size: 24))
                .foregroundStyle(model.voice.isActive ? Color.red : Color.secondary)
                .symbolEffect(.pulse, isActive: model.voice.state == .listening)
        }
        .buttonStyle(.plain)
        .help("Speak (or hold the shortcut)")
    }

    private var voiceStatus: AnyView? {
        switch model.voice.state {
        case .idle:
            return nil
        case .preparing(let message):
            return AnyView(Label(message, systemImage: "hourglass").font(.callout).foregroundStyle(.secondary))
        case .listening:
            return AnyView(
                Label("Listening… release the shortcut or click ⏹ when done", systemImage: "waveform")
                    .font(.callout)
                    .foregroundStyle(.red)
            )
        case .failed(let message):
            return AnyView(Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange))
        }
    }

    private var preview: some View {
        let parsed = model.parsed
        return VStack(alignment: .leading, spacing: 8) {
            Text(parsed.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 8) {
                if let due = parsed.due {
                    Chip(icon: "calendar", text: Formatting.longDue(due, allDay: parsed.allDay, now: store.now))
                    Chip(icon: "bell", text: reminderText(parsed, due: due))
                } else {
                    Chip(icon: "tray", text: String(localized: "No date"))
                }
                if let rule = parsed.repeatRule {
                    Chip(icon: "repeat", text: Formatting.repeatLabel(rule))
                }
            }
        }
        .onTapGesture { model.openForm() }
    }

    private func reminderText(_ parsed: ParsedTask, due: Date) -> String {
        guard let offset = parsed.remindOffset else { return String(localized: "In the morning summary") }
        guard let at = store.reminderDate(due: due, allDay: parsed.allDay, offset: offset) else { return String(localized: "No reminder") }
        if offset == 0, !parsed.allDay { return String(localized: "On time") }
        let when = Calendar.current.isDate(at, inSameDayAs: due)
            ? Formatting.clock(at)
            : Formatting.longDue(at, allDay: false, now: store.now)
        return String(localized: "Remind \(when)")
    }

    private var hints: some View {
        HStack(spacing: 14) {
            Hint(key: "↩", text: "Save")
            Button("⌘↩ Set details") { model.openForm() }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            Hint(key: "esc", text: "Cancel")
            Spacer()
            Text("Hold \(model.settings.hotkey.label) to speak")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct Chip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

private struct Hint: View {
    let key: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: key)
            Text(text)
        }
    }
}
