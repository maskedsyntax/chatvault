import Foundation
import SwiftData

@Model
public final class ChatParticipant {
    @Attribute(.unique) public var id: UUID
    public var exportName: String
    public var displayName: String
    public var isMe: Bool = false
    public var birthdayMonth: Int?
    public var birthdayDay: Int?
    public var birthdayNote: String?

    public var chatArchive: ChatArchive?

    public init(
        id: UUID = UUID(),
        exportName: String,
        displayName: String? = nil,
        isMe: Bool = false,
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        birthdayNote: String? = nil
    ) {
        self.id = id
        self.exportName = exportName
        self.displayName = displayName ?? exportName
        self.isMe = isMe
        self.birthdayMonth = birthdayMonth
        self.birthdayDay = birthdayDay
        self.birthdayNote = birthdayNote
    }

    public var resolvedName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? exportName : trimmed
    }

    public var hasBirthday: Bool {
        birthdayMonth != nil && birthdayDay != nil
    }

    public func birthdayMatchesToday(calendar: Calendar = .current) -> Bool {
        guard let month = birthdayMonth, let day = birthdayDay else { return false }
        let today = calendar.dateComponents([.month, .day], from: Date())
        return today.month == month && today.day == day
    }

    public var formattedBirthday: String? {
        guard let month = birthdayMonth, let day = birthdayDay else { return nil }
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = 2000
        guard let date = Calendar.current.date(from: components) else { return nil }
        return date.formatted(.dateTime.month(.wide).day())
    }
}

public struct ImportParticipantDraft: Identifiable, Equatable {
    public let id: String
    public let exportName: String
    public var displayName: String
    public var isMe: Bool
    public var birthdayMonth: Int?
    public var birthdayDay: Int?
    public var birthdayNote: String?

    public init(
        exportName: String,
        displayName: String? = nil,
        isMe: Bool = false,
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        birthdayNote: String? = nil
    ) {
        self.id = exportName
        self.exportName = exportName
        self.displayName = displayName ?? exportName
        self.isMe = isMe
        self.birthdayMonth = birthdayMonth
        self.birthdayDay = birthdayDay
        self.birthdayNote = birthdayNote
    }
}

public struct ImportConfiguration: Equatable {
    public let title: String
    public let participants: [ImportParticipantDraft]

    public init(title: String, participants: [ImportParticipantDraft]) {
        self.title = title
        self.participants = participants
    }
}

public struct BirthdayReminder: Identifiable, Equatable {
    public let id: String
    public let personName: String
    public let archiveID: UUID
    public let archiveTitle: String
    public let birthdayNote: String?

    public init(
        personName: String,
        archiveID: UUID,
        archiveTitle: String,
        birthdayNote: String?
    ) {
        self.id = "\(archiveID.uuidString)-\(personName)"
        self.personName = personName
        self.archiveID = archiveID
        self.archiveTitle = archiveTitle
        self.birthdayNote = birthdayNote
    }
}
