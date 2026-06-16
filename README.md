<div align="center">

<img src="logo.png" alt="ChatVault logo" width="128" />

# ChatVault

**A local-first WhatsApp export viewer for macOS.** Import `.txt` or `.zip` chats, browse messages in a familiar UI, search history, and inspect media — all without leaving your Mac.

<br />

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-007AFF?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

## Run the app

`swift run` launches a raw executable — macOS treats that as a background tool, so it won't get a Dock icon and its window can stay behind other apps.

Build and launch a proper `.app` bundle instead:

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open build/ChatVault.app
```

For day-to-day use, drag `build/ChatVault.app` to Applications or the Dock.

## Development

```bash
swift build
swift test
```

## Import a chat

1. Export a chat from WhatsApp on Android as `.txt` or `.zip` (with media)
2. Open ChatVault
3. Click **Import Chat**, drag-and-drop a file onto the sidebar, or pick a file
4. Review the preview, confirm the title, and import

ZIP exports are extracted locally. Images and videos appear inline in the chat; use the **Media Inspector** (photo toolbar button) to browse all attachments.

## Features

- WhatsApp-style chat bubbles with sent/received alignment
- Batch import of multiple `.txt` / `.zip` exports
- Full-text search, date jump, and media inspector
- Participant names, birthday detection, and archive management
- Delete chats from the sidebar with confirmation
