import Foundation
import SwiftData

@Model
public final class ChatMessage {
    @Attribute(.unique) public var id: UUID
    public var senderName: String?
    public var body: String
    public var timestamp: Date?
    public var isSystemMessage: Bool
    public var isMediaPlaceholder: Bool
    public var isDeletedMessage: Bool = false
    public var mediaFileName: String?
    public var mediaTypeRaw: String?
    public var rawText: String
    public var sequenceIndex: Int

    public var chatArchive: ChatArchive?

    public init(
        id: UUID = UUID(),
        senderName: String? = nil,
        body: String,
        timestamp: Date? = nil,
        isSystemMessage: Bool = false,
        isMediaPlaceholder: Bool = false,
        isDeletedMessage: Bool = false,
        mediaFileName: String? = nil,
        mediaType: MediaType? = nil,
        rawText: String,
        sequenceIndex: Int
    ) {
        self.id = id
        self.senderName = senderName
        self.body = body
        self.timestamp = timestamp
        self.isSystemMessage = isSystemMessage
        self.isMediaPlaceholder = isMediaPlaceholder
        self.isDeletedMessage = isDeletedMessage
        self.mediaFileName = mediaFileName
        self.mediaTypeRaw = mediaType?.rawValue
        self.rawText = rawText
        self.sequenceIndex = sequenceIndex
    }

    public var mediaType: MediaType? {
        guard let mediaTypeRaw else { return nil }
        return MediaType(rawValue: mediaTypeRaw)
    }

    public var hasResolvableMedia: Bool {
        mediaFileName != nil && !isMediaPlaceholder
    }
}
