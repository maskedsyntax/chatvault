#pragma once

#include "Database.h"

#include <QAbstractListModel>
#include <QHash>

class MessageModel : public QAbstractListModel {
    Q_OBJECT

public:
    enum Roles {
        SenderRole = Qt::UserRole + 1,
        BodyRole,
        TimestampRole,
        SystemRole,
        SequenceRole,
        MediaFileNameRole,
        MediaPathRole,
        IsMediaRole
    };

    explicit MessageModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

    void setMessages(QVector<MessageRow> messages);
    void prependMessages(const QVector<MessageRow> &messages);
    void clear();
    void setStorageDirectory(const QString &storageDirectory);

    const QVector<MessageRow> &messages() const { return messages_; }

private:
    QVector<MessageRow> messages_;
    QString storageDirectory_;
    QHash<QString, QString> mediaPathByName_;

    QString resolveMediaPath(const QString &fileName) const;
};
