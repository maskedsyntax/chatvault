import Foundation
import SwiftData

@MainActor
public final class ChatStore {
    private let modelContext: ModelContext
    private let parser: WhatsAppChatParser

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.parser = WhatsAppChatParser()
    }

    public struct ParsedImport {
        public let parsed: ParsedChat
        public let suggestedTitle: String
        public let sourceFileName: String
        public let encodingName: String
    }

    public func parseChat(from url: URL) async throws -> ParsedImport {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.fileUnreadable
        }

        guard !data.isEmpty else {
            throw ImportError.emptyFile
        }

        let (text, encodingName) = try Self.decodeText(from: data)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ImportError.emptyFile
        }

        let parsedChat = parser.parse(text: text)
        guard !parsedChat.messages.isEmpty else {
            throw ImportError.noMessagesFound
        }

        let suggestedTitle = url.deletingPathExtension().lastPathComponent
        return ParsedImport(
            parsed: parsedChat,
            suggestedTitle: suggestedTitle,
            sourceFileName: url.lastPathComponent,
            encodingName: encodingName
        )
    }

    @discardableResult
    public func saveArchive(
        parsed: ParsedChat,
        title: String,
        sourceFileName: String
    ) throws -> ChatArchive {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ImportError.invalidTitle
        }

        let archive = ChatArchive(
            title: trimmedTitle,
            sourceFileName: sourceFileName,
            messageCount: parsed.messages.count,
            participants: parsed.participants,
            lastMessageDate: parsed.messages.last?.timestamp
        )

        modelContext.insert(archive)

        for (index, msg) in parsed.messages.enumerated() {
            let chatMessage = ChatMessage(
                senderName: msg.senderName,
                body: msg.body,
                timestamp: msg.timestamp,
                isSystemMessage: msg.isSystemMessage,
                isMediaPlaceholder: msg.isMediaPlaceholder,
                rawText: msg.rawText,
                sequenceIndex: index
            )
            chatMessage.chatArchive = archive
            modelContext.insert(chatMessage)
        }

        try modelContext.save()
        return archive
    }

    public func findPossibleDuplicate(sourceFileName: String, messageCount: Int) -> ChatArchive? {
        let descriptor = FetchDescriptor<ChatArchive>()
        guard let archives = try? modelContext.fetch(descriptor) else { return nil }
        return archives.first { $0.sourceFileName == sourceFileName && $0.messageCount == messageCount }
    }

    public func importChat(from url: URL) async throws -> ChatArchive {
        let parsedImport = try await parseChat(from: url)
        return try saveArchive(
            parsed: parsedImport.parsed,
            title: parsedImport.suggestedTitle,
            sourceFileName: parsedImport.sourceFileName
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

    private static func decodeText(from data: Data) throws -> (String, String) {
        let encodings: [(String.Encoding, String)] = [
            (.utf8, "UTF-8"),
            (.utf16, "UTF-16"),
            (.windowsCP1252, "Windows-1252"),
            (.isoLatin1, "ISO Latin-1"),
        ]

        for (encoding, name) in encodings {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return (text, name)
            }
        }

        throw ImportError.encodingFailed
    }

    public enum ImportError: LocalizedError {
        case fileUnreadable
        case encodingFailed
        case emptyFile
        case noMessagesFound
        case invalidTitle

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
            }
        }
    }
}
