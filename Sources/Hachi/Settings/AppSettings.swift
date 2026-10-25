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

/// Bahasa tampilan. Disimpan sebagai `AppleLanguages` di domain app, sama dengan setelan per app
/// di Pengaturan Sistem → Umum → Bahasa & Wilayah → Aplikasi. Berlaku setelah app dibuka ulang.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, id

    var id: String { rawValue }
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
    @Published var language: AppLanguage { didSet { saveLanguage() } }
    /// `.system` = ikut bahasa tampilan.
    @Published var voiceLanguage: AppLanguage { didSet { defaults.set(voiceLanguage.rawValue, forKey: "voiceLanguage") } }
    /// Bahasa saat app dibuka; bila berbeda dari `language`, app perlu dibuka ulang.
    let launchLanguage: AppLanguage

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
            "briefingEnabled": true, "briefingHour": 5, "nudgeEnabled": true, "voiceLanguage": AppLanguage.system.rawValue,
        ])
        hotkey = HotkeyChoice(rawValue: defaults.string(forKey: "hotkey") ?? "") ?? .optionSpace
        morningHour = defaults.integer(forKey: "morningHour")
        noonHour = defaults.integer(forKey: "noonHour")
        afternoonHour = defaults.integer(forKey: "afternoonHour")
        eveningHour = defaults.integer(forKey: "eveningHour")
        briefingEnabled = defaults.bool(forKey: "briefingEnabled")
        briefingHour = defaults.integer(forKey: "briefingHour")
        nudgeEnabled = defaults.bool(forKey: "nudgeEnabled")
        voiceLanguage = AppLanguage(rawValue: defaults.string(forKey: "voiceLanguage") ?? "") ?? .system
        let stored = Self.storedLanguage()
        language = stored
        launchLanguage = stored
    }

    /// Bahasa tampilan yang sedang dipakai ("id" atau "en").
    static var appLanguageCode: String {
        Bundle.main.preferredLocalizations.first == "id" ? "id" : "en"
    }

    var voiceLanguageCode: String {
        voiceLanguage == .system ? Self.appLanguageCode : voiceLanguage.rawValue
    }

    /// Hanya domain app yang dibaca; `object(forKey:)` akan ikut membaca bahasa sistem.
    private static func storedLanguage() -> AppLanguage {
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        let languages = UserDefaults.standard.persistentDomain(forName: domain)?["AppleLanguages"] as? [String]
        return languages?.first.flatMap { AppLanguage(rawValue: String($0.prefix(2))) } ?? .system
    }

    private func saveLanguage() {
        if language == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    var parserSettings: ParserSettings {
        ParserSettings(
            morningHour: morningHour, noonHour: noonHour, afternoonHour: afternoonHour, eveningHour: eveningHour,
            preferredLanguage: Self.appLanguageCode == "id" ? .indonesian : .english,
            monthFirst: DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: Formatting.locale)?.first == "M"
        )
    }

    var parser: TaskParser {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return TaskParser(settings: parserSettings, calendar: calendar)
    }
}
