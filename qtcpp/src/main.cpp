#include "MainWindow.h"

#include <QApplication>

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    QApplication::setApplicationName("ChatVaultQt");
    QApplication::setOrganizationName("MaskedSyntax");

    MainWindow window;
    window.resize(1200, 780);
    window.show();

    return app.exec();
}
