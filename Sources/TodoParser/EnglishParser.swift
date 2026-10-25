import Foundation

/// Membaca kalimat sehari-hari berbahasa Inggris menjadi tugas.
struct EnglishParser: LanguageParser {
    let core: ParserCore

    func parse(_ text: String, now: Date) -> (task: ParsedTask, consumed: Int) {
        let cursor = Cursor(text)
        return (ParsedTask(title: ParserCore.cleanTitle(cursor.remaining, fallback: text, edge: Self.edge)), cursor.consumed)
    }

    static let edge = #"(?i)^(?:and|at|on|by|to|the|,|-|:)\s+|\s+(?:and|at|on|by|to|the|,|-|:)$|^[,\-:]+|[,\-:]+$"#
}
