# ChatVaultQt

Native Qt/C++ rewrite focused on performance.

## Build

```sh
cmake -S qtcpp -B qtcpp/build -DCMAKE_BUILD_TYPE=Release
cmake --build qtcpp/build --config Release -j 8
```

## Run

```sh
open qtcpp/build/ChatVaultQt.app
```

Data is stored separately from the Swift app at the Qt application data path:

```text
~/Library/Application Support/MaskedSyntax/ChatVaultQt/chatvault.sqlite3
```

The importer stores messages in SQLite using one transaction per archive, builds FTS search in the same transaction, and loads chat messages in pages instead of loading the full chat into memory.

Media from ZIP imports is kept in the app data folder. Images render as inline thumbnails; videos, audio, documents, and other files render as attachment rows. Double-click a media row to open the original file.
