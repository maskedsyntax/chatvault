#pragma once

#include "Database.h"

#include <QRegularExpression>
#include <QString>
#include <QUrl>

class Importer {
public:
    static ParsedChat parseFile(const QString &path);

private:
    struct LineMatch {
        bool matched = false;
        QString date;
        QString time;
        QString rest;
    };

    static QString prepareInputPath(const QString &path, QString &temporaryRoot, int &mediaCount);
    static bool extractZip(const QString &zipPath, const QString &destination);
    static QString findChatTextFile(const QString &directory);
    static int countMediaFiles(const QString &directory);
    static QString moveImportDirectory(const QString &temporaryRoot);
    static ParsedChat parseTextFile(const QString &textPath);
    static LineMatch matchLine(const QString &line);
    static qint64 parseTimestamp(const QString &date, const QString &time);
    static QString suggestedTitle(const QString &sourceFileName, const QStringList &participants);
    static bool looksLikeMedia(const QString &body, QString &fileName);
};
