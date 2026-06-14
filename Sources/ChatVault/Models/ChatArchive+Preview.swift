import Foundation
import SwiftData

extension ChatArchive {
    func lastMessagePreview(in context: ModelContext) -> String? {
        let archiveId = id
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { message in
                message.chatArchive?.id == archiveId
            },
            sortBy: [SortDescriptor(\.sequenceIndex, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let message = try? context.fetch(descriptor).first else { return nil }
        if message.isSystemMessage {
            return message.body
        }
        if message.isMediaPlaceholder {
            return "Media omitted"
        }
        if let fileName = message.mediaFileName {
            return fileName
        }
        if let sender = message.senderName {
            return "\(sender): \(message.body)"
        }
        return message.body
    }
}
