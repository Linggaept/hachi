import Foundation
import SQLite3

enum SQLValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case null

    static func date(_ date: Date?) -> SQLValue {
        date.map { .double($0.timeIntervalSince1970) } ?? .null
    }

    static func string(_ text: String?) -> SQLValue {
        text.map { .text($0) } ?? .null
    }

    static func number(_ value: Double?) -> SQLValue {
        value.map { .double($0) } ?? .null
    }
}

struct DatabaseError: Error, CustomStringConvertible {
    let description: String
}

/// Pembungkus tipis `sqlite3` bawaan macOS.
final class Database {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            throw DatabaseError(description: "Can't open the database at \(url.path)")
        }
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit {
        sqlite3_close(handle)
    }

    var lastInsertID: Int64 { sqlite3_last_insert_rowid(handle) }

    var userVersion: Int {
        get { (try? query("PRAGMA user_version") { $0.int(0) }.first).flatMap { $0 } ?? 0 }
        set { try? execute("PRAGMA user_version = \(newValue)") }
    }

    func execute(_ sql: String, _ params: [SQLValue] = []) throws {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else { throw lastError(sql) }
    }

    func query<T>(_ sql: String, _ params: [SQLValue] = [], row: (Row) -> T) throws -> [T] {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        var result: [T] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw lastError(sql) }
            result.append(row(Row(statement: statement)))
        }
        return result
    }

    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError(sql) }
        for (i, param) in params.enumerated() {
            let index = Int32(i + 1)
            switch param {
            case .int(let v): sqlite3_bind_int64(statement, index, v)
            case .double(let v): sqlite3_bind_double(statement, index, v)
            case .text(let v): sqlite3_bind_text(statement, index, v, -1, Self.transient)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func lastError(_ sql: String) -> DatabaseError {
        DatabaseError(description: String(cString: sqlite3_errmsg(handle)) + " (\(sql))")
    }

    struct Row {
        let statement: OpaquePointer?

        private func isNull(_ i: Int32) -> Bool { sqlite3_column_type(statement, i) == SQLITE_NULL }

        func int(_ i: Int32) -> Int? { isNull(i) ? nil : Int(sqlite3_column_int64(statement, i)) }
        func int64(_ i: Int32) -> Int64 { sqlite3_column_int64(statement, i) }
        func double(_ i: Int32) -> Double? { isNull(i) ? nil : sqlite3_column_double(statement, i) }
        func text(_ i: Int32) -> String? { isNull(i) ? nil : sqlite3_column_text(statement, i).map { String(cString: $0) } }
        func date(_ i: Int32) -> Date? { double(i).map(Date.init(timeIntervalSince1970:)) }
    }
}
