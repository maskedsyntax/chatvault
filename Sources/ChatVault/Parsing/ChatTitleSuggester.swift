import Foundation

public enum ChatTitleSuggester {
    public struct ImportSetup {
        public let suggestedTitle: String
        public let participantDrafts: [ImportParticipantDraft]
    }

    public static func buildImportSetup(
        fileName: String,
        parsed: ParsedChat
    ) -> ImportSetup {
        let cleanedFileName = cleanWhatsAppFileName(fileName)
        let participants = parsed.participants
        let birthdays = BirthdayExtractor.extract(from: parsed.messages, participants: parsed.participants)
        let messageCounts = countMessagesBySender(parsed.messages)

        var meName: String?
        var suggestedTitle = cleanedFileName

        if participants.count == 2 {
            let contactFromFile = participants.first { participant in
                cleanedFileName.localizedCaseInsensitiveContains(participant)
            }

            if let contactFromFile {
                suggestedTitle = contactFromFile
                meName = participants.first { $0 != contactFromFile }
            } else if !cleanedFileName.isEmpty, cleanedFileName != "chat" {
                suggestedTitle = cleanedFileName
                meName = participants.first { !$0.localizedCaseInsensitiveContains(cleanedFileName) }
                    ?? participants.max(by: { messageCounts[$0, default: 0] < messageCounts[$1, default: 0] })
            } else {
                meName = participants.max(by: { messageCounts[$0, default: 0] < messageCounts[$1, default: 0] })
                suggestedTitle = participants.first { $0 != meName } ?? participants[0]
            }
        } else if participants.count > 2 {
            suggestedTitle = cleanedFileName.isEmpty ? "Group Chat" : cleanedFileName
        } else if let only = participants.first {
            suggestedTitle = only
        }

        let drafts = participants.map { name in
            let birthday = birthdays[name]
            return ImportParticipantDraft(
                exportName: name,
                displayName: name == suggestedTitle ? name : name,
                isMe: name == meName,
                birthdayMonth: birthday?.month,
                birthdayDay: birthday?.day,
                birthdayNote: birthday?.note
            )
        }

        return ImportSetup(suggestedTitle: suggestedTitle, participantDrafts: drafts)
    }

    public static func suggestedTitle(
        for drafts: [ImportParticipantDraft],
        fallback: String
    ) -> String {
        let others = drafts.filter { !$0.isMe }
        if others.count == 1 {
            return others[0].resolvedDisplayName
        }
        if others.count > 1 {
            return fallback
        }
        return fallback
    }

    private static func cleanWhatsAppFileName(_ fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        return base
            .replacingOccurrences(of: "WhatsApp Chat with ", with: "")
            .replacingOccurrences(of: "WhatsApp Chat - ", with: "")
            .replacingOccurrences(of: "_chat", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func countMessagesBySender(_ messages: [ParsedMessage]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for message in messages {
            guard let sender = message.senderName else { continue }
            counts[sender, default: 0] += 1
        }
        return counts
    }
}

private extension ImportParticipantDraft {
    var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? exportName : trimmed
    }
}
