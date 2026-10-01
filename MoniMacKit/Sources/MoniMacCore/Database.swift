import Foundation
import SQLite3

/// Minimal SQLite wrapper for MetricsHistory. Not thread-safe; owned by one actor.
final class Database {
    enum Location: Equatable {
        case inMemory
        case file(URL)
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private var handle: OpaquePointer?
    private var statements: [String: OpaquePointer] = [:]

    init(_ location: Location) throws {
        let path: String
        switch location {
        case .inMemory:
            path = ":memory:"
        case .file(let url):
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            path = url.path
        }
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close(handle)
            throw Failure(description: "open \(path): \(message)")
        }
    }

    deinit {
        for statement in statements.values { sqlite3_finalize(statement) }
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure(sql) }
    }

    /// Runs a statement that returns no rows. Statements are prepared once and cached.
    func run(_ sql: String, _ values: Value...) throws {
        let statement = try prepared(sql, values)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure(sql) }
    }

    /// Runs a query and maps each row.
    func query<Row>(_ sql: String, _ values: Value..., row: (Cursor) -> Row) throws -> [Row] {
        let statement = try prepared(sql, values)
        var rows: [Row] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: rows.append(row(Cursor(statement: statement)))
            case SQLITE_DONE: return rows
            default: throw failure(sql)
            }
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    enum Value {
        case double(Double)
        case int(Int)
        case text(String)
        case null
    }

    struct Cursor {
        let statement: OpaquePointer

        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
        func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }
        func text(_ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
    }

    private func prepared(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
        let statement: OpaquePointer
        if let cached = statements[sql] {
            statement = cached
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        } else {
            var new: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &new, nil) == SQLITE_OK, let new else { throw failure(sql) }
            statements[sql] = new
            statement = new
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .double(let double): sqlite3_bind_double(statement, index, double)
            case .int(let int): sqlite3_bind_int64(statement, index, Int64(int))
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func failure(_ sql: String) -> Failure {
        Failure(description: "\(String(cString: sqlite3_errmsg(handle))) — \(sql)")
    }
}
