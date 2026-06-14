import Foundation

public struct WhatsAppChatParser {
    public init() {}

    public func parse(text: String) -> ParsedChat {
        var messages: [ParsedMessage] = []
        var participants = Set<String>()
        var warnings: [ParserWarning] = []

        let lines = text.components(separatedBy: .newlines)

        let patterns = [
            #"^(\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}),?\s+(\d{1,2}:\d{2}(?::\d{2})?(?:\s?[aApP][mM])?)\s?-\s(.*)$"#,
            #"^\[(\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}),\s*(\d{1,2}:\d{2}(?::\d{2})?)\]\s(.*)$"#,
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
            let message = ParsedMessage(
                timestamp: currentTimestamp,
                senderName: currentSender,
                body: mediaInfo.displayBody,
                isSystemMessage: currentIsSystem,
                isMediaPlaceholder: mediaInfo.isPlaceholder,
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

    private static func parseMedia(from body: String) -> MediaInfo {
        if body.contains("<Media omitted>") {
            return MediaInfo(displayBody: body, fileName: nil, mediaType: nil, isPlaceholder: true)
        }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachedPattern = #"^(.+?)\s+\((?:file attached|attached file|archivo adjunto|fichier joint)\)$"#
        if let regex = try? NSRegularExpression(pattern: attachedPattern, options: [.caseInsensitive]),
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
            "MM/dd/yy HH:mm",
            "dd/MM/yy HH:mm",
            "MM/dd/yyyy HH:mm",
            "dd/MM/yyyy HH:mm",
            "MM/dd/yyyy HH:mm:ss",
            "dd/MM/yyyy HH:mm:ss",
            "MM/dd/yy HH:mm:ss",
            "dd/MM/yy HH:mm:ss",
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
