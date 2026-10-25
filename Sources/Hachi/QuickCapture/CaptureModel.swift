import Combine
import Foundation
import TodoParser

/// Keadaan kotak catat cepat: teks bebas (diketik/diucapkan) atau form detail.
@MainActor
final class CaptureModel: ObservableObject {
    enum Mode { case quick, form }

    @Published var text = ""
    @Published var mode: Mode = .quick
    @Published var draft = TaskDraft(title: "")
    @Published private(set) var editingID: Int64?
    /// Dinaikkan setiap panel dibuka supaya kursor kembali ke isian.
    @Published private(set) var focusToken = 0
    @Published var confirmDelete = false

    let voice = VoiceRecognizer()
    let store: TaskStore
    let settings: AppSettings
    var onClose: (() -> Void)?

    private var textBeforeVoice = ""
    private var bag: Set<AnyCancellable> = []

    init(store: TaskStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        voice.$transcript
            .sink { [weak self] transcript in
                guard let self, self.voice.isActive else { return }
                self.text = Self.join(self.textBeforeVoice, transcript)
            }
            .store(in: &bag)
        voice.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    var parsed: ParsedTask { settings.parser.parse(text, now: store.now) }

    func newTask() {
        voice.cancel()
        confirmDelete = false
        text = ""
        mode = .quick
        draft = TaskDraft(title: "")
        editingID = nil
        focusToken += 1
    }

    func edit(_ task: TaskItem) {
        voice.cancel()
        confirmDelete = false
        text = ""
        draft = TaskDraft(task: task)
        editingID = task.id
        mode = .form
        focusToken += 1
    }

    /// Pindah ke form dengan isi hasil bacaan kalimat.
    func openForm() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        draft = trimmed.isEmpty ? TaskDraft(title: "") : TaskDraft(parsed: parsed)
        mode = .form
        focusToken += 1
    }

    var canSave: Bool {
        switch mode {
        case .quick: !text.trimmingCharacters(in: .whitespaces).isEmpty && !voice.isActive
        case .form: !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    func save() {
        guard canSave else { return }
        switch mode {
        case .quick:
            store.add(TaskDraft(parsed: parsed))
        case .form:
            var clean = draft
            clean.title = clean.title.trimmingCharacters(in: .whitespaces)
            if let id = editingID {
                store.update(id, with: clean)
            } else {
                store.add(clean)
            }
        }
        close()
    }

    func delete() {
        guard let id = editingID else { return }
        store.delete(id)
        close()
    }

    func close() {
        voice.cancel()
        onClose?()
    }

    // MARK: - Suara

    func startVoice() {
        guard !voice.isActive else { return }
        if mode == .form { mode = .quick }
        textBeforeVoice = text
        Task { await voice.start(language: settings.voiceLanguageCode) }
    }

    func stopVoice() {
        guard voice.isActive else { return }
        Task {
            let final = await voice.stop()
            text = Self.join(textBeforeVoice, final)
            focusToken += 1
        }
    }

    func toggleVoice() {
        voice.isActive ? stopVoice() : startVoice()
    }

    private static func join(_ a: String, _ b: String) -> String {
        [a.trimmingCharacters(in: .whitespaces), b].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
