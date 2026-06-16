#pragma once

#include <QDateTime>
#include <QString>
#include <QStringList>
#include <QVector>
#include <QUuid>

#include <sqlite3.h>

struct ArchiveRow {
    QString id;
    QString title;
    QString sourceFileName;
    qint64 importedAt = 0;
    int messageCount = 0;
    QString participantsCsv;
    qint64 lastMessageAt = 0;
    QString storageDirectory;
    int mediaFileCount = 0;
    QString preview;
};

struct MessageRow {
    QString id;
    QString archiveId;
    QString senderName;
    QString body;
    qint64 timestamp = 0;
    bool isSystem = false;
    bool isMedia = false;
    QString mediaFileName;
    int sequenceIndex = 0;
};

struct ParsedMessage {
    QString senderName;
    QString body;
    QString rawText;
    qint64 timestamp = 0;
    bool isSystem = false;
    bool isMedia = false;
    QString mediaFileName;
};

struct ParsedChat {
    QVector<ParsedMessage> messages;
    QStringList participants;
    int mediaFileCount = 0;
    QString storageDirectory;
    QString sourceFileName;
    QString suggestedTitle;
};

class Database {
public:
    explicit Database(QString path = defaultPath());
    ~Database();

    Database(const Database &) = delete;
    Database &operator=(const Database &) = delete;

    static QString defaultPath();
    static QString appDataDirectory();

    void open();
    void initialize();

    QVector<ArchiveRow> archives();
    QVector<MessageRow> recentMessages(const QString &archiveId, int limit);
    QVector<MessageRow> messagesBefore(const QString &archiveId, int beforeSequence, int limit);
    QVector<MessageRow> messagesMatching(const QString &archiveId, const QString &query, int limit);
    ArchiveRow archive(const QString &archiveId);

    QString saveArchive(const ParsedChat &chat);
    void deleteArchive(const QString &archiveId);
    void renameArchive(const QString &archiveId, const QString &title);

private:
    QString path_;
    sqlite3 *db_ = nullptr;

    void exec(const QString &sql);
    sqlite3_stmt *prepare(const QString &sql);
    static QString columnText(sqlite3_stmt *stmt, int index);
    static qint64 columnInt64(sqlite3_stmt *stmt, int index);
    static QString ftsQuery(const QString &query);
    void bindText(sqlite3_stmt *stmt, int index, const QString &value);
};
