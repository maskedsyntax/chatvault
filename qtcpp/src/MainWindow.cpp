#include "MainWindow.h"
#include "Importer.h"
#include "MessageDelegate.h"

#include <QtConcurrent>

#include <QApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QFileDialog>
#include <QFont>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QInputDialog>
#include <QLabel>
#include <QMessageBox>
#include <QProgressBar>
#include <QSplitter>
#include <QTextEdit>
#include <QToolBar>
#include <QUrl>
#include <QVBoxLayout>

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent) {
    Database db;
    db.initialize();
    buildUi();
    refreshArchives();
}

void MainWindow::buildUi() {
    setWindowTitle("ChatVaultQt");
    const QIcon logo(":/logo.png");
    setWindowIcon(logo);
    QApplication::setWindowIcon(logo);

    auto *central = new QWidget(this);
    auto *layout = new QHBoxLayout(central);
    layout->setContentsMargins(0, 0, 0, 0);

    auto *splitter = new QSplitter(Qt::Horizontal, central);
    layout->addWidget(splitter);

    auto *side = new QWidget(splitter);
    auto *sideLayout = new QVBoxLayout(side);
    sideLayout->setContentsMargins(8, 8, 8, 8);

    auto *title = new QLabel(side);
    title->setText("ChatVaultQt");
    title->setPixmap(QPixmap(":/logo.png").scaled(28, 28, Qt::KeepAspectRatio, Qt::SmoothTransformation));
    title->setToolTip("ChatVaultQt");
    auto *titleText = new QLabel("ChatVaultQt", side);
    QFont titleFont = title->font();
    titleFont.setBold(true);
    titleFont.setPointSize(titleFont.pointSize() + 2);
    titleText->setFont(titleFont);
    auto *titleRow = new QHBoxLayout();
    titleRow->addWidget(title);
    titleRow->addWidget(titleText, 1);
    sideLayout->addLayout(titleRow);

    archiveList_ = new QListWidget(side);
    archiveList_->setUniformItemSizes(false);
    archiveList_->setSelectionMode(QAbstractItemView::SingleSelection);
    sideLayout->addWidget(archiveList_, 1);

    auto *sideButtons = new QHBoxLayout();
    importButton_ = new QPushButton("Import", side);
    renameButton_ = new QPushButton("Rename", side);
    deleteButton_ = new QPushButton("Delete", side);
    sideButtons->addWidget(importButton_);
    sideButtons->addWidget(renameButton_);
    sideButtons->addWidget(deleteButton_);
    sideLayout->addLayout(sideButtons);

    auto *main = new QWidget(splitter);
    auto *mainLayout = new QVBoxLayout(main);
    mainLayout->setContentsMargins(8, 8, 8, 8);

    auto *topBar = new QHBoxLayout();
    loadEarlierButton_ = new QPushButton("Load Earlier", main);
    loadEarlierButton_->setEnabled(false);
    searchBox_ = new QLineEdit(main);
    searchBox_->setPlaceholderText("Search current chat");
    topBar->addWidget(loadEarlierButton_);
    topBar->addWidget(searchBox_, 1);
    mainLayout->addLayout(topBar);

    messageModel_ = new MessageModel(this);
    messageView_ = new QListView(main);
    messageView_->setModel(messageModel_);
    messageView_->setItemDelegate(new MessageDelegate(messageView_));
    messageView_->setUniformItemSizes(false);
    messageView_->setWordWrap(true);
    messageView_->setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);
    messageView_->setAlternatingRowColors(true);
    mainLayout->addWidget(messageView_, 1);

    splitter->addWidget(side);
    splitter->addWidget(main);
    splitter->setStretchFactor(0, 0);
    splitter->setStretchFactor(1, 1);
    splitter->setSizes({320, 880});

    setCentralWidget(central);
    statusBar()->showMessage("Ready");

    connect(importButton_, &QPushButton::clicked, this, &MainWindow::importFiles);
    connect(renameButton_, &QPushButton::clicked, this, &MainWindow::renameCurrentArchive);
    connect(deleteButton_, &QPushButton::clicked, this, &MainWindow::deleteCurrentArchive);
    connect(loadEarlierButton_, &QPushButton::clicked, this, &MainWindow::loadEarlier);
    connect(archiveList_, &QListWidget::currentRowChanged, this, [this](int row) {
        if (row < 0) return;
        const QString id = archiveList_->item(row)->data(Qt::UserRole).toString();
        loadArchive(id);
    });
    connect(searchBox_, &QLineEdit::returnPressed, this, [this] {
        searchMessages(searchBox_->text().trimmed());
    });
    connect(messageView_, &QListView::doubleClicked, this, &MainWindow::openSelectedMedia);
}

void MainWindow::refreshArchives() {
    Database db;
    db.initialize();
    archives_ = db.archives();

    archiveList_->clear();
    for (const ArchiveRow &archive : archives_) {
        const QString subtitle = QString("%1 messages%2\n%3")
            .arg(archive.messageCount)
            .arg(archive.mediaFileCount > 0 ? QString(" · %1 media").arg(archive.mediaFileCount) : QString())
            .arg(archive.preview.left(120));
        auto *item = new QListWidgetItem(archive.title + "\n" + subtitle, archiveList_);
        item->setData(Qt::UserRole, archive.id);
        item->setToolTip(archive.sourceFileName);
        item->setSizeHint(QSize(260, 72));
        archiveList_->addItem(item);
    }
}

ArchiveRow MainWindow::currentArchive() const {
    for (const ArchiveRow &archive : archives_) {
        if (archive.id == currentArchiveId_) return archive;
    }
    return {};
}

void MainWindow::setBusy(const QString &message) {
    loading_ = true;
    statusBar()->showMessage(message);
}

void MainWindow::clearBusy(const QString &message) {
    loading_ = false;
    statusBar()->showMessage(message.isEmpty() ? "Ready" : message);
}

void MainWindow::loadArchive(const QString &archiveId) {
    currentArchiveId_ = archiveId;
    searchBox_->clear();
    messageModel_->clear();
    messageModel_->setStorageDirectory(currentArchive().storageDirectory);
    canLoadEarlier_ = false;
    loadEarlierButton_->setEnabled(false);
    setBusy("Loading chat...");

    auto *watcher = new QFutureWatcher<QVector<MessageRow>>(this);
    connect(watcher, &QFutureWatcher<QVector<MessageRow>>::finished, this, [this, watcher, archiveId] {
        watcher->deleteLater();
        if (archiveId != currentArchiveId_) return;
        const QVector<MessageRow> rows = watcher->result();
        messageModel_->setMessages(rows);
        canLoadEarlier_ = !rows.isEmpty() && rows.first().sequenceIndex > 0;
        loadEarlierButton_->setEnabled(canLoadEarlier_);
        clearBusy(QString("Loaded %1 messages").arg(rows.size()));
        if (!rows.isEmpty()) {
            messageView_->scrollToBottom();
        }
    });
    watcher->setFuture(QtConcurrent::run([archiveId] {
        Database db;
        db.initialize();
        return db.recentMessages(archiveId, PageSize);
    }));
}

void MainWindow::loadEarlier() {
    if (currentArchiveId_.isEmpty() || messageModel_->messages().isEmpty() || loading_) return;
    const int before = messageModel_->messages().first().sequenceIndex;
    setBusy("Loading earlier messages...");

    auto *watcher = new QFutureWatcher<QVector<MessageRow>>(this);
    connect(watcher, &QFutureWatcher<QVector<MessageRow>>::finished, this, [this, watcher] {
        watcher->deleteLater();
        const QVector<MessageRow> rows = watcher->result();
        messageModel_->prependMessages(rows);
        canLoadEarlier_ = !messageModel_->messages().isEmpty() && messageModel_->messages().first().sequenceIndex > 0;
        loadEarlierButton_->setEnabled(canLoadEarlier_);
        clearBusy(QString("Loaded %1 earlier messages").arg(rows.size()));
    });
    const QString archiveId = currentArchiveId_;
    watcher->setFuture(QtConcurrent::run([archiveId, before] {
        Database db;
        db.initialize();
        return db.messagesBefore(archiveId, before, PageSize);
    }));
}

void MainWindow::searchMessages(const QString &query) {
    if (currentArchiveId_.isEmpty()) return;
    if (query.isEmpty()) {
        loadArchive(currentArchiveId_);
        return;
    }
    setBusy("Searching...");

    auto *watcher = new QFutureWatcher<QVector<MessageRow>>(this);
    connect(watcher, &QFutureWatcher<QVector<MessageRow>>::finished, this, [this, watcher] {
        watcher->deleteLater();
        const QVector<MessageRow> rows = watcher->result();
        messageModel_->setMessages(rows);
        loadEarlierButton_->setEnabled(false);
        clearBusy(QString("Found %1 messages").arg(rows.size()));
    });
    const QString archiveId = currentArchiveId_;
    watcher->setFuture(QtConcurrent::run([archiveId, query] {
        Database db;
        db.initialize();
        return db.messagesMatching(archiveId, query, 1000);
    }));
}

void MainWindow::importFiles() {
    const QStringList files = QFileDialog::getOpenFileNames(
        this,
        "Import WhatsApp Exports",
        QString(),
        "WhatsApp exports (*.txt *.zip)"
    );
    if (files.isEmpty()) return;

    setBusy(QString("Importing %1 file(s)...").arg(files.size()));
    importButton_->setEnabled(false);

    auto *watcher = new QFutureWatcher<QStringList>(this);
    connect(watcher, &QFutureWatcher<QStringList>::finished, this, [this, watcher] {
        watcher->deleteLater();
        importButton_->setEnabled(true);
        const QStringList errors = watcher->result();
        refreshArchives();
        clearBusy(errors.isEmpty() ? "Import complete" : "Import completed with errors");
        if (!errors.isEmpty()) {
            QMessageBox::warning(this, "Import Errors", errors.join("\n\n"));
        }
    });

    watcher->setFuture(QtConcurrent::run([files] {
        QStringList errors;
        Database db;
        db.initialize();
        for (const QString &file : files) {
            try {
                ParsedChat chat = Importer::parseFile(file);
                db.saveArchive(chat);
            } catch (const std::exception &error) {
                errors << QFileInfo(file).fileName() + ": " + error.what();
            }
        }
        return errors;
    }));
}

void MainWindow::deleteCurrentArchive() {
    const int row = archiveList_->currentRow();
    if (row < 0 || currentArchiveId_.isEmpty()) return;
    const QString archiveId = currentArchiveId_;
    const QString title = archiveList_->currentItem()->text().section('\n', 0, 0);
    if (QMessageBox::question(this, "Delete Chat", "Delete \"" + title + "\"?") != QMessageBox::Yes) {
        return;
    }

    delete archiveList_->takeItem(row);
    messageModel_->clear();
    messageModel_->setStorageDirectory({});
    currentArchiveId_.clear();
    setBusy("Deleting chat...");

    auto *watcher = new QFutureWatcher<QString>(this);
    connect(watcher, &QFutureWatcher<QString>::finished, this, [this, watcher] {
        watcher->deleteLater();
        const QString error = watcher->result();
        refreshArchives();
        clearBusy(error.isEmpty() ? "Deleted chat" : "Delete failed");
        if (!error.isEmpty()) QMessageBox::warning(this, "Delete Failed", error);
    });

    watcher->setFuture(QtConcurrent::run([archiveId] {
        try {
            Database db;
            db.initialize();
            const ArchiveRow archive = db.archive(archiveId);
            db.deleteArchive(archiveId);
            if (!archive.storageDirectory.isEmpty()) {
                QDir(archive.storageDirectory).removeRecursively();
            }
            return QString();
        } catch (const std::exception &error) {
            return QString(error.what());
        }
    }));
}

void MainWindow::renameCurrentArchive() {
    const int row = archiveList_->currentRow();
    if (row < 0 || currentArchiveId_.isEmpty()) return;

    const QString currentTitle = archiveList_->currentItem()->text().section('\n', 0, 0);
    bool ok = false;
    const QString newTitle = QInputDialog::getText(
        this,
        "Rename Chat",
        "Chat title:",
        QLineEdit::Normal,
        currentTitle,
        &ok
    ).trimmed();
    if (!ok || newTitle.isEmpty() || newTitle == currentTitle) return;

    try {
        Database db;
        db.initialize();
        db.renameArchive(currentArchiveId_, newTitle);
        refreshArchives();
        for (int i = 0; i < archiveList_->count(); ++i) {
            if (archiveList_->item(i)->data(Qt::UserRole).toString() == currentArchiveId_) {
                archiveList_->setCurrentRow(i);
                break;
            }
        }
        statusBar()->showMessage("Renamed chat");
    } catch (const std::exception &error) {
        QMessageBox::warning(this, "Rename Failed", error.what());
    }
}

void MainWindow::openSelectedMedia(const QModelIndex &index) {
    const QString mediaPath = index.data(MessageModel::MediaPathRole).toString();
    if (mediaPath.isEmpty()) return;
    QDesktopServices::openUrl(QUrl::fromLocalFile(mediaPath));
}
