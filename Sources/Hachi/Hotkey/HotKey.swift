import Carbon.HIToolbox
import Foundation

/// Shortcut global lewat Carbon `RegisterEventHotKey`. Tidak butuh izin Aksesibilitas.
/// Memberi tahu saat ditekan dan saat dilepas (untuk tahan-untuk-bicara).
@MainActor
final class HotKey {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var ref: EventHotKeyRef?
    private static var handlerInstalled = false
    private static var active: HotKey?
    private static let signature: OSType = 0x4C_41_53_54 // "LAST"

    func register(_ choice: HotkeyChoice) {
        unregister()
        Self.installHandler()
        let (code, modifiers) = Self.keys(for: choice)
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(code, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("Hachi: shortcut gagal didaftarkan (\(status))") }
        Self.active = self
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private static func keys(for choice: HotkeyChoice) -> (UInt32, UInt32) {
        switch choice {
        case .optionSpace: (UInt32(kVK_Space), UInt32(optionKey))
        case .controlSpace: (UInt32(kVK_Space), UInt32(controlKey))
        case .optionCommandSpace: (UInt32(kVK_Space), UInt32(optionKey | cmdKey))
        case .controlOptionT: (UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey))
        }
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            let kind = GetEventKind(event)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if kind == UInt32(kEventHotKeyPressed) {
                        HotKey.active?.onPress?()
                    } else {
                        HotKey.active?.onRelease?()
                    }
                }
            }
            return noErr
        }, types.count, &types, nil, nil)
    }
}
