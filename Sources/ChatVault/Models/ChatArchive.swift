import Foundation
import SwiftData

@Model
public final class ChatArchive {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var sourceFileName: String
    public var importedAt: Date
    public var messageCount: Int
    public var participants: [String]
    public var lastMessageDate: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var storageDirectory: String?
    public var mediaFileCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.chatArchive)
    public var messages: [ChatMessage] = []

    public init(
        id: UUID = UUID(),
        title: String,
        sourceFileName: String,
        importedAt: Date = Date(),
        messageCount: Int = 0,
        participants: [String] = [],
        lastMessageDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        storageDirectory: String? = nil,
        mediaFileCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.messageCount = messageCount
        self.participants = participants
        self.lastMessageDate = lastMessageDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.storageDirectory = storageDirectory
        self.mediaFileCount = mediaFileCount
    }
}

extension ChatArchive {
    public var mediaDirectoryURL: URL? {
        guard let storageDirectory else { return nil }
        return URL(fileURLWithPath: storageDirectory, isDirectory: true)
    }
}
