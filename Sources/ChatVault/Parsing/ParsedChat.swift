import Foundation

public struct ParsedMessage: Equatable, Identifiable {
    public let id = UUID()
    public let timestamp: Date?
    public let senderName: String?
    public let body: String
    public let isSystemMessage: Bool
    public let isMediaPlaceholder: Bool
    public let mediaFileName: String?
    public let mediaType: MediaType?
    public let rawText: String

    public init(
        timestamp: Date?,
        senderName: String?,
        body: String,
        isSystemMessage: Bool,
        isMediaPlaceholder: Bool,
        mediaFileName: String? = nil,
        mediaType: MediaType? = nil,
        rawText: String
    ) {
        self.timestamp = timestamp
        self.senderName = senderName
        self.body = body
        self.isSystemMessage = isSystemMessage
        self.isMediaPlaceholder = isMediaPlaceholder
        self.mediaFileName = mediaFileName
        self.mediaType = mediaType
        self.rawText = rawText
    }

    public var hasAttachedMedia: Bool {
        mediaFileName != nil
    }
}

public struct ParsedChat: Equatable {
    public let messages: [ParsedMessage]
    public let participants: [String]
    public let warnings: [ParserWarning]

    public init(messages: [ParsedMessage], participants: [String], warnings: [ParserWarning]) {
        self.messages = messages
        self.participants = participants
        self.warnings = warnings
    }

    public var attachedMediaCount: Int {
        messages.filter(\.hasAttachedMedia).count
    }
}
