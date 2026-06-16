import Foundation
import SQLite3

public struct MessageDaySummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let firstMessageID: UUID
    public let messageCount: Int

    public init(date: Date, firstMessageID: UUID, messageCount: Int) {
        self.id = Self.dayKey(for: date)
        self.date = date
        self.firstMessageID = firstMessageID
        self.messageCount = messageCount
    }

    public static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

@MainActor
public final class MessageSearchIndex {
    public static let shared = MessageSearchIndex()

    private var db: OpaquePointer?
    private var isInitialized = false

    private init() {}

    public struct IndexedMessage {
        public let id: UUID
        public let body: String
        public let senderName: String?
        public let timestamp: Date?

        public init(id: UUID, body: String, senderName: String?, timestamp: Date?) {
            self.id = id
            self.body = body
            self.senderName = senderName
            self.timestamp = timestamp
        }
    }

    public func rebuildIndex(
        archiveID: UUID,
        messages: [IndexedMessage]
    ) throws {
        try openDatabaseIfNeeded()
        try execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            try deleteIndex(for: archiveID)

            let insertSQL = """
            INSERT INTO message_fts (message_id, archive_id, body, sender_name)
            VALUES (?, ?, ?, ?);
            """
            var insertStatement: OpaquePointer?
            defer { sqlite3_finalize(insertStatement) }
            guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStatement, nil) == SQLITE_OK else {
                throw SearchIndexError.prepareFailed(lastError)
            }

            for message in messages {
                sqlite3_bind_text(insertStatement, 1, message.id.uuidString, -1, Self.transientDestructor)
                sqlite3_bind_text(insertStatement, 2, archiveID.uuidString, -1, Self.transientDestructor)
                sqlite3_bind_text(insertStatement, 3, message.body, -1, Self.transientDestructor)
                sqlite3_bind_text(insertStatement, 4, message.senderName ?? "", -1, Self.transientDestructor)
                guard sqlite3_step(insertStatement) == SQLITE_DONE else {
                    throw SearchIndexError.insertFailed(lastError)
                }
                sqlite3_reset(insertStatement)
                sqlite3_clear_bindings(insertStatement)
            }

            try rebuildMessageDays(archiveID: archiveID, messages: messages)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func deleteIndex(for archiveID: UUID) throws {
        try openDatabaseIfNeeded()
        try execute("DELETE FROM message_fts WHERE archive_id = '\(archiveID.uuidString)';")
        try execute("DELETE FROM message_days WHERE archive_id = '\(archiveID.uuidString)';")
    }

    public func search(archiveID: UUID, query: String, limit: Int = 1000) throws -> [UUID] {
        try openDatabaseIfNeeded()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let ftsQuery = Self.buildFTSQuery(from: trimmed)
        let sql = """
        SELECT message_id FROM message_fts
        WHERE archive_id = ? AND message_fts MATCH ?
        LIMIT ?;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SearchIndexError.prepareFailed(lastError)
        }

        sqlite3_bind_text(statement, 1, archiveID.uuidString, -1, Self.transientDestructor)
        sqlite3_bind_text(statement, 2, ftsQuery, -1, Self.transientDestructor)
        sqlite3_bind_int(statement, 3, Int32(limit))

        var ids: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(statement, 0),
                  let id = UUID(uuidString: String(cString: cString)) else { continue }
            ids.append(id)
        }
        return ids
    }

    public func messageDays(for archiveID: UUID) throws -> [MessageDaySummary] {
        try openDatabaseIfNeeded()
        let sql = """
        SELECT day, first_message_id, message_count
        FROM message_days
        WHERE archive_id = ?
        ORDER BY day ASC;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SearchIndexError.prepareFailed(lastError)
        }
        sqlite3_bind_text(statement, 1, archiveID.uuidString, -1, Self.transientDestructor)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var days: [MessageDaySummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let dayCString = sqlite3_column_text(statement, 0),
                  let messageCString = sqlite3_column_text(statement, 1),
                  let date = formatter.date(from: String(cString: dayCString)),
                  let messageID = UUID(uuidString: String(cString: messageCString)) else { continue }
            let count = Int(sqlite3_column_int(statement, 2))
            days.append(MessageDaySummary(date: date, firstMessageID: messageID, messageCount: count))
        }
        return days
    }

    private func rebuildMessageDays(archiveID: UUID, messages: [IndexedMessage]) throws {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        var grouped: [String: (date: Date, firstID: UUID, count: Int)] = [:]

        for message in messages {
            guard let timestamp = message.timestamp else { continue }
            let day = calendar.startOfDay(for: timestamp)
            let key = dayFormatter.string(from: day)
            if var existing = grouped[key] {
                existing.count += 1
                grouped[key] = existing
            } else {
                grouped[key] = (day, message.id, 1)
            }
        }

        let insertSQL = """
        INSERT INTO message_days (archive_id, day, first_message_id, message_count)
        VALUES (?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            throw SearchIndexError.prepareFailed(lastError)
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        for (_, value) in grouped.sorted(by: { $0.key < $1.key }) {
            let dayString = formatter.string(from: value.date)
            sqlite3_bind_text(statement, 1, archiveID.uuidString, -1, Self.transientDestructor)
            sqlite3_bind_text(statement, 2, dayString, -1, Self.transientDestructor)
            sqlite3_bind_text(statement, 3, value.firstID.uuidString, -1, Self.transientDestructor)
            sqlite3_bind_int(statement, 4, Int32(value.count))
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SearchIndexError.insertFailed(lastError)
            }
            sqlite3_reset(statement)
        }
    }

    private func openDatabaseIfNeeded() throws {
        guard !isInitialized else { return }
        try openDatabase()
        isInitialized = true
    }

    private func openDatabase() throws {
        if isRunningTests {
            guard sqlite3_open(":memory:", &db) == SQLITE_OK else {
                throw SearchIndexError.openFailed(lastError)
            }
        } else {
            let url = try Self.databaseURL()
            guard sqlite3_open(url.path, &db) == SQLITE_OK else {
                throw SearchIndexError.openFailed(lastError)
            }
        }

        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS message_fts USING fts5(
            message_id UNINDEXED,
            archive_id UNINDEXED,
            body,
            sender_name,
            tokenize='unicode61'
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS message_days (
            archive_id TEXT NOT NULL,
            day TEXT NOT NULL,
            first_message_id TEXT NOT NULL,
            message_count INTEGER NOT NULL,
            PRIMARY KEY (archive_id, day)
        );
        """)
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMessage) }
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastError
            throw SearchIndexError.execFailed(message)
        }
    }

    private var lastError: String {
        guard let db else { return "Database unavailable" }
        return String(cString: sqlite3_errmsg(db))
    }

    private static func databaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("ChatVault", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("search-index.db")
    }

    private static func buildFTSQuery(from query: String) -> String {
        let tokens = query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return query }

        return tokens.map { token in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\"*"
        }.joined(separator: " AND ")
    }

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public enum SearchIndexError: LocalizedError {
        case openFailed(String)
        case prepareFailed(String)
        case insertFailed(String)
        case execFailed(String)

        public var errorDescription: String? {
            switch self {
            case .openFailed(let message): return "Could not open search index: \(message)"
            case .prepareFailed(let message): return "Search index prepare failed: \(message)"
            case .insertFailed(let message): return "Search index insert failed: \(message)"
            case .execFailed(let message): return "Search index exec failed: \(message)"
            }
        }
    }
}
