import Foundation
import TodoParser

/// Pilihan shortcut catat cepat. Dibatasi ke beberapa pilihan supaya tidak bentrok dengan shortcut sistem.
enum HotkeyChoice: String, CaseIterable, Identifiable {
    case optionSpace, controlSpace, optionCommandSpace, controlOptionT

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionSpace: "⌥ Space"
        case .controlSpace: "⌃ Space"
        case .optionCommandSpace: "⌥⌘ Space"
        case .controlOptionT: "⌃⌥ T"
        }
    }
}

/// Pengaturan yang disimpan di UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var hotkey: HotkeyChoice { didSet { defaults.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var morningHour: Int { didSet { defaults.set(morningHour, forKey: "morningHour") } }
    @Published var noonHour: Int { didSet { defaults.set(noonHour, forKey: "noonHour") } }
    @Published var afternoonHour: Int { didSet { defaults.set(afternoonHour, forKey: "afternoonHour") } }
    @Published var eveningHour: Int { didSet { defaults.set(eveningHour, forKey: "eveningHour") } }
    @Published var briefingEnabled: Bool { didSet { defaults.set(briefingEnabled, forKey: "briefingEnabled") } }
    @Published var briefingHour: Int { didSet { defaults.set(briefingHour, forKey: "briefingHour") } }
    @Published var nudgeEnabled: Bool { didSet { defaults.set(nudgeEnabled, forKey: "nudgeEnabled") } }

    /// Hari terakhir ringkasan pagi dikirim (yyyy-MM-dd).
    var lastBriefingDay: String? {
        get { defaults.string(forKey: "lastBriefingDay") }
        set { defaults.set(newValue, forKey: "lastBriefingDay") }
    }

    var onboarded: Bool {
        get { defaults.bool(forKey: "onboarded") }
        set { defaults.set(newValue, forKey: "onboarded") }
    }

    init() {
        defaults.register(defaults: [
            "hotkey": HotkeyChoice.optionSpace.rawValue,
            "morningHour": 8, "noonHour": 12, "afternoonHour": 16, "eveningHour": 20,
            "briefingEnabled": true, "briefingHour": 5, "nudgeEnabled": true,
        ])
        hotkey = HotkeyChoice(rawValue: defaults.string(forKey: "hotkey") ?? "") ?? .optionSpace
        morningHour = defaults.integer(forKey: "morningHour")
        noonHour = defaults.integer(forKey: "noonHour")
        afternoonHour = defaults.integer(forKey: "afternoonHour")
        eveningHour = defaults.integer(forKey: "eveningHour")
        briefingEnabled = defaults.bool(forKey: "briefingEnabled")
        briefingHour = defaults.integer(forKey: "briefingHour")
        nudgeEnabled = defaults.bool(forKey: "nudgeEnabled")
    }

    var parserSettings: ParserSettings {
        ParserSettings(morningHour: morningHour, noonHour: noonHour, afternoonHour: afternoonHour, eveningHour: eveningHour)
    }

    var parser: TaskParser {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return TaskParser(settings: parserSettings, calendar: calendar)
    }
}
