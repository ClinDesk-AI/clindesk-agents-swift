import Foundation
import SQLite3

public struct SQLiteSessionError: Error, Equatable, LocalizedError, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public final class SQLiteSession: Session, @unchecked Sendable {
    public let sessionID: String
    public let sessionSettings: SessionSettings?
    public let dbPath: String
    public let sessionsTable: String
    public let messagesTable: String

    private static let lockRegistry = SQLiteSessionLockRegistry()

    private let lock: NSRecursiveLock
    private let lockPath: String?
    private var database: OpaquePointer?
    private var closed = false

    public init(
        sessionID: String,
        dbPath: String = ":memory:",
        sessionsTable: String = "agent_sessions",
        messagesTable: String = "agent_messages",
        sessionSettings: SessionSettings? = SessionSettings()
    ) throws {
        self.sessionID = sessionID
        self.sessionSettings = sessionSettings ?? SessionSettings()
        self.dbPath = dbPath
        self.sessionsTable = sessionsTable
        self.messagesTable = messagesTable

        if dbPath == ":memory:" {
            lock = NSRecursiveLock()
            lockPath = nil
        } else {
            let acquired = Self.lockRegistry.acquire(path: dbPath)
            lock = acquired.lock
            lockPath = acquired.path
        }

        do {
            try lock.withLock {
                try openDatabase()
                try initializeDatabase()
            }
        } catch {
            if let lockPath {
                Self.lockRegistry.release(path: lockPath)
            }
            throw error
        }
    }

    deinit {
        close()
    }

    public func getItems(limit: Int? = nil) async throws -> [ModelInputItem] {
        try lock.withLock {
            let sessionLimit = SessionSettings.resolveLimit(
                explicitLimit: limit,
                settings: sessionSettings
            )
            if let sessionLimit {
                let rows = try queryRows(
                    """
                    SELECT message_data FROM \(messagesTable)
                    WHERE session_id = ?
                    ORDER BY id DESC
                    LIMIT ?
                    """,
                    bindings: [.text(sessionID), .int(sessionLimit)]
                )
                return decodeItems(rows.reversed())
            }

            let rows = try queryRows(
                """
                SELECT message_data FROM \(messagesTable)
                WHERE session_id = ?
                ORDER BY id ASC
                """,
                bindings: [.text(sessionID)]
            )
            return decodeItems(rows)
        }
    }

    public func addItems(_ items: [ModelInputItem]) async throws {
        guard !items.isEmpty else {
            return
        }

        try lock.withLock {
            try execute("BEGIN TRANSACTION")
            do {
                try execute(
                    "INSERT OR IGNORE INTO \(sessionsTable) (session_id) VALUES (?)",
                    bindings: [.text(sessionID)]
                )

                for item in items {
                    let data = try JSONEncoder().encode(item)
                    guard let json = String(data: data, encoding: .utf8) else {
                        throw SQLiteSessionError("Failed to encode session item as UTF-8 JSON.")
                    }
                    try execute(
                        "INSERT INTO \(messagesTable) (session_id, message_data) VALUES (?, ?)",
                        bindings: [.text(sessionID), .text(json)]
                    )
                }

                try execute(
                    """
                    UPDATE \(sessionsTable)
                    SET updated_at = CURRENT_TIMESTAMP
                    WHERE session_id = ?
                    """,
                    bindings: [.text(sessionID)]
                )
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func popItem() async throws -> ModelInputItem? {
        try lock.withLock {
            while true {
                guard let row = try latestRow() else {
                    return nil
                }
                try execute(
                    "DELETE FROM \(messagesTable) WHERE id = ?",
                    bindings: [.int64(row.id)]
                )
                if let item = try? JSONDecoder().decode(ModelInputItem.self, from: Data(row.messageData.utf8)) {
                    return item
                }
            }
        }
    }

    public func clearSession() async throws {
        try lock.withLock {
            try execute(
                "DELETE FROM \(messagesTable) WHERE session_id = ?",
                bindings: [.text(sessionID)]
            )
            try execute(
                "DELETE FROM \(sessionsTable) WHERE session_id = ?",
                bindings: [.text(sessionID)]
            )
        }
    }

    public func close() {
        lock.withLock {
            guard !closed else {
                return
            }
            closed = true
            if let database {
                sqlite3_close(database)
                self.database = nil
            }
            if let lockPath {
                Self.lockRegistry.release(path: lockPath)
            }
        }
    }

    private func openDatabase() throws {
        let path = dbPath == ":memory:" ? dbPath : SQLiteSessionLockRegistry.normalizedPath(dbPath)
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(
            path,
            &opened,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let opened else {
            let message = opened.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
                ?? "Unable to open SQLite database."
            if let opened {
                sqlite3_close(opened)
            }
            throw SQLiteSessionError(message)
        }
        database = opened
        try execute("PRAGMA journal_mode=WAL")
    }

    private func initializeDatabase() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS \(sessionsTable) (
                session_id TEXT PRIMARY KEY,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS \(messagesTable) (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                message_data TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (session_id) REFERENCES \(sessionsTable) (session_id)
                    ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_\(messagesTable)_session_id
            ON \(messagesTable) (session_id, id)
            """
        )
    }

    private func latestRow() throws -> SQLiteSessionRow? {
        let rows = try queryRows(
            """
            SELECT id, message_data FROM \(messagesTable)
            WHERE session_id = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            bindings: [.text(sessionID)],
            columnCount: 2
        )
        guard let row = rows.first,
              let id = Int64(row[0])
        else {
            return nil
        }
        return SQLiteSessionRow(id: id, messageData: row[1])
    }

    private func decodeItems(_ rows: some Sequence<String>) -> [ModelInputItem] {
        rows.compactMap { row in
            try? JSONDecoder().decode(ModelInputItem.self, from: Data(row.utf8))
        }
    }

    private func execute(_ sql: String, bindings: [SQLiteSessionBinding] = []) throws {
        let statement = try prepare(sql, bindings: bindings)
        defer {
            sqlite3_finalize(statement)
        }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                continue
            }
            guard result == SQLITE_DONE else {
                throw SQLiteSessionError(errorMessage())
            }
            return
        }
    }

    private func queryRows(
        _ sql: String,
        bindings: [SQLiteSessionBinding] = [],
        columnCount: Int = 1
    ) throws -> [[String]] {
        let statement = try prepare(sql, bindings: bindings)
        defer {
            sqlite3_finalize(statement)
        }

        var rows: [[String]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                var row: [String] = []
                for column in 0..<columnCount {
                    guard let text = sqlite3_column_text(statement, Int32(column)) else {
                        row.append("")
                        continue
                    }
                    row.append(String(cString: UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self)))
                }
                rows.append(row)
            } else if result == SQLITE_DONE {
                return rows
            } else {
                throw SQLiteSessionError(errorMessage())
            }
        }
    }

    private func queryRows(
        _ sql: String,
        bindings: [SQLiteSessionBinding] = []
    ) throws -> [String] {
        try queryRows(sql, bindings: bindings, columnCount: 1).map { $0[0] }
    }

    private func prepare(_ sql: String, bindings: [SQLiteSessionBinding]) throws -> OpaquePointer {
        let database = try requireDatabase()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteSessionError(errorMessage())
        }

        do {
            try bind(bindings, to: statement)
            return statement
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
    }

    private func bind(_ bindings: [SQLiteSessionBinding], to statement: OpaquePointer) throws {
        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                result = value.withCString { pointer in
                    sqlite3_bind_text(statement, position, pointer, -1, sqliteTransient)
                }
            case .int(let value):
                result = sqlite3_bind_int(statement, position, Int32(value))
            case .int64(let value):
                result = sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            }
            guard result == SQLITE_OK else {
                throw SQLiteSessionError(errorMessage())
            }
        }
    }

    private func requireDatabase() throws -> OpaquePointer {
        if closed {
            throw SQLiteSessionError("SQLiteSession is closed")
        }
        guard let database else {
            throw SQLiteSessionError("SQLiteSession is closed")
        }
        return database
    }

    private func errorMessage() -> String {
        guard let database else {
            return "SQLiteSession is closed"
        }
        return String(cString: sqlite3_errmsg(database))
    }
}

private struct SQLiteSessionRow {
    var id: Int64
    var messageData: String
}

private enum SQLiteSessionBinding {
    case text(String)
    case int(Int)
    case int64(Int64)
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteSessionLockRegistry: @unchecked Sendable {
    private let guardLock = NSLock()
    private var locks: [String: SQLiteSessionLockRecord] = [:]

    func acquire(path: String) -> (path: String, lock: NSRecursiveLock) {
        let normalized = Self.normalizedPath(path)
        guardLock.lock()
        defer {
            guardLock.unlock()
        }
        let record = locks[normalized] ?? SQLiteSessionLockRecord()
        record.count += 1
        locks[normalized] = record
        return (normalized, record.lock)
    }

    func release(path: String) {
        guardLock.lock()
        defer {
            guardLock.unlock()
        }
        guard let record = locks[path] else {
            return
        }
        if record.count <= 1 {
            locks.removeValue(forKey: path)
        } else {
            record.count -= 1
        }
    }

    static func normalizedPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}

private final class SQLiteSessionLockRecord: @unchecked Sendable {
    let lock = NSRecursiveLock()
    var count = 0
}

private extension NSRecursiveLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer {
            unlock()
        }
        return try body()
    }
}
