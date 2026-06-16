cmake_minimum_required(VERSION 3.24)

project(ChatVaultQt VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets Concurrent)
find_package(SQLite3 REQUIRED)

qt_add_executable(ChatVaultQt
    src/main.cpp
    src/MainWindow.cpp
    src/MainWindow.h
    src/Database.cpp
    src/Database.h
    src/Importer.cpp
    src/Importer.h
    src/MessageModel.cpp
    src/MessageModel.h
    src/MessageDelegate.cpp
    src/MessageDelegate.h
    resources.qrc
)

if(APPLE)
    target_sources(ChatVaultQt PRIVATE ../Resources/AppIcon.icns)
    set_source_files_properties(../Resources/AppIcon.icns PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )
endif()

target_link_libraries(ChatVaultQt
    PRIVATE
        Qt6::Widgets
        Qt6::Concurrent
        SQLite3::SQLite3
)

if(APPLE)
    set_target_properties(ChatVaultQt PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_GUI_IDENTIFIER com.maskedsyntax.chatvaultqt
        MACOSX_BUNDLE_BUNDLE_NAME "ChatVaultQt"
        MACOSX_BUNDLE_ICON_FILE AppIcon
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    )
endif()
