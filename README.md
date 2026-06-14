# ChatVault

Personal WhatsApp export viewer for macOS. All data stays local on your device.

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
