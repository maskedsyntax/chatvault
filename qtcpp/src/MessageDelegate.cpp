#include "MessageDelegate.h"
#include "MessageModel.h"

#include <QApplication>
#include <QDateTime>
#include <QFileInfo>
#include <QFontMetrics>
#include <QPainter>
#include <QPainterPath>
#include <QStyle>

MessageDelegate::MessageDelegate(QObject *parent)
    : QStyledItemDelegate(parent), thumbnailCache_(256) {}

bool MessageDelegate::isImagePath(const QString &path) {
    const QString ext = QFileInfo(path).suffix().toLower();
    return ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "webp" || ext == "gif";
}

QPixmap MessageDelegate::thumbnailFor(const QString &path) const {
    if (path.isEmpty()) return {};
    if (auto *cached = thumbnailCache_.object(path)) return *cached;

    QPixmap image(path);
    if (image.isNull()) return {};
    QPixmap thumb = image.scaled(QSize(260, 180), Qt::KeepAspectRatio, Qt::SmoothTransformation);
    thumbnailCache_.insert(path, new QPixmap(thumb), 1);
    return thumb;
}

QSize MessageDelegate::sizeHint(const QStyleOptionViewItem &option, const QModelIndex &index) const {
    const QString body = index.data(MessageModel::BodyRole).toString();
    const QString mediaPath = index.data(MessageModel::MediaPathRole).toString();
    const QString mediaName = index.data(MessageModel::MediaFileNameRole).toString();
    const bool isMedia = index.data(MessageModel::IsMediaRole).toBool();

    const int width = qMax(320, option.rect.width() - 72);
    QFontMetrics fm(option.font);
    int height = 44;

    if (isMedia) {
        if (isImagePath(mediaPath) && !thumbnailFor(mediaPath).isNull()) {
            height += thumbnailFor(mediaPath).height() + 10;
        } else {
            height += 36;
        }
        const QString attachmentText = mediaName.isEmpty() ? QFileInfo(mediaPath).fileName() : mediaName;
        if (!attachmentText.isEmpty()) {
            height += fm.boundingRect(QRect(0, 0, width, 2000), Qt::TextWordWrap, attachmentText).height() + 8;
        }
    }

    if (!body.trimmed().isEmpty()) {
        height += fm.boundingRect(QRect(0, 0, width, 2000), Qt::TextWordWrap, body).height() + 8;
    }

    return QSize(width, qMax(64, height + 18));
}

void MessageDelegate::paint(QPainter *painter, const QStyleOptionViewItem &option, const QModelIndex &index) const {
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);

    const QString sender = index.data(MessageModel::SenderRole).toString();
    const QString body = index.data(MessageModel::BodyRole).toString();
    const qint64 timestamp = index.data(MessageModel::TimestampRole).toLongLong();
    const bool isSystem = index.data(MessageModel::SystemRole).toBool();
    const bool isMedia = index.data(MessageModel::IsMediaRole).toBool();
    const QString mediaName = index.data(MessageModel::MediaFileNameRole).toString();
    const QString mediaPath = index.data(MessageModel::MediaPathRole).toString();

    QRect r = option.rect.adjusted(12, 6, -12, -6);
    QColor bubble = isSystem ? QColor(90, 90, 90) : QColor(38, 57, 52);
    QColor textColor = option.palette.color(QPalette::Text);
    if (option.state & QStyle::State_Selected) {
        bubble = option.palette.highlight().color();
        textColor = option.palette.highlightedText().color();
    }

    QPainterPath path;
    path.addRoundedRect(r, 8, 8);
    painter->fillPath(path, bubble);

    int y = r.top() + 10;
    const int x = r.left() + 12;
    const int contentWidth = r.width() - 24;

    QFont small = option.font;
    small.setPointSize(qMax(9, small.pointSize() - 2));
    small.setBold(true);
    painter->setFont(small);
    painter->setPen(textColor.darker(115));
    QString meta;
    if (timestamp > 0) meta = QDateTime::fromSecsSinceEpoch(timestamp).toString("MMM d, yyyy h:mm AP");
    if (!sender.isEmpty()) meta = sender + (meta.isEmpty() ? "" : " · " + meta);
    painter->drawText(QRect(x, y, contentWidth, 18), Qt::AlignLeft | Qt::AlignVCenter, meta);
    y += meta.isEmpty() ? 0 : 22;

    if (isMedia) {
        if (isImagePath(mediaPath)) {
            const QPixmap thumb = thumbnailFor(mediaPath);
            if (!thumb.isNull()) {
                painter->drawPixmap(QRect(x, y, thumb.width(), thumb.height()), thumb);
                y += thumb.height() + 8;
            }
        } else {
            QRect mediaRect(x, y, contentWidth, 30);
            painter->setPen(textColor);
            painter->drawText(mediaRect, Qt::AlignLeft | Qt::AlignVCenter, "Attachment");
            y += 34;
        }

        const QString attachmentText = mediaName.isEmpty() ? QFileInfo(mediaPath).fileName() : mediaName;
        if (!attachmentText.isEmpty()) {
            QFont attachmentFont = option.font;
            attachmentFont.setPointSize(qMax(9, attachmentFont.pointSize() - 1));
            painter->setFont(attachmentFont);
            painter->setPen(textColor.darker(110));
            QFontMetrics attachmentMetrics(attachmentFont);
            const QRect attachmentRect = attachmentMetrics.boundingRect(
                QRect(x, y, contentWidth, r.bottom() - y - 6),
                Qt::TextWordWrap | Qt::AlignLeft | Qt::AlignTop,
                attachmentText
            );
            painter->drawText(attachmentRect, Qt::TextWordWrap | Qt::AlignLeft | Qt::AlignTop, attachmentText);
            y = attachmentRect.bottom() + 8;
        }
    }

    QFont bodyFont = option.font;
    painter->setFont(bodyFont);
    painter->setPen(textColor);
    const QString text = body.trimmed();
    if (!text.isEmpty()) {
        painter->drawText(QRect(x, y, contentWidth, qMax(0, r.bottom() - y - 8)), Qt::TextWordWrap | Qt::AlignLeft | Qt::AlignTop, text);
    }

    painter->restore();
}
