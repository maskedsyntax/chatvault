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
        rawText: String,
        sequenceIndex: Int
    ) {
        self.id = id
        self.senderName = senderName
        self.body = body
        self.timestamp = timestamp
        self.isSystemMessage = isSystemMessage
        self.isMediaPlaceholder = isMediaPlaceholder
        self.rawText = rawText
        self.sequenceIndex = sequenceIndex
    }
}
