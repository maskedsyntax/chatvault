# ChatVault — Personal WhatsApp Export Viewer

## 1. Project Overview

**ChatVault** is a private, local-only Swift app for viewing old WhatsApp chats exported from Android before switching to iPhone.

The app is not intended for App Store release, cloud sync, analytics, monetization, or public use. It exists only as a personal archive browser so old WhatsApp conversations remain readable on macOS and iOS after moving away from Android.

The app should support importing exported WhatsApp `.txt` chat files, parsing the messages, storing them locally, and presenting them in a clean chat-style interface similar to a messaging app.

## 2. Product Goals

- Allow personal WhatsApp chat exports to be imported and viewed later.
- Work on both **macOS** and **iOS** using Swift.
- Keep all data fully local on the device.
- Make old chats easy to search, browse, and read.
- Preserve message timestamps, sender names, message text, and system messages.
- Support large chat exports without making the app feel slow.
- Avoid unnecessary complexity because this is a personal utility, not a commercial product.

## 3. Non-Goals

- No WhatsApp account login.
- No scraping WhatsApp.
- No restoring chats back into WhatsApp.
- No iCloud sync for the first version.
- No server, backend, or online storage.
- No App Store launch requirement.
- No support for sending messages.
- No end-to-end encrypted WhatsApp backup parsing.
- No Android app version.

## 4. Target Platforms

### macOS

Primary platform for importing, organizing, and browsing old chats.

Minimum target:

- macOS 14+
- SwiftUI
- SwiftData or SQLite-backed local storage

### iOS

Secondary platform for reading imported chats on iPhone.

Minimum target:

- iOS 17+
- SwiftUI
- Local file import through Files app

## 5. Suggested Tech Stack

- **Language:** Swift
- **UI:** SwiftUI
- **Architecture:** MVVM or lightweight feature-based architecture
- **Persistence:** SwiftData for simplicity, or SQLite if performance becomes an issue
- **File Import:** Document Picker / fileImporter
- **Parsing:** Custom WhatsApp export parser in Swift
- **Search:** Local search over stored message text and sender names
- **Testing:** XCTest for parser tests

Recommended first approach: **SwiftUI + SwiftData**.

If very large exports become slow, migrate the message storage layer to SQLite later.

## 6. App Name

Primary name: **ChatVault**

Alternative names:

- ArchiveChat
- PastPing
- WArchive
- Chattrace
- EchoThread
- OldThread
- MemoChat

Recommended final name: **ChatVault** because it clearly communicates a private, personal archive.

## 7. Core User Flow

1. Export WhatsApp chat from Android.
2. Transfer the exported `.txt` file to Mac or iPhone.
3. Open ChatVault.
4. Import the exported chat file.
5. App parses the chat.
6. User confirms chat name/contact name.
7. App stores parsed messages locally.
8. User can browse the chat in a WhatsApp-like view.
9. User can search old messages when needed.

## 8. WhatsApp Export Format Support

WhatsApp exports usually produce a `.txt` file with message lines similar to:

```txt
12/05/24, 9:42 PM - Aftaab: Hey, are you free?
12/05/24, 9:43 PM - Akanksha: Yes
12/05/24, 9:44 PM - Messages and calls are end-to-end encrypted.
```

Some exports may use 24-hour time:

```txt
12/05/2024, 21:42 - Aftaab: Hey
```

Some messages may span multiple lines:

```txt
12/05/24, 9:42 PM - Aftaab: This is a long message
that continues on another line
and another line.
```

The parser must handle:

- 12-hour time format
- 24-hour time format
- 2-digit and 4-digit years
- Multi-line messages
- System messages without sender
- Deleted message placeholders
- Media placeholders such as `<Media omitted>`
- Different date separators if practical: `/`, `-`, `.`

## 9. Data Model

### ChatArchive

Represents one imported WhatsApp chat export.

Fields:

- `id: UUID`
- `title: String`
- `sourceFileName: String`
- `importedAt: Date`
- `messageCount: Int`
- `participants: [String]`
- `lastMessageDate: Date?`
- `createdAt: Date`
- `updatedAt: Date`

### ChatMessage

Represents a single parsed message.

Fields:

- `id: UUID`
- `chatArchiveId: UUID`
- `senderName: String?`
- `body: String`
- `timestamp: Date?`
- `isSystemMessage: Bool`
- `isMediaPlaceholder: Bool`
- `rawText: String`
- `sequenceIndex: Int`

### Participant

Optional model if needed later.

Fields:

- `id: UUID`
- `chatArchiveId: UUID`
- `name: String`
- `messageCount: Int`

## 10. Main Screens

### 10.1 Archive List

Shows all imported chats.

Content:

- Chat title
- Last message preview
- Message count
- Last message date
- Import date

Actions:

- Import new chat
- Delete archive
- Rename archive
- Open archive

### 10.2 Import Screen

Allows the user to pick a WhatsApp exported `.txt` file.

Import steps:

- Pick file
- Read text
- Detect encoding
- Parse messages
- Show import preview
- Confirm chat title
- Save archive locally

Preview should show:

- Detected participants
- Total messages
- First message date
- Last message date
- Sample messages
- Any parsing warnings

### 10.3 Chat Viewer

Displays messages in a chat-style interface.

Features:

- Message bubbles
- Sender name shown for group chats
- Timestamp display
- System messages centered
- Media placeholders styled differently
- Jump to latest / earliest
- Scroll performance for long chats

### 10.4 Search

Search inside an archive.

Features:

- Search message text
- Search sender name
- Results grouped by date
- Tap result to jump to message

### 10.5 Archive Details

Shows metadata about the imported chat.

Content:

- Title
- Source file name
- Imported date
- Message count
- Participants
- Date range
- Storage size if available

Actions:

- Rename archive
- Delete archive
- Re-import from file

## 11. MVP Features

Version 0.1 should include:

- Import `.txt` WhatsApp chat export
- Parse messages locally
- Store archive locally
- Show archive list
- Open chat viewer
- Display message bubbles
- Support multi-line messages
- Basic search inside one chat
- Delete archive
- Rename archive

## 12. Nice-to-Have Features

Possible later additions:

- Import multiple chats
- Better group chat support
- Contact color assignment
- Date jump picker
- Calendar timeline
- Export parsed archive as JSON
- Export archive as PDF
- Full-text search index
- Attachments folder support
- Password lock / Face ID
- iCloud Drive manual backup
- Statistics screen: messages per participant, busiest days, common words
- Memories mode: “On this day” old messages

## 13. Privacy and Security

The app should be private by design.

Rules:

- No network calls.
- No analytics.
- No crash reporting service.
- No remote database.
- No cloud sync in MVP.
- No third-party SDKs unless absolutely required.
- All imported chats stay on the device.

For personal use, signing with a local developer account is enough.

## 14. Parser Requirements

The parser should be its own separate module so it can be tested independently.

Example structure:

```swift
struct WhatsAppChatParser {
    func parse(text: String) throws -> ParsedChat
}
```

Parser responsibilities:

- Split raw text into logical messages.
- Detect whether a line starts a new message.
- Append continuation lines to the previous message.
- Extract timestamp.
- Extract sender name when available.
- Detect system messages.
- Detect media placeholders.
- Return parsing warnings instead of failing completely where possible.

### Parsing Strategy

1. Read file as text.
2. Normalize line endings.
3. Iterate line by line.
4. Use regex to detect message-start lines.
5. If line matches message format, create a new message.
6. If line does not match, append to previous message body.
7. After parsing, infer participants from sender names.
8. Return parsed result.

## 15. Example Regex Ideas

These are starting points and should be refined during implementation.

12-hour format:

```regex
^(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}),\s+(\d{1,2}:\d{2})\s?(AM|PM|am|pm)\s-\s(.+)$
```

24-hour format:

```regex
^(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}),\s+(\d{1,2}:\d{2})\s-\s(.+)$
```

Sender split:

```txt
Sender Name: Message body
```

If the content after the timestamp does not contain `:`, treat it as a system message.

## 16. Architecture

Suggested folder structure:

```txt
ChatVault/
  App/
    ChatVaultApp.swift
  Features/
    ArchiveList/
    ImportChat/
    ChatViewer/
    Search/
    ArchiveDetails/
  Models/
    ChatArchive.swift
    ChatMessage.swift
    Participant.swift
  Parsing/
    WhatsAppChatParser.swift
    ParsedChat.swift
    ParserWarning.swift
  Persistence/
    ChatStore.swift
  Shared/
    Extensions/
    Components/
  Tests/
    WhatsAppChatParserTests.swift
```

## 17. UI Direction

The app should feel calm, private, and practical.

Visual style:

- Native SwiftUI look
- Clean sidebar on macOS
- Simple list navigation on iOS
- Soft message bubbles
- Muted colors
- Good dark mode support
- No overly fancy animations

macOS layout:

- Sidebar: imported archives
- Main panel: selected chat
- Toolbar: import, search, archive info

iOS layout:

- Archive list
- Chat viewer pushed through NavigationStack
- Search accessible from toolbar

## 18. Performance Considerations

Large WhatsApp exports can contain tens or hundreds of thousands of lines.

Important considerations:

- Avoid loading too many SwiftUI views at once.
- Use lazy lists for message rendering.
- Store messages incrementally if needed.
- Avoid reparsing every app launch.
- Cache parsed messages in local storage.
- Consider SQLite if SwiftData struggles with very large archives.

## 19. Error Handling

Possible errors:

- Unsupported file type
- Empty file
- File could not be read
- Encoding detection failed
- No messages detected
- Too many malformed lines
- Duplicate archive imported

Errors should be shown in a friendly way, with enough detail to debug personally.

## 20. Testing Plan

Parser tests should cover:

- Basic one-to-one chat
- Group chat
- Multi-line messages
- System messages
- 12-hour time format
- 24-hour time format
- Media omitted messages
- Deleted messages
- Messages with colons in body
- Messages with names containing spaces
- Large sample file performance

## 21. Development Roadmap

### Phase 1 — Parser Prototype

- Create Swift package or parser module.
- Add sample exported chat fixtures.
- Parse basic messages.
- Add unit tests.

### Phase 2 — macOS MVP

- Build archive list.
- Add file importer.
- Parse and save imported chat.
- Display messages in chat viewer.
- Add delete and rename.

### Phase 3 — iOS Support

- Add iOS target.
- Reuse parser and models.
- Implement iOS file import.
- Build iPhone-friendly archive list and chat viewer.

### Phase 4 — Search and Polish

- Add local search.
- Add archive details.
- Improve empty states and errors.
- Add dark mode polish.

### Phase 5 — Optional Personal Enhancements

- Add Face ID lock.
- Add JSON export.
- Add stats.
- Add manual backup/import package.

## 22. First Build Prompt for Coding Agent

Build a SwiftUI app called ChatVault for macOS and iOS. The app is a private local-only viewer for exported WhatsApp `.txt` chats. Start by implementing the parser module with tests. The parser should handle WhatsApp export lines with timestamps, sender names, system messages, media placeholders, and multi-line messages. Then create a basic SwiftUI UI with an archive list, file importer, local persistence, and a chat-style viewer. Prioritize clean architecture, local-only privacy, and parser correctness over visual complexity.
