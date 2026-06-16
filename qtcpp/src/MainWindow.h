#pragma once

#include "Database.h"
#include "MessageModel.h"

#include <QFutureWatcher>
#include <QLineEdit>
#include <QListView>
#include <QListWidget>
#include <QMainWindow>
#include <QPushButton>
#include <QStatusBar>
#include <QVector>

class MainWindow : public QMainWindow {
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);

private:
    static constexpr int PageSize = 700;

    QListWidget *archiveList_ = nullptr;
    QListView *messageView_ = nullptr;
    MessageModel *messageModel_ = nullptr;
    QPushButton *importButton_ = nullptr;
    QPushButton *deleteButton_ = nullptr;
    QPushButton *renameButton_ = nullptr;
    QPushButton *loadEarlierButton_ = nullptr;
    QLineEdit *searchBox_ = nullptr;

    QString currentArchiveId_;
    QVector<ArchiveRow> archives_;
    bool loading_ = false;
    bool canLoadEarlier_ = false;

    void buildUi();
    void refreshArchives();
    void setBusy(const QString &message);
    void clearBusy(const QString &message = {});
    void loadArchive(const QString &archiveId);
    void loadEarlier();
    void searchMessages(const QString &query);
    void importFiles();
    void deleteCurrentArchive();
    void renameCurrentArchive();
    void openSelectedMedia(const QModelIndex &index);
    ArchiveRow currentArchive() const;
};
