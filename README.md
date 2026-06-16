<div align="center">

<img src="logo.png" alt="ChatVault logo" width="128" />

# ChatVault

**A local-first WhatsApp export viewer for macOS, rewritten in Qt/C++ for performance.**

</div>

## Build

```bash
cmake -S qtcpp -B qtcpp/build -DCMAKE_BUILD_TYPE=Release
cmake --build qtcpp/build --config Release -j 8
```

## Run

```bash
open qtcpp/build/ChatVaultQt.app
```

## Import a chat

1. Export a chat from WhatsApp as `.txt` or `.zip`.
2. Open ChatVaultQt.
3. Click `Import` and select one or more exports.

ZIP imports keep extracted media in the app data folder. Images render inline as thumbnails; videos, audio, documents, and other files render as attachment rows. Double-click a media row to open the original file.

## Data

The Qt app stores its database separately from the previous Swift app, under the current macOS user's Application Support directory:

```text
$HOME/Library/Application Support/MaskedSyntax/ChatVaultQt/chatvault.sqlite3
```

## Features

- Fast SQLite-backed imports using transactions.
- Full-text search with SQLite FTS5.
- Paged message loading for large chats.
- Media thumbnails and attachment opening.
- Rename and delete archives.
