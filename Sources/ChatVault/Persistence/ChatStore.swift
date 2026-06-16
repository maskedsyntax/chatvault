import Foundation
import SwiftData

@MainActor
public final class ChatStore {
    private let modelContext: ModelContext
    private let parser: WhatsAppChatParser

    private static let messageBatchSize = 2_000
    private static let deletionBatchSize = 500

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.parser = WhatsAppChatParser()
    }

    public struct ParsedImport: Identifiable, Sendable {
        public let id = UUID()
        public let parsed: ParsedChat
        public let suggestedTitle: String
        public let sourceFileName: String
        public let encodingName: String
        public let extractedBundleURL: URL?
        public let mediaFileCount: Int

        public func cleanupTemporaryFiles() {
            guard let extractedBundleURL else { return }
            try? FileManager.default.removeItem(at: extractedBundleURL)
        }

        public var importSetup: ChatTitleSuggester.ImportSetup {
            ChatTitleSuggester.buildImportSetup(fileName: sourceFileName, parsed: parsed)
        }
    }

    public func parseImport(from url: URL) async throws -> ParsedImport {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if url.pathExtension.lowercased() == "zip" {
            return try await parseZipImport(from: url)
        }
        return try await parseTextImport(from: url)
    }

    public func parseImports(from urls: [URL]) async -> (imports: [ParsedImport], errors: [(URL, Error)]) {
        await Task.detached(priority: .userInitiated) {
            ZipImportParser.parseImports(from: urls)
        }.value
    }

    public func parseChat(from url: URL) async throws -> ParsedImport {
        try await parseImport(from: url)
    }

    private func parseTextImport(from url: URL) async throws -> ParsedImport {
        let data = try readData(from: url)
        let (text, encodingName) = try Self.decodeText(from: data)
        let parsedChat = try parseText(text, sourceName: url.lastPathComponent)
        _ = url.deletingPathExtension().lastPathComponent

        let setup = ChatTitleSuggester.buildImportSetup(
            fileName: url.lastPathComponent,
            parsed: parsedChat
        )

        return ParsedImport(
            parsed: parsedChat,
            suggestedTitle: setup.suggestedTitle,
            sourceFileName: url.lastPathComponent,
            encodingName: encodingName,
            extractedBundleURL: nil,
            mediaFileCount: 0
        )
    }

    private func parseZipImport(from url: URL) async throws -> ParsedImport {
        let tempDirectory = try ArchiveStorage.makeTemporaryImportDirectory()
        do {
            try ArchiveStorage.extractZip(from: url, to: tempDirectory)
            guard let chatFileURL = ArchiveStorage.findChatTextFile(in: tempDirectory) else {
                try? FileManager.default.removeItem(at: tempDirectory)
                throw ImportError.chatTextNotFoundInZip
            }

            let data = try readData(from: chatFileURL)
            let (text, encodingName) = try Self.decodeText(from: data)
            let parsedChat = try parseText(text, sourceName: chatFileURL.lastPathComponent)
            _ = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "WhatsApp Chat with ", with: "")
                .replacingOccurrences(of: "WhatsApp Chat - ", with: "")

            let setup = ChatTitleSuggester.buildImportSetup(
                fileName: url.lastPathComponent,
                parsed: parsedChat
            )

            return ParsedImport(
                parsed: parsedChat,
                suggestedTitle: setup.suggestedTitle,
                sourceFileName: url.lastPathComponent,
                encodingName: encodingName,
                extractedBundleURL: tempDirectory,
                mediaFileCount: ArchiveStorage.mediaCount(in: tempDirectory)
            )
        } catch {
            try? FileManager.default.removeItem(at: tempDirectory)
            throw error
        }
    }

    private func parseText(_ text: String, sourceName: String) throws -> ParsedChat {
        let normalized = WhatsAppChatParser.normalizeInput(text)
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyFile }

        let parsedChat = parser.parse(text: normalized)
        guard !parsedChat.messages.isEmpty else { throw ImportError.noMessagesFound }
        _ = sourceName
        return parsedChat
    }

    @discardableResult
    public func saveArchive(from parsedImport: ParsedImport, configuration: ImportConfiguration) throws -> ChatArchive {
        let trimmedTitle = configuration.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw ImportError.invalidTitle }

        let archiveID = UUID()
        var storagePath: String?
        var mediaCount = parsedImport.mediaFileCount

        if let temporaryBundleURL = parsedImport.extractedBundleURL {
            let permanentURL = try ArchiveStorage.moveTemporaryBundle(from: temporaryBundleURL, to: archiveID)
            storagePath = permanentURL.path
            mediaCount = ArchiveStorage.mediaCount(in: permanentURL)
        }

        let participantNames = configuration.participants.map(\.exportName)
        let archive = ChatArchive(
            id: archiveID,
            title: trimmedTitle,
            sourceFileName: parsedImport.sourceFileName,
            messageCount: parsedImport.parsed.messages.count,
            participants: participantNames,
            lastMessageDate: parsedImport.parsed.messages.last?.timestamp,
            storageDirectory: storagePath,
            mediaFileCount: mediaCount
        )

        modelContext.insert(archive)
        let indexedMessages = try insertMessages(parsedImport.parsed.messages, into: archive)
        try applyParticipants(configuration.participants, to: archive)
        try modelContext.save()
        scheduleSearchIndexRebuild(for: archive.id, messages: indexedMessages)
        return archive
    }

    @discardableResult
    public func saveArchive(from parsedImport: ParsedImport, title: String) throws -> ChatArchive {
        let setup = parsedImport.importSetup
        let configuration = ImportConfiguration(
            title: title,
            participants: setup.participantDrafts
        )
        return try saveArchive(from: parsedImport, configuration: configuration)
    }

    @discardableResult
    public func reimportArchive(
        _ archive: ChatArchive,
        from parsedImport: ParsedImport,
        configuration: ImportConfiguration
    ) throws -> ChatArchive {
        let trimmedTitle = configuration.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw ImportError.invalidTitle }
        archive.title = trimmedTitle

        deleteArchiveFiles(for: archive)
        try deleteSearchIndex(for: archive)

        try deleteMessagesAndParticipants(for: archive.id)

        var storagePath: String?
        var mediaCount = parsedImport.mediaFileCount

        if let temporaryBundleURL = parsedImport.extractedBundleURL {
            let permanentURL = try ArchiveStorage.moveTemporaryBundle(from: temporaryBundleURL, to: archive.id)
            storagePath = permanentURL.path
            mediaCount = ArchiveStorage.mediaCount(in: permanentURL)
        } else {
            storagePath = nil
        }

        archive.sourceFileName = parsedImport.sourceFileName
        archive.messageCount = parsedImport.parsed.messages.count
        archive.participants = configuration.participants.map(\.exportName)
        archive.lastMessageDate = parsedImport.parsed.messages.last?.timestamp
        archive.storageDirectory = storagePath
        archive.mediaFileCount = mediaCount
        archive.updatedAt = Date()

        let indexedMessages = try insertMessages(parsedImport.parsed.messages, into: archive)
        try applyParticipants(configuration.participants, to: archive)
        try modelContext.save()
        scheduleSearchIndexRebuild(for: archive.id, messages: indexedMessages)
        return archive
    }

    @discardableResult
    public func reimportArchive(
        _ archive: ChatArchive,
        from parsedImport: ParsedImport,
        title: String? = nil
    ) throws -> ChatArchive {
        let setup = parsedImport.importSetup
        let configuration = ImportConfiguration(
            title: title ?? archive.title,
            participants: setup.participantDrafts
        )
        return try reimportArchive(archive, from: parsedImport, configuration: configuration)
    }

    @discardableResult
    public func saveArchive(
        parsed: ParsedChat,
        title: String,
        sourceFileName: String
    ) throws -> ChatArchive {
        let importValue = ParsedImport(
            parsed: parsed,
            suggestedTitle: title,
            sourceFileName: sourceFileName,
            encodingName: "UTF-8",
            extractedBundleURL: nil,
            mediaFileCount: 0
        )
        return try saveArchive(from: importValue, title: title)
    }

    @discardableResult
    private func insertMessages(_ parsedMessages: [ParsedMessage], into archive: ChatArchive) throws -> [MessageSearchIndex.IndexedMessage] {
        var indexedMessages: [MessageSearchIndex.IndexedMessage] = []
        indexedMessages.reserveCapacity(parsedMessages.count)

        for (index, msg) in parsedMessages.enumerated() {
            let chatMessage = ChatMessage(
                senderName: msg.senderName,
                body: msg.body,
                timestamp: msg.timestamp,
                isSystemMessage: msg.isSystemMessage,
                isMediaPlaceholder: msg.isMediaPlaceholder,
                isDeletedMessage: msg.isDeletedMessage,
                mediaFileName: msg.mediaFileName,
                mediaType: msg.mediaType,
                rawText: msg.rawText,
                sequenceIndex: index
            )
            chatMessage.chatArchive = archive
            modelContext.insert(chatMessage)
            indexedMessages.append(
                MessageSearchIndex.IndexedMessage(
                    id: chatMessage.id,
                    body: chatMessage.body,
                    senderName: chatMessage.senderName,
                    timestamp: chatMessage.timestamp
                )
            )

            if (index + 1) % Self.messageBatchSize == 0 {
                try modelContext.save()
            }
        }
        return indexedMessages
    }

    public func findPossibleDuplicate(sourceFileName: String, messageCount: Int) -> ChatArchive? {
        let descriptor = FetchDescriptor<ChatArchive>()
        guard let archives = try? modelContext.fetch(descriptor) else { return nil }
        return archives.first { $0.sourceFileName == sourceFileName && $0.messageCount == messageCount }
    }

    public func importChat(from url: URL) async throws -> ChatArchive {
        let parsedImport = try await parseImport(from: url)
        return try saveArchive(from: parsedImport, title: parsedImport.suggestedTitle)
    }

    public func deleteArchiveFiles(for archive: ChatArchive) {
        ArchiveStorage.deleteBundle(at: archive.storageDirectory)
    }

    public func deleteSearchIndex(for archive: ChatArchive) throws {
        try MessageSearchIndex.shared.deleteIndex(for: archive.id)
    }

    public func deleteArchive(withID id: UUID) async throws {
        let descriptor = FetchDescriptor<ChatArchive>(
            predicate: #Predicate<ChatArchive> { $0.id == id }
        )
        guard let archive = try modelContext.fetch(descriptor).first else { return }
        deleteArchiveFiles(for: archive)
        try deleteSearchIndex(for: archive)
        try await deleteMessagesAndParticipantsForDeletion(for: id)
        modelContext.delete(archive)
        try modelContext.save()
    }

    public func scheduleArchiveDeletion(id: UUID, clearSelection: () -> Void) {
        clearSelection()
        Task { @MainActor in
            await Task.yield()
            try? await deleteArchive(withID: id)
        }
    }

    public func ensureParticipantRecords(for archive: ChatArchive) throws {
        guard archive.participantRecords.isEmpty, !archive.participants.isEmpty else { return }

        for name in archive.participants {
            let participant = ChatParticipant(
                exportName: name,
                displayName: name
            )
            participant.chatArchive = archive
            modelContext.insert(participant)
        }
        try modelContext.save()
    }

    public func searchMessages(in archive: ChatArchive, query: String) throws -> [UUID] {
        try MessageSearchIndex.shared.search(archiveID: archive.id, query: query)
    }

    public func messageDays(for archive: ChatArchive) throws -> [MessageDaySummary] {
        try MessageSearchIndex.shared.messageDays(for: archive.id)
    }

    public func recentMessages(for archive: ChatArchive, limit: Int) throws -> [ChatMessage] {
        let archiveID = archive.id
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { message in
                message.chatArchive?.id == archiveID
            },
            sortBy: [SortDescriptor(\.sequenceIndex, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).reversed()
    }

    public func messagesBefore(
        archive: ChatArchive,
        sequenceIndex: Int,
        limit: Int
    ) throws -> [ChatMessage] {
        let archiveID = archive.id
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { message in
                message.chatArchive?.id == archiveID && message.sequenceIndex < sequenceIndex
            },
            sortBy: [SortDescriptor(\.sequenceIndex, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).reversed()
    }

    public func messageWindow(
        archive: ChatArchive,
        containing messageID: UUID,
        radius: Int
    ) throws -> [ChatMessage] {
        let archiveID = archive.id
        var targetDescriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { message in
                message.chatArchive?.id == archiveID && message.id == messageID
            }
        )
        targetDescriptor.fetchLimit = 1
        guard let target = try modelContext.fetch(targetDescriptor).first else { return [] }

        let lowerBound = max(0, target.sequenceIndex - radius)
        let upperBound = target.sequenceIndex + radius
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { message in
                message.chatArchive?.id == archiveID &&
                message.sequenceIndex >= lowerBound &&
                message.sequenceIndex <= upperBound
            },
            sortBy: [SortDescriptor(\.sequenceIndex, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    public func messages(matching ids: [UUID], in archive: ChatArchive) throws -> [ChatMessage] {
        guard !ids.isEmpty else { return [] }
        let archiveID = archive.id
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { message in
                message.chatArchive?.id == archiveID && idSet.contains(message.id)
            },
            sortBy: [SortDescriptor(\.sequenceIndex, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    public func mediaLinkedMessages(for archive: ChatArchive) throws -> [String: ChatMessage] {
        let archiveID = archive.id
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { message in
                message.chatArchive?.id == archiveID && message.mediaFileName != nil
            },
            sortBy: [SortDescriptor(\.sequenceIndex, order: .forward)]
        )
        let messages = try modelContext.fetch(descriptor)
        return Dictionary(
            messages.compactMap { message -> (String, ChatMessage)? in
                guard let fileName = message.mediaFileName else { return nil }
                return (fileName, message)
            },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    public func birthdaysToday() -> [BirthdayReminder] {
        let descriptor = FetchDescriptor<ChatParticipant>()
        guard let participants = try? modelContext.fetch(descriptor) else { return [] }

        return participants.compactMap { participant in
            guard !participant.isMe,
                  participant.birthdayMatchesToday(),
                  let archive = participant.chatArchive else { return nil }
            return BirthdayReminder(
                personName: participant.resolvedName,
                archiveID: archive.id,
                archiveTitle: archive.title,
                birthdayNote: participant.birthdayNote
            )
        }
        .sorted { $0.personName.localizedStandardCompare($1.personName) == .orderedAscending }
    }

    public func rescanBirthdays(for archive: ChatArchive) throws {
        let messages = try fetchMessages(for: archive.id)
        let parsedMessages = messages.map(Self.parsedMessage(from:))
        let birthdays = BirthdayExtractor.extract(from: parsedMessages, participants: archive.participants)

        for participant in archive.participantRecords {
            if let match = birthdays[participant.exportName] {
                participant.birthdayMonth = match.month
                participant.birthdayDay = match.day
                participant.birthdayNote = match.note
            }
        }
        archive.updatedAt = Date()
        try modelContext.save()
    }

    private func applyParticipants(_ drafts: [ImportParticipantDraft], to archive: ChatArchive) throws {
        for draft in drafts {
            let participant = ChatParticipant(
                exportName: draft.exportName,
                displayName: draft.displayName,
                isMe: draft.isMe,
                birthdayMonth: draft.birthdayMonth,
                birthdayDay: draft.birthdayDay,
                birthdayNote: draft.birthdayNote
            )
            participant.chatArchive = archive
            modelContext.insert(participant)
        }
    }

    public func rebuildSearchIndexIfNeeded(for archive: ChatArchive) throws {
        let existingDays = try MessageSearchIndex.shared.messageDays(for: archive.id)
        guard existingDays.isEmpty, archive.messageCount > 0 else { return }
        let messages = try fetchMessages(for: archive.id)
        let indexedMessages = messages.map(Self.indexedMessage(from:))
        try rebuildSearchIndex(for: archive.id, messages: indexedMessages)
    }

    private func rebuildSearchIndex(for archiveID: UUID, messages: [MessageSearchIndex.IndexedMessage]) throws {
        try MessageSearchIndex.shared.rebuildIndex(archiveID: archiveID, messages: messages)
    }

    private func scheduleSearchIndexRebuild(
        for archiveID: UUID,
        messages: [MessageSearchIndex.IndexedMessage]
    ) {
        Task { @MainActor in
            try? rebuildSearchIndex(for: archiveID, messages: messages)
        }
    }

    private func fetchMessages(for archiveID: UUID) throws -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { message in
                message.chatArchive?.id == archiveID
            },
            sortBy: [SortDescriptor(\.sequenceIndex, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func deleteMessagesAndParticipants(for archiveID: UUID) throws {
        try deleteMessages(for: archiveID)
        try deleteParticipants(for: archiveID)
    }

    private func deleteMessagesAndParticipantsForDeletion(for archiveID: UUID) async throws {
        try await deleteMessagesForDeletion(for: archiveID)
        try deleteParticipants(for: archiveID)
    }

    private func deleteMessages(for archiveID: UUID) throws {
        while true {
            var descriptor = FetchDescriptor<ChatMessage>(
                predicate: #Predicate<ChatMessage> { message in
                    message.chatArchive?.id == archiveID
                }
            )
            descriptor.fetchLimit = Self.messageBatchSize
            let messages = try modelContext.fetch(descriptor)
            guard !messages.isEmpty else { return }
            for message in messages {
                modelContext.delete(message)
            }
            try modelContext.save()
        }
    }

    private func deleteMessagesForDeletion(for archiveID: UUID) async throws {
        while true {
            var descriptor = FetchDescriptor<ChatMessage>(
                predicate: #Predicate<ChatMessage> { message in
                    message.chatArchive?.id == archiveID
                }
            )
            descriptor.fetchLimit = Self.deletionBatchSize
            let messages = try modelContext.fetch(descriptor)
            guard !messages.isEmpty else { return }
            for message in messages {
                modelContext.delete(message)
            }
            try modelContext.save()
            await Task.yield()
        }
    }

    private func deleteParticipants(for archiveID: UUID) throws {
        let descriptor = FetchDescriptor<ChatParticipant>(
            predicate: #Predicate<ChatParticipant> { participant in
                participant.chatArchive?.id == archiveID
            }
        )
        for participant in try modelContext.fetch(descriptor) {
            modelContext.delete(participant)
        }
    }

    private static func parsedMessage(from message: ChatMessage) -> ParsedMessage {
        ParsedMessage(
            timestamp: message.timestamp,
            senderName: message.senderName,
            body: message.body,
            isSystemMessage: message.isSystemMessage,
            isMediaPlaceholder: message.isMediaPlaceholder,
            isDeletedMessage: message.isDeletedMessage,
            mediaFileName: message.mediaFileName,
            mediaType: message.mediaType,
            rawText: message.rawText
        )
    }

    private static func indexedMessage(from message: ChatMessage) -> MessageSearchIndex.IndexedMessage {
        MessageSearchIndex.IndexedMessage(
            id: message.id,
            body: message.body,
            senderName: message.senderName,
            timestamp: message.timestamp
        )
    }

    public func firstMessageDate(for archive: ChatArchive) -> Date? {
        let archiveId = archive.id
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { message in
                message.chatArchive?.id == archiveId
            },
            sortBy: [SortDescriptor(\.sequenceIndex, order: .forward)]
        )
        descriptor.fetchLimit = 100
        let messages = (try? modelContext.fetch(descriptor)) ?? []
        return messages.first(where: { $0.timestamp != nil })?.timestamp
    }

    public func mediaItems(for archive: ChatArchive) -> [MediaItem] {
        guard let storagePath = archive.storageDirectory else { return [] }
        return ArchiveStorage.mediaFiles(in: URL(fileURLWithPath: storagePath, isDirectory: true)).map {
            MediaItem(
                fileName: $0.lastPathComponent,
                fileURL: $0,
                mediaType: MediaType.infer(from: $0.lastPathComponent)
            )
        }
    }

    private func readData(from url: URL) throws -> Data {
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw ImportError.emptyFile }
            return data
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.fileUnreadable
        }
    }

    private static func decodeText(from data: Data) throws -> (String, String) {
        var payload = data
        if payload.starts(with: [0xEF, 0xBB, 0xBF]) {
            payload.removeFirst(3)
        }

        let encodings: [(String.Encoding, String)] = [
            (.utf8, "UTF-8"),
            (.utf16, "UTF-16"),
            (.windowsCP1252, "Windows-1252"),
            (.isoLatin1, "ISO Latin-1"),
        ]

        for (encoding, name) in encodings {
            if let text = String(data: payload, encoding: encoding), !text.isEmpty {
                return (text, name)
            }
        }

        throw ImportError.encodingFailed
    }

    public enum ImportError: LocalizedError, Equatable {
        case fileUnreadable
        case encodingFailed
        case emptyFile
        case noMessagesFound
        case invalidTitle
        case chatTextNotFoundInZip

        public var errorDescription: String? {
            switch self {
            case .fileUnreadable:
                return "The selected file could not be read."
            case .encodingFailed:
                return "Could not detect a supported text encoding for this file."
            case .emptyFile:
                return "The selected file is empty."
            case .noMessagesFound:
                return "No valid messages were found in the selected file."
            case .invalidTitle:
                return "Please enter a valid chat title."
            case .chatTextNotFoundInZip:
                return "No chat .txt file was found inside the ZIP archive."
            }
        }
    }
}

public struct MediaItem: Identifiable, Hashable {
    public let id: String
    public let fileName: String
    public let fileURL: URL
    public let mediaType: MediaType

    public init(fileName: String, fileURL: URL, mediaType: MediaType) {
        self.id = fileName
        self.fileName = fileName
        self.fileURL = fileURL
        self.mediaType = mediaType
    }
}
