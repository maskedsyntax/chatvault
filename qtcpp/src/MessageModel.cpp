#include "MessageModel.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>

MessageModel::MessageModel(QObject *parent) : QAbstractListModel(parent) {}

int MessageModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) return 0;
    return messages_.size();
}

QVariant MessageModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= messages_.size()) return {};
    const MessageRow &message = messages_[index.row()];
    switch (role) {
    case Qt::DisplayRole: {
        QString prefix;
        if (!message.senderName.isEmpty()) prefix = message.senderName + ": ";
        QString time;
        if (message.timestamp > 0) {
            time = QDateTime::fromSecsSinceEpoch(message.timestamp).toString("MMM d, yyyy h:mm AP") + "\n";
        }
        return time + prefix + message.body;
    }
    case SenderRole:
        return message.senderName;
    case BodyRole:
        return message.body;
    case TimestampRole:
        return message.timestamp;
    case SystemRole:
        return message.isSystem;
    case SequenceRole:
        return message.sequenceIndex;
    case MediaFileNameRole:
        return message.mediaFileName;
    case MediaPathRole:
        return resolveMediaPath(message.mediaFileName);
    case IsMediaRole:
        return message.isMedia || !message.mediaFileName.isEmpty();
    default:
        return {};
    }
}

void MessageModel::setMessages(QVector<MessageRow> messages) {
    beginResetModel();
    messages_ = std::move(messages);
    endResetModel();
}

void MessageModel::prependMessages(const QVector<MessageRow> &messages) {
    if (messages.isEmpty()) return;
    beginInsertRows(QModelIndex(), 0, messages.size() - 1);
    messages_ = messages + messages_;
    endInsertRows();
}

void MessageModel::clear() {
    beginResetModel();
    messages_.clear();
    endResetModel();
}

void MessageModel::setStorageDirectory(const QString &storageDirectory) {
    storageDirectory_ = storageDirectory;
    mediaPathByName_.clear();
    if (storageDirectory_.isEmpty()) return;

    QDirIterator it(storageDirectory_, QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString path = it.next();
        mediaPathByName_.insert(QFileInfo(path).fileName(), path);
    }
}

QString MessageModel::resolveMediaPath(const QString &fileName) const {
    if (fileName.isEmpty() || storageDirectory_.isEmpty()) return {};
    const QFileInfo direct(QDir(storageDirectory_).filePath(fileName));
    if (direct.exists()) return direct.absoluteFilePath();
    return mediaPathByName_.value(QFileInfo(fileName).fileName());
}
