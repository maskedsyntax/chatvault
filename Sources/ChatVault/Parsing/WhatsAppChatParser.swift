import Foundation

public struct WhatsAppChatParser {
    public init() {}

    public func parse(text: String) -> ParsedChat {
        var messages: [ParsedMessage] = []
        var participants = Set<String>()
        var warnings: [ParserWarning] = []

        let normalizedText = Self.normalizeInput(text)
        let lines = normalizedText.components(separatedBy: .newlines)

        let patterns = [
            // Android / legacy: 12/05/24, 9:42 PM - Sender: message
            #"^(\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}),?\s+(\d{1,2}:\d{2}(?::\d{2})?(?:\s?[aApP][mM])?)\s?-\s(.*)$"#,
            // iOS / Android bracket: [16/03/2024, 09:14:22] or [1/15/24, 3:45:30 PM]
            #"^\[(\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}),\s*(\d{1,2}:\d{2}(?::\d{2})?(?:\s?[aApP][mM])?)\]\s(.*)$"#,
        ]
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }

        var currentTimestamp: Date?
        var currentSender: String?
        var currentBody = ""
        var currentIsSystem = false
        var currentRawText = ""

        func commitCurrentMessage() {
            guard !currentRawText.isEmpty else { return }
            let mediaInfo = Self.parseMedia(from: currentBody)
            let isDeleted = Self.isDeletedMessage(body: mediaInfo.displayBody)
            let message = ParsedMessage(
                timestamp: currentTimestamp,
                senderName: currentSender,
                body: mediaInfo.displayBody,
                isSystemMessage: currentIsSystem,
                isMediaPlaceholder: mediaInfo.isPlaceholder,
                isDeletedMessage: isDeleted,
                mediaFileName: mediaInfo.fileName,
                mediaType: mediaInfo.mediaType,
                rawText: currentRawText
            )
            messages.append(message)
            if let sender = currentSender {
                participants.insert(sender)
            }
        }

        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty && currentRawText.isEmpty {
                continue
            }

            if let match = matchLine(line, using: regexes) {
                commitCurrentMessage()

                currentTimestamp = Self.parseDate(dateString: match.date, timeString: match.time)
                if let colonRange = match.rest.range(of: ": ") {
                    currentSender = String(match.rest[..<colonRange.lowerBound])
                    currentBody = String(match.rest[colonRange.upperBound...])
                    currentIsSystem = false
                } else {
                    currentSender = nil
                    currentBody = match.rest
                    currentIsSystem = true
                }
                currentRawText = line
            } else if currentRawText.isEmpty {
                warnings.append(.unparseableLine(line, index))
            } else {
                currentBody += "\n" + line
                currentRawText += "\n" + line
            }
        }

        commitCurrentMessage()

        return ParsedChat(messages: messages, participants: Array(participants).sorted(), warnings: warnings)
    }

    private struct LineMatch {
        let date: String
        let time: String
        let rest: String
    }

    private func matchLine(_ line: String, using regexes: [NSRegularExpression]) -> LineMatch? {
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        for regex in regexes {
            guard let match = regex.firstMatch(in: line, options: [], range: nsRange),
                  match.numberOfRanges == 4,
                  let dateRange = Range(match.range(at: 1), in: line),
                  let timeRange = Range(match.range(at: 2), in: line),
                  let restRange = Range(match.range(at: 3), in: line) else {
                continue
            }
            return LineMatch(
                date: String(line[dateRange]),
                time: String(line[timeRange]),
                rest: String(line[restRange])
            )
        }
        return nil
    }

    private struct MediaInfo {
        let displayBody: String
        let fileName: String?
        let mediaType: MediaType?
        let isPlaceholder: Bool
    }

    private static let attachedFilePattern = """
    ^(.+?)\\s+\\((?:file attached|attached file|archivo adjunto|fichier joint|\
    datei angehängt|datei angehangt|arquivo anexado|allegato|\
    plik dołączony|plik dolaczony|файл в приложении)\\)$
    """

    private static let deletedMessagePhrases = [
        "this message was deleted",
        "you deleted this message",
        "this message was deleted by admin",
        "<this message was deleted>",
        "du hast diese nachricht gelöscht",
        "diese nachricht wurde gelöscht",
        "elimaste este mensaje",
        "se eliminó este mensaje",
        "este mensaje fue eliminado",
        "vous avez supprimé ce message",
        "ce message a été supprimé",
        "você apagou esta mensagem",
        "esta mensagem foi apagada",
        "eliminasti questo messaggio",
        "questo messaggio è stato eliminato",
        "wiadomość została usunięta",
        "usunąłeś tę wiadomość",
    ]

    static func normalizeInput(_ text: String) -> String {
        var normalized = text
        if normalized.hasPrefix("\u{FEFF}") {
            normalized.removeFirst()
        }
        normalized = normalized.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")
        return normalized
    }

    static func isDeletedMessage(body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if deletedMessagePhrases.contains(where: { lowered == $0 || lowered.contains($0) }) {
            return true
        }
        return lowered.hasPrefix("<") && lowered.hasSuffix(">") && lowered.contains("deleted")
    }

    private static func parseMedia(from body: String) -> MediaInfo {
        if body.contains("<Media omitted>") {
            return MediaInfo(displayBody: body, fileName: nil, mediaType: nil, isPlaceholder: true)
        }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: attachedFilePattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
           let fileRange = Range(match.range(at: 1), in: trimmed) {
            let fileName = String(trimmed[fileRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let mediaType = MediaType.infer(from: fileName)
            return MediaInfo(displayBody: fileName, fileName: fileName, mediaType: mediaType, isPlaceholder: false)
        }

        let knownPrefixPattern = #"^((?:IMG|VID|PTT|STK|AUD|DOC)-[\w\-. ]+\.(?:jpg|jpeg|png|webp|gif|mp4|mov|opus|m4a|mp3|pdf|docx?|xlsx?|pptx?))$"#
        if let regex = try? NSRegularExpression(pattern: knownPrefixPattern, options: [.caseInsensitive]),
           regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)) != nil {
            let mediaType = MediaType.infer(from: trimmed)
            return MediaInfo(displayBody: trimmed, fileName: trimmed, mediaType: mediaType, isPlaceholder: false)
        }

        return MediaInfo(displayBody: body, fileName: nil, mediaType: nil, isPlaceholder: false)
    }

    private static func parseDate(dateString: String, timeString: String) -> Date? {
        let normalizedDateStr = dateString
            .replacingOccurrences(of: "-", with: "/")
            .replacingOccurrences(of: ".", with: "/")
        let normalizedTime = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFullString = "\(normalizedDateStr) \(normalizedTime)"

        let formats = [
            "MM/dd/yy h:mm a",
            "dd/MM/yy h:mm a",
            "MM/dd/yyyy h:mm a",
            "dd/MM/yyyy h:mm a",
            "d/M/yy h:mm a",
            "d/M/yyyy h:mm a",
            "M/d/yy h:mm a",
            "M/d/yyyy h:mm a",
            "MM/dd/yy HH:mm",
            "dd/MM/yy HH:mm",
            "MM/dd/yyyy HH:mm",
            "dd/MM/yyyy HH:mm",
            "MM/dd/yyyy HH:mm:ss",
            "dd/MM/yyyy HH:mm:ss",
            "MM/dd/yy HH:mm:ss",
            "dd/MM/yy HH:mm:ss",
            "d/M/yyyy HH:mm:ss",
            "M/d/yyyy HH:mm:ss",
            "d/M/yyyy h:mm:ss a",
            "M/d/yyyy h:mm:ss a",
            "MM/dd/yyyy h:mm:ss a",
            "dd/MM/yyyy h:mm:ss a",
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalizedFullString) {
                return date
            }
        }

        return nil
    }
}
