import Foundation

public struct WhatsAppChatParser {
    public init() {}
    
    public func parse(text: String) -> ParsedChat {
        var messages: [ParsedMessage] = []
        var participants = Set<String>()
        var warnings: [ParserWarning] = []
        
        let lines = text.components(separatedBy: .newlines)
        
        // Regex to match the start of a message
        // Group 1: Date (e.g., 12/05/24)
        // Group 2: Time (e.g., 9:42 PM or 21:42)
        // Group 3: Rest of the message (Sender: Message or System Message)
        let pattern = #"^(\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}),?\s+(\d{1,2}:\d{2}(?:\s?[aApP][mM])?)\s?-\s(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ParsedChat(messages: [], participants: [], warnings: [])
        }
        
        var currentTimestamp: Date? = nil
        var currentSender: String? = nil
        var currentBody: String = ""
        var currentIsSystem: Bool = false
        var currentRawText: String = ""
        
        func commitCurrentMessage() {
            if !currentRawText.isEmpty {
                let isMedia = currentBody.contains("<Media omitted>")
                let msg = ParsedMessage(
                    timestamp: currentTimestamp,
                    senderName: currentSender,
                    body: currentBody,
                    isSystemMessage: currentIsSystem,
                    isMediaPlaceholder: isMedia,
                    rawText: currentRawText
                )
                messages.append(msg)
                if let sender = currentSender {
                    participants.insert(sender)
                }
            }
        }
        
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty && currentRawText.isEmpty {
                continue // Skip leading empty lines
            }
            
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: nsRange) {
                commitCurrentMessage() // commit previous
                
                let dateRange = Range(match.range(at: 1), in: line)!
                let timeRange = Range(match.range(at: 2), in: line)!
                let restRange = Range(match.range(at: 3), in: line)!
                
                let dateStr = String(line[dateRange])
                let timeStr = String(line[timeRange])
                let restStr = String(line[restRange])
                
                currentTimestamp = Self.parseDate(dateString: dateStr, timeString: timeStr)
                
                // Parse Sender vs System Message
                // Check if there is a colon and that it's followed by a space, which is the standard "Sender: " format
                if let colonRange = restStr.range(of: ": ") {
                    let sender = String(restStr[..<colonRange.lowerBound])
                    let body = String(restStr[colonRange.upperBound...])
                    
                    currentSender = sender
                    currentBody = body
                    currentIsSystem = false
                } else {
                    currentSender = nil
                    currentBody = restStr
                    currentIsSystem = true
                }
                
                currentRawText = line
                
            } else {
                // Continuation line or unparseable line
                if currentRawText.isEmpty {
                    // This means the very first line didn't match the regex.
                    warnings.append(.unparseableLine(line, index))
                } else {
                    currentBody += "\n" + line
                    currentRawText += "\n" + line
                }
            }
        }
        
        commitCurrentMessage() // commit last
        
        return ParsedChat(messages: messages, participants: Array(participants).sorted(), warnings: warnings)
    }
    
    private static func parseDate(dateString: String, timeString: String) -> Date? {
        // Handle varying date separators (replace with slash for easier parsing)
        let normalizedDateStr = dateString.replacingOccurrences(of: "-", with: "/").replacingOccurrences(of: ".", with: "/")
        let normalizedFullString = "\(normalizedDateStr) \(timeString)"
        
        let formats = [
            "MM/dd/yy h:mm a",
            "dd/MM/yy h:mm a",
            "MM/dd/yyyy h:mm a",
            "dd/MM/yyyy h:mm a",
            "MM/dd/yy HH:mm",
            "dd/MM/yy HH:mm",
            "MM/dd/yyyy HH:mm",
            "dd/MM/yyyy HH:mm"
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
