#include "Importer.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpressionMatch>
#include <QSet>
#include <QTemporaryDir>
#include <QTextStream>

static const QRegularExpression kLinePatterns[] = {
    QRegularExpression(R"(^(\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}),?\s+(\d{1,2}:\d{2}(?::\d{2})?(?:\s?[aApP][mM])?)\s?-\s(.*)$)"),
    QRegularExpression(R"(^\[(\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}),\s*(\d{1,2}:\d{2}(?::\d{2})?(?:\s?[aApP][mM])?)\]\s(.*)$)")
};

ParsedChat Importer::parseFile(const QString &path) {
    QString temporaryRoot;
    int mediaCount = 0;
    const QString textPath = prepareInputPath(path, temporaryRoot, mediaCount);
    ParsedChat chat = parseTextFile(textPath);
    chat.sourceFileName = QFileInfo(path).fileName();
    chat.suggestedTitle = suggestedTitle(chat.sourceFileName, chat.participants);
    chat.mediaFileCount = mediaCount;
    if (!temporaryRoot.isEmpty()) {
        chat.storageDirectory = moveImportDirectory(temporaryRoot);
    }
    return chat;
}

QString Importer::prepareInputPath(const QString &path, QString &temporaryRoot, int &mediaCount) {
    QFileInfo info(path);
    if (info.suffix().compare("zip", Qt::CaseInsensitive) != 0) {
        return path;
    }

    QDir root(Database::appDataDirectory());
    root.mkpath("imports");
    temporaryRoot = root.filePath("imports/import-" + QUuid::createUuid().toString(QUuid::WithoutBraces));
    QDir().mkpath(temporaryRoot);

    if (!extractZip(path, temporaryRoot)) {
        throw std::runtime_error("Could not extract ZIP export");
    }
    mediaCount = countMediaFiles(temporaryRoot);

    const QString textPath = findChatTextFile(temporaryRoot);
    if (textPath.isEmpty()) {
        throw std::runtime_error("No WhatsApp .txt file found inside ZIP");
    }
    return textPath;
}

bool Importer::extractZip(const QString &zipPath, const QString &destination) {
    QProcess unzip;
    unzip.start("/usr/bin/unzip", {"-qq", zipPath, "-d", destination});
    unzip.waitForFinished(-1);
    if (unzip.exitStatus() == QProcess::NormalExit && unzip.exitCode() == 0) {
        return true;
    }

    QProcess ditto;
    ditto.start("/usr/bin/ditto", {"-x", "-k", zipPath, destination});
    ditto.waitForFinished(-1);
    return ditto.exitStatus() == QProcess::NormalExit && ditto.exitCode() == 0;
}

QString Importer::findChatTextFile(const QString &directory) {
    QStringList textFiles;
    QDirIterator it(directory, {"*.txt"}, QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) textFiles << it.next();

    for (const QString &path : textFiles) {
        if (QFileInfo(path).fileName().compare("_chat.txt", Qt::CaseInsensitive) == 0) return path;
    }
    for (const QString &path : textFiles) {
        if (QFileInfo(path).fileName().contains("WhatsApp Chat", Qt::CaseInsensitive)) return path;
    }
    std::sort(textFiles.begin(), textFiles.end());
    return textFiles.value(0);
}

int Importer::countMediaFiles(const QString &directory) {
    int count = 0;
    QDirIterator it(directory, QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString path = it.next();
        if (QFileInfo(path).suffix().compare("txt", Qt::CaseInsensitive) != 0) ++count;
    }
    return count;
}

QString Importer::moveImportDirectory(const QString &temporaryRoot) {
    QDir root(Database::appDataDirectory());
    root.mkpath("archives");
    const QString destination = root.filePath("archives/" + QUuid::createUuid().toString(QUuid::WithoutBraces));
    if (!QDir().rename(temporaryRoot, destination)) {
        return temporaryRoot;
    }
    return destination;
}

ParsedChat Importer::parseTextFile(const QString &textPath) {
    QFile file(textPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        throw std::runtime_error("Could not read chat text file");
    }

    ParsedChat chat;
    QSet<QString> participants;
    ParsedMessage current;
    bool hasCurrent = false;

    auto commit = [&]() {
        if (!hasCurrent) return;
        QString mediaName;
        if (looksLikeMedia(current.body, mediaName)) {
            current.isMedia = true;
            current.mediaFileName = mediaName;
        }
        chat.messages.push_back(current);
        if (!current.senderName.isEmpty()) participants.insert(current.senderName);
        current = ParsedMessage();
        hasCurrent = false;
    };

    QTextStream stream(&file);
    stream.setEncoding(QStringConverter::Utf8);
    while (!stream.atEnd()) {
        QString line = stream.readLine();
        if (line.startsWith(QChar::ByteOrderMark)) line.remove(0, 1);
        const LineMatch match = matchLine(line);
        if (match.matched) {
            commit();
            current.timestamp = parseTimestamp(match.date, match.time);
            current.rawText = line;
            const int colon = match.rest.indexOf(": ");
            if (colon >= 0) {
                current.senderName = match.rest.left(colon);
                current.body = match.rest.mid(colon + 2);
                current.isSystem = false;
            } else {
                current.body = match.rest;
                current.isSystem = true;
            }
            hasCurrent = true;
        } else if (hasCurrent) {
            current.body += "\n" + line;
            current.rawText += "\n" + line;
        }
    }
    commit();

    chat.participants = QStringList(participants.begin(), participants.end());
    chat.participants.sort(Qt::CaseInsensitive);
    if (chat.messages.isEmpty()) throw std::runtime_error("No valid WhatsApp messages found");
    return chat;
}

Importer::LineMatch Importer::matchLine(const QString &line) {
    for (const QRegularExpression &pattern : kLinePatterns) {
        const QRegularExpressionMatch match = pattern.match(line);
        if (match.hasMatch()) {
            return {true, match.captured(1), match.captured(2), match.captured(3)};
        }
    }
    return {};
}

qint64 Importer::parseTimestamp(const QString &date, const QString &time) {
    QString normalizedDate = date;
    normalizedDate.replace('-', '/').replace('.', '/');
    const QString value = normalizedDate + " " + time.trimmed().toUpper();
    const QStringList formats = {
        "M/d/yy h:mm AP", "d/M/yy h:mm AP", "M/d/yyyy h:mm AP", "d/M/yyyy h:mm AP",
        "M/d/yy HH:mm", "d/M/yy HH:mm", "M/d/yyyy HH:mm", "d/M/yyyy HH:mm",
        "M/d/yy HH:mm:ss", "d/M/yy HH:mm:ss", "M/d/yyyy HH:mm:ss", "d/M/yyyy HH:mm:ss",
        "M/d/yyyy h:mm:ss AP", "d/M/yyyy h:mm:ss AP"
    };
    for (const QString &format : formats) {
        QDateTime dt = QDateTime::fromString(value, format);
        if (dt.isValid()) return dt.toSecsSinceEpoch();
    }
    return 0;
}

QString Importer::suggestedTitle(const QString &sourceFileName, const QStringList &participants) {
    QString base = QFileInfo(sourceFileName).completeBaseName();
    base.remove("WhatsApp Chat with ", Qt::CaseInsensitive);
    base.remove("WhatsApp Chat - ", Qt::CaseInsensitive);
    base.remove("_chat", Qt::CaseInsensitive);
    base = base.trimmed();
    if (!base.isEmpty() && base.compare("chat", Qt::CaseInsensitive) != 0) return base;
    if (participants.size() == 1) return participants.first();
    if (participants.size() == 2) return participants.join(" & ");
    return "Imported Chat";
}

bool Importer::looksLikeMedia(const QString &body, QString &fileName) {
    const QString trimmed = body.trimmed();
    if (trimmed.contains("<Media omitted>", Qt::CaseInsensitive)) return true;

    static const QRegularExpression attached(
        R"(^(.+?)\s+\((?:file attached|attached file|archivo adjunto|fichier joint|datei angehängt|datei angehangt|arquivo anexado|allegato)\)$)",
        QRegularExpression::CaseInsensitiveOption
    );
    const QRegularExpressionMatch attachedMatch = attached.match(trimmed);
    if (attachedMatch.hasMatch()) {
        fileName = attachedMatch.captured(1).trimmed();
        return true;
    }

    static const QRegularExpression known(
        R"(^((?:IMG|VID|PTT|STK|AUD|DOC)-[\w\-. ]+\.(?:jpg|jpeg|png|webp|gif|mp4|mov|opus|m4a|mp3|pdf|docx?|xlsx?|pptx?))$)",
        QRegularExpression::CaseInsensitiveOption
    );
    if (known.match(trimmed).hasMatch()) {
        fileName = trimmed;
        return true;
    }
    return false;
}
