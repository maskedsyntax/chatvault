#include "Database.h"

#include <QDir>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>
#include <stdexcept>

Database::Database(QString path) : path_(std::move(path)) {}

Database::~Database() {
    if (db_) sqlite3_close(db_);
}

QString Database::appDataDirectory() {
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(base);
    return base;
}

QString Database::defaultPath() {
    return QDir(appDataDirectory()).filePath("chatvault.sqlite3");
}

void Database::open() {
    if (db_) return;
    if (sqlite3_open(path_.toUtf8().constData(), &db_) != SQLITE_OK) {
        throw std::runtime_error(sqlite3_errmsg(db_));
    }
    exec("PRAGMA journal_mode=WAL;");
    exec("PRAGMA synchronous=NORMAL;");
    exec("PRAGMA temp_store=MEMORY;");
    exec("PRAGMA foreign_keys=ON;");
}

void Database::initialize() {
    open();
    exec(R"sql(
        CREATE TABLE IF NOT EXISTS archives (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            source_file_name TEXT NOT NULL,
            imported_at INTEGER NOT NULL,
            message_count INTEGER NOT NULL,
            participants_csv TEXT NOT NULL,
            last_message_at INTEGER,
            storage_directory TEXT,
            media_file_count INTEGER NOT NULL DEFAULT 0
        );
    )sql");
    exec(R"sql(
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            archive_id TEXT NOT NULL REFERENCES archives(id) ON DELETE CASCADE,
            sender_name TEXT,
            body TEXT NOT NULL,
            raw_text TEXT NOT NULL,
            timestamp INTEGER,
            is_system INTEGER NOT NULL,
            is_media INTEGER NOT NULL,
            media_file_name TEXT,
            sequence_index INTEGER NOT NULL
        );
    )sql");
    exec("CREATE INDEX IF NOT EXISTS idx_messages_archive_seq ON messages(archive_id, sequence_index);");
    exec("CREATE INDEX IF NOT EXISTS idx_messages_archive_time ON messages(archive_id, timestamp);");
    exec(R"sql(
        CREATE VIRTUAL TABLE IF NOT EXISTS message_fts USING fts5(
            message_id UNINDEXED,
            archive_id UNINDEXED,
            body,
            sender_name,
            tokenize='unicode61'
        );
    )sql");
}

void Database::exec(const QString &sql) {
    char *error = nullptr;
    if (sqlite3_exec(db_, sql.toUtf8().constData(), nullptr, nullptr, &error) != SQLITE_OK) {
        QString message = error ? QString::fromUtf8(error) : QString::fromUtf8(sqlite3_errmsg(db_));
        sqlite3_free(error);
        throw std::runtime_error(message.toStdString());
    }
}

sqlite3_stmt *Database::prepare(const QString &sql) {
    sqlite3_stmt *stmt = nullptr;
    if (sqlite3_prepare_v2(db_, sql.toUtf8().constData(), -1, &stmt, nullptr) != SQLITE_OK) {
        throw std::runtime_error(sqlite3_errmsg(db_));
    }
    return stmt;
}

QString Database::columnText(sqlite3_stmt *stmt, int index) {
    const unsigned char *text = sqlite3_column_text(stmt, index);
    return text ? QString::fromUtf8(reinterpret_cast<const char *>(text)) : QString();
}

qint64 Database::columnInt64(sqlite3_stmt *stmt, int index) {
    return sqlite3_column_int64(stmt, index);
}

void Database::bindText(sqlite3_stmt *stmt, int index, const QString &value) {
    sqlite3_bind_text(stmt, index, value.toUtf8().constData(), -1, SQLITE_TRANSIENT);
}

QVector<ArchiveRow> Database::archives() {
    open();
    QVector<ArchiveRow> rows;
    sqlite3_stmt *stmt = prepare(R"sql(
        SELECT a.id, a.title, a.source_file_name, a.imported_at, a.message_count,
               a.participants_csv, COALESCE(a.last_message_at, 0),
               COALESCE(a.storage_directory, ''), a.media_file_count,
               COALESCE((
                   SELECT CASE
                       WHEN m.is_media = 1 AND COALESCE(m.media_file_name, '') <> '' THEN m.media_file_name
                       WHEN COALESCE(m.sender_name, '') <> '' THEN m.sender_name || ': ' || m.body
                       ELSE m.body
                   END
                   FROM messages m
                   WHERE m.archive_id = a.id
                   ORDER BY m.sequence_index DESC
                   LIMIT 1
               ), '')
        FROM archives a
        ORDER BY a.imported_at DESC;
    )sql");
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        ArchiveRow row;
        row.id = columnText(stmt, 0);
        row.title = columnText(stmt, 1);
        row.sourceFileName = columnText(stmt, 2);
        row.importedAt = columnInt64(stmt, 3);
        row.messageCount = sqlite3_column_int(stmt, 4);
        row.participantsCsv = columnText(stmt, 5);
        row.lastMessageAt = columnInt64(stmt, 6);
        row.storageDirectory = columnText(stmt, 7);
        row.mediaFileCount = sqlite3_column_int(stmt, 8);
        row.preview = columnText(stmt, 9);
        rows.push_back(row);
    }
    sqlite3_finalize(stmt);
    return rows;
}

ArchiveRow Database::archive(const QString &archiveId) {
    for (const auto &row : archives()) {
        if (row.id == archiveId) return row;
    }
    return {};
}

static MessageRow readMessage(sqlite3_stmt *stmt) {
    MessageRow row;
    auto text = [](sqlite3_stmt *statement, int index) {
        const unsigned char *value = sqlite3_column_text(statement, index);
        return value ? QString::fromUtf8(reinterpret_cast<const char *>(value)) : QString();
    };
    row.id = text(stmt, 0);
    row.archiveId = text(stmt, 1);
    row.senderName = text(stmt, 2);
    row.body = text(stmt, 3);
    row.timestamp = sqlite3_column_int64(stmt, 4);
    row.isSystem = sqlite3_column_int(stmt, 5) != 0;
    row.isMedia = sqlite3_column_int(stmt, 6) != 0;
    row.mediaFileName = text(stmt, 7);
    row.sequenceIndex = sqlite3_column_int(stmt, 8);
    return row;
}

QVector<MessageRow> Database::recentMessages(const QString &archiveId, int limit) {
    open();
    QVector<MessageRow> rows;
    sqlite3_stmt *stmt = prepare(R"sql(
        SELECT id, archive_id, COALESCE(sender_name, ''), body, COALESCE(timestamp, 0),
               is_system, is_media, COALESCE(media_file_name, ''), sequence_index
        FROM (
            SELECT * FROM messages
            WHERE archive_id = ?
            ORDER BY sequence_index DESC
            LIMIT ?
        )
        ORDER BY sequence_index ASC;
    )sql");
    bindText(stmt, 1, archiveId);
    sqlite3_bind_int(stmt, 2, limit);
    while (sqlite3_step(stmt) == SQLITE_ROW) rows.push_back(readMessage(stmt));
    sqlite3_finalize(stmt);
    return rows;
}

QVector<MessageRow> Database::messagesBefore(const QString &archiveId, int beforeSequence, int limit) {
    open();
    QVector<MessageRow> rows;
    sqlite3_stmt *stmt = prepare(R"sql(
        SELECT id, archive_id, COALESCE(sender_name, ''), body, COALESCE(timestamp, 0),
               is_system, is_media, COALESCE(media_file_name, ''), sequence_index
        FROM (
            SELECT * FROM messages
            WHERE archive_id = ? AND sequence_index < ?
            ORDER BY sequence_index DESC
            LIMIT ?
        )
        ORDER BY sequence_index ASC;
    )sql");
    bindText(stmt, 1, archiveId);
    sqlite3_bind_int(stmt, 2, beforeSequence);
    sqlite3_bind_int(stmt, 3, limit);
    while (sqlite3_step(stmt) == SQLITE_ROW) rows.push_back(readMessage(stmt));
    sqlite3_finalize(stmt);
    return rows;
}

QString Database::ftsQuery(const QString &query) {
    QStringList tokens;
    for (const QString &part : query.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts)) {
        QString escaped = part;
        escaped.replace('"', "\"\"");
        tokens << "\"" + escaped + "\"*";
    }
    return tokens.isEmpty() ? query : tokens.join(" AND ");
}

QVector<MessageRow> Database::messagesMatching(const QString &archiveId, const QString &query, int limit) {
    open();
    QVector<MessageRow> rows;
    sqlite3_stmt *stmt = prepare(R"sql(
        SELECT m.id, m.archive_id, COALESCE(m.sender_name, ''), m.body, COALESCE(m.timestamp, 0),
               m.is_system, m.is_media, COALESCE(m.media_file_name, ''), m.sequence_index
        FROM message_fts f
        JOIN messages m ON m.id = f.message_id
        WHERE f.archive_id = ? AND message_fts MATCH ?
        ORDER BY m.sequence_index ASC
        LIMIT ?;
    )sql");
    bindText(stmt, 1, archiveId);
    bindText(stmt, 2, ftsQuery(query));
    sqlite3_bind_int(stmt, 3, limit);
    while (sqlite3_step(stmt) == SQLITE_ROW) rows.push_back(readMessage(stmt));
    sqlite3_finalize(stmt);
    return rows;
}

QString Database::saveArchive(const ParsedChat &chat) {
    open();
    const QString archiveId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const qint64 now = QDateTime::currentDateTimeUtc().toSecsSinceEpoch();
    const qint64 lastMessageAt = chat.messages.isEmpty() ? 0 : chat.messages.back().timestamp;

    exec("BEGIN IMMEDIATE TRANSACTION;");
    try {
        sqlite3_stmt *archiveStmt = prepare(R"sql(
            INSERT INTO archives
            (id, title, source_file_name, imported_at, message_count, participants_csv,
             last_message_at, storage_directory, media_file_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        )sql");
        bindText(archiveStmt, 1, archiveId);
        bindText(archiveStmt, 2, chat.suggestedTitle);
        bindText(archiveStmt, 3, chat.sourceFileName);
        sqlite3_bind_int64(archiveStmt, 4, now);
        sqlite3_bind_int(archiveStmt, 5, chat.messages.size());
        bindText(archiveStmt, 6, chat.participants.join("|"));
        sqlite3_bind_int64(archiveStmt, 7, lastMessageAt);
        bindText(archiveStmt, 8, chat.storageDirectory);
        sqlite3_bind_int(archiveStmt, 9, chat.mediaFileCount);
        if (sqlite3_step(archiveStmt) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        sqlite3_finalize(archiveStmt);

        sqlite3_stmt *messageStmt = prepare(R"sql(
            INSERT INTO messages
            (id, archive_id, sender_name, body, raw_text, timestamp, is_system, is_media, media_file_name, sequence_index)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        )sql");
        sqlite3_stmt *ftsStmt = prepare(R"sql(
            INSERT INTO message_fts (message_id, archive_id, body, sender_name)
            VALUES (?, ?, ?, ?);
        )sql");

        for (int i = 0; i < chat.messages.size(); ++i) {
            const ParsedMessage &msg = chat.messages[i];
            const QString messageId = QUuid::createUuid().toString(QUuid::WithoutBraces);

            bindText(messageStmt, 1, messageId);
            bindText(messageStmt, 2, archiveId);
            bindText(messageStmt, 3, msg.senderName);
            bindText(messageStmt, 4, msg.body);
            bindText(messageStmt, 5, msg.rawText);
            sqlite3_bind_int64(messageStmt, 6, msg.timestamp);
            sqlite3_bind_int(messageStmt, 7, msg.isSystem ? 1 : 0);
            sqlite3_bind_int(messageStmt, 8, msg.isMedia ? 1 : 0);
            bindText(messageStmt, 9, msg.mediaFileName);
            sqlite3_bind_int(messageStmt, 10, i);
            if (sqlite3_step(messageStmt) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
            sqlite3_reset(messageStmt);
            sqlite3_clear_bindings(messageStmt);

            bindText(ftsStmt, 1, messageId);
            bindText(ftsStmt, 2, archiveId);
            bindText(ftsStmt, 3, msg.body);
            bindText(ftsStmt, 4, msg.senderName);
            if (sqlite3_step(ftsStmt) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
            sqlite3_reset(ftsStmt);
            sqlite3_clear_bindings(ftsStmt);
        }
        sqlite3_finalize(messageStmt);
        sqlite3_finalize(ftsStmt);
        exec("COMMIT;");
    } catch (...) {
        exec("ROLLBACK;");
        throw;
    }

    return archiveId;
}

void Database::deleteArchive(const QString &archiveId) {
    open();
    exec("BEGIN IMMEDIATE TRANSACTION;");
    try {
        sqlite3_stmt *stmt = prepare("DELETE FROM message_fts WHERE archive_id = ?;");
        bindText(stmt, 1, archiveId);
        if (sqlite3_step(stmt) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        sqlite3_finalize(stmt);

        stmt = prepare("DELETE FROM messages WHERE archive_id = ?;");
        bindText(stmt, 1, archiveId);
        if (sqlite3_step(stmt) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        sqlite3_finalize(stmt);

        stmt = prepare("DELETE FROM archives WHERE id = ?;");
        bindText(stmt, 1, archiveId);
        if (sqlite3_step(stmt) != SQLITE_DONE) throw std::runtime_error(sqlite3_errmsg(db_));
        sqlite3_finalize(stmt);

        exec("COMMIT;");
    } catch (...) {
        exec("ROLLBACK;");
        throw;
    }
}

void Database::renameArchive(const QString &archiveId, const QString &title) {
    open();
    sqlite3_stmt *stmt = prepare("UPDATE archives SET title = ? WHERE id = ?;");
    bindText(stmt, 1, title);
    bindText(stmt, 2, archiveId);
    if (sqlite3_step(stmt) != SQLITE_DONE) {
        const QString message = QString::fromUtf8(sqlite3_errmsg(db_));
        sqlite3_finalize(stmt);
        throw std::runtime_error(message.toStdString());
    }
    sqlite3_finalize(stmt);
}
