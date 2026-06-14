import Foundation
import SwiftData

@MainActor
public final class ChatStore {
    private let modelContext: ModelContext
    private let parser: WhatsAppChatParser

    private static let messageBatchSize = 500

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.parser = WhatsAppChatParser()
    }

    public struct ParsedImport: Identifiable {
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
        var imports: [ParsedImport] = []
        var errors: [(URL, Error)] = []

        for url in urls {
            do {
                imports.append(try await parseImport(from: url))
            } catch {
                errors.append((url, error))
            }
        }

        return (imports, errors)
    }

    public func parseChat(from url: URL) async throws -> ParsedImport {
        try await parseImport(from: url)
    }

    private func parseTextImport(from url: URL) async throws -> ParsedImport {
        let data = try readData(from: url)
        let (text, encodingName) = try Self.decodeText(from: data)
        let parsedChat = try parseText(text, sourceName: url.lastPathComponent)
        let suggestedTitle = url.deletingPathExtension().lastPathComponent

        return ParsedImport(
            parsed: parsedChat,
            suggestedTitle: suggestedTitle,
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
            let suggestedTitle = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "WhatsApp Chat with ", with: "")
                .replacingOccurrences(of: "WhatsApp Chat - ", with: "")

            return ParsedImport(
                parsed: parsedChat,
                suggestedTitle: suggestedTitle,
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
    public func saveArchive(from parsedImport: ParsedImport, title: String) throws -> ChatArchive {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw ImportError.invalidTitle }

        let archiveID = UUID()
        var storagePath: String?
        var mediaCount = parsedImport.mediaFileCount

        if let temporaryBundleURL = parsedImport.extractedBundleURL {
            let permanentURL = try ArchiveStorage.moveTemporaryBundle(from: temporaryBundleURL, to: archiveID)
            storagePath = permanentURL.path
            mediaCount = ArchiveStorage.mediaCount(in: permanentURL)
        }

        let archive = ChatArchive(
            id: archiveID,
            title: trimmedTitle,
            sourceFileName: parsedImport.sourceFileName,
            messageCount: parsedImport.parsed.messages.count,
            participants: parsedImport.parsed.participants,
            lastMessageDate: parsedImport.parsed.messages.last?.timestamp,
            storageDirectory: storagePath,
            mediaFileCount: mediaCount
        )

        modelContext.insert(archive)
        try insertMessages(parsedImport.parsed.messages, into: archive)
        try modelContext.save()
        return archive
    }

    @discardableResult
    public func reimportArchive(
        _ archive: ChatArchive,
        from parsedImport: ParsedImport,
        title: String? = nil
    ) throws -> ChatArchive {
        if let title {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { throw ImportError.invalidTitle }
            archive.title = trimmedTitle
        }

        deleteArchiveFiles(for: archive)

        for message in archive.messages {
            modelContext.delete(message)
        }
        archive.messages.removeAll()

        var storagePath: String?
        var mediaCount = parsedImport.mediaFileCount

        if let temporaryBundleURL = parsedImport.extractedBundleURL {
            let permanentURL = try ArchiveStorage.moveTemporaryBundle(from: temporaryBundleURL, to: archive.id)
            storagePath = permanentURL.path
            mediaCount = ArchiveStorage.mediaCount(in: permanentURL)
        }

        archive.sourceFileName = parsedImport.sourceFileName
        archive.messageCount = parsedImport.parsed.messages.count
        archive.participants = parsedImport.parsed.participants
        archive.lastMessageDate = parsedImport.parsed.messages.last?.timestamp
        archive.storageDirectory = storagePath
        archive.mediaFileCount = mediaCount
        archive.updatedAt = Date()

        try insertMessages(parsedImport.parsed.messages, into: archive)
        try modelContext.save()
        return archive
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

    private func insertMessages(_ parsedMessages: [ParsedMessage], into archive: ChatArchive) throws {
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

            if (index + 1) % Self.messageBatchSize == 0 {
                try modelContext.save()
            }
        }
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
