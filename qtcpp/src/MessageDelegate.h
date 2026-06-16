#pragma once

#include <QPixmap>
#include <QStyledItemDelegate>
#include <QCache>

class MessageDelegate : public QStyledItemDelegate {
    Q_OBJECT

public:
    explicit MessageDelegate(QObject *parent = nullptr);

    void paint(QPainter *painter, const QStyleOptionViewItem &option, const QModelIndex &index) const override;
    QSize sizeHint(const QStyleOptionViewItem &option, const QModelIndex &index) const override;

private:
    mutable QCache<QString, QPixmap> thumbnailCache_;

    static bool isImagePath(const QString &path);
    QPixmap thumbnailFor(const QString &path) const;
};
