import Foundation
import CSQLite

/// This database is owned by Session Canvas. Never opens or writes a Codex database.
public final class CanvasDatabase {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw CanvasError.message("Could not open canvas storage.") }
        try execute("PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL;")
        try execute("CREATE TABLE IF NOT EXISTS workspace (source TEXT PRIMARY KEY, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS acknowledgments (source TEXT NOT NULL, session TEXT NOT NULL, result TEXT NOT NULL, PRIMARY KEY(source,session,result)); PRAGMA user_version=1;")
        try execute("CREATE TABLE IF NOT EXISTS canvas_visibility (source TEXT PRIMARY KEY, payload BLOB NOT NULL); PRAGMA user_version=2;")
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> CanvasError { .message("Canvas storage: " + String(cString: sqlite3_errmsg(db))) }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var value: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &value, nil) == SQLITE_OK, let value else { throw failure() }
        return value
    }
    public func save(_ workspace: Workspace, source: String) throws {
        let data = try JSONEncoder().encode(workspace)
        let stmt = try statement("INSERT INTO workspace(source,payload) VALUES(?,?) ON CONFLICT(source) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, source, -1, transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    public func load(source: String) throws -> Workspace {
        let stmt = try statement("SELECT payload FROM workspace WHERE source=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, source, -1, transient)
        let status = sqlite3_step(stmt)
        if status == SQLITE_DONE { return Workspace() }
        guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else { throw failure() }
        return try JSONDecoder().decode(Workspace.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
    }
    public func acknowledge(source: String, session: String, result: String) throws {
        try acknowledge(source: source, results: [(session, result)])
    }
    public func acknowledge(source: String, results: [(session: String, result: String)]) throws {
        guard !results.isEmpty else { return }
        let stmt = try statement("INSERT OR IGNORE INTO acknowledgments(source,session,result) VALUES(?,?,?)")
        defer { sqlite3_finalize(stmt) }
        try execute("BEGIN IMMEDIATE")
        do {
            for result in results {
                sqlite3_reset(stmt); sqlite3_clear_bindings(stmt)
                for (index, value) in [source, result.session, result.result].enumerated() { sqlite3_bind_text(stmt, Int32(index + 1), value, -1, transient) }
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
    public func removeAcknowledgment(source: String, session: String, result: String) throws {
        let stmt = try statement("DELETE FROM acknowledgments WHERE source=? AND session=? AND result=?")
        defer { sqlite3_finalize(stmt) }
        for (index, value) in [source, session, result].enumerated() { sqlite3_bind_text(stmt, Int32(index + 1), value, -1, transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    public func saveVisibility(_ visibility: CanvasVisibility, source: String) throws {
        let data = try JSONEncoder().encode(visibility)
        let stmt = try statement("INSERT INTO canvas_visibility(source,payload) VALUES(?,?) ON CONFLICT(source) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, source, -1, transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    public func visibility(source: String) throws -> CanvasVisibility {
        let stmt = try statement("SELECT payload FROM canvas_visibility WHERE source=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, source, -1, transient)
        let status = sqlite3_step(stmt)
        if status == SQLITE_DONE { return CanvasVisibility() }
        guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else { throw failure() }
        return try JSONDecoder().decode(CanvasVisibility.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
    }
    public func acknowledgments(source: String) throws -> [String: Set<String>] {
        let stmt = try statement("SELECT session,result FROM acknowledgments WHERE source=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, source, -1, transient)
        var values: [String: Set<String>] = [:]
        while true {
            let status = sqlite3_step(stmt)
            if status == SQLITE_DONE { return values }
            guard status == SQLITE_ROW, let session = sqlite3_column_text(stmt, 0), let result = sqlite3_column_text(stmt, 1) else { throw failure() }
            values[String(cString: session), default: []].insert(String(cString: result))
        }
    }
}
