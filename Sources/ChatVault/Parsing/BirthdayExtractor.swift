import Foundation

public enum BirthdayExtractor {
    public struct BirthdayMatch: Equatable {
        public let month: Int
        public let day: Int
        public let note: String
    }

    private static let monthNames: [(String, Int)] = [
        ("january", 1), ("jan", 1),
        ("february", 2), ("feb", 2),
        ("march", 3), ("mar", 3),
        ("april", 4), ("apr", 4),
        ("may", 5),
        ("june", 6), ("jun", 6),
        ("july", 7), ("jul", 7),
        ("august", 8), ("aug", 8),
        ("september", 9), ("sep", 9), ("sept", 9),
        ("october", 10), ("oct", 10),
        ("november", 11), ("nov", 11),
        ("december", 12), ("dec", 12),
    ]

    public static func extract(from messages: [ParsedMessage], participants: [String] = []) -> [String: BirthdayMatch] {
        var results: [String: BirthdayMatch] = [:]
        let participantSet = Set(participants + messages.compactMap(\.senderName))

        for message in messages where !message.isSystemMessage && !message.isDeletedMessage {
            let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }

            let lowered = body.lowercased()
            guard lowered.contains("birthday") || lowered.contains("born on") || lowered.contains("b-day") else {
                continue
            }

            if let named = parseNamedBirthday(from: body, participants: participantSet) {
                if results[named.name] == nil {
                    results[named.name] = BirthdayMatch(month: named.month, day: named.day, note: body)
                }
            } else if let date = parseBirthday(from: body), let sender = message.senderName {
                if results[sender] == nil {
                    results[sender] = BirthdayMatch(month: date.month, day: date.day, note: body)
                }
            }
        }

        return results
    }

    private struct NamedBirthday {
        let name: String
        let month: Int
        let day: Int
    }

    private static func parseNamedBirthday(from body: String, participants: Set<String>) -> NamedBirthday? {
        guard let date = parseBirthday(from: body) else { return nil }

        for participant in participants {
            if body.localizedCaseInsensitiveContains("\(participant)'s birthday") ||
                body.localizedCaseInsensitiveContains("\(participant) birthday") ||
                body.localizedCaseInsensitiveContains("birthday of \(participant)") {
                return NamedBirthday(name: participant, month: date.month, day: date.day)
            }
        }
        return nil
    }

    private static func parseBirthday(from text: String) -> (month: Int, day: Int)? {
        let lowered = text.lowercased()

        for (name, month) in monthNames {
            let monthPattern = NSRegularExpression.escapedPattern(for: name)

            if let regex = try? NSRegularExpression(pattern: "\(monthPattern)\\s+(\\d{1,2})", options: []),
               let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
               let dayRange = Range(match.range(at: 1), in: lowered),
               let day = Int(lowered[dayRange]), (1...31).contains(day) {
                return (month, day)
            }

            if let regex = try? NSRegularExpression(pattern: "(\\d{1,2})\\s+\(monthPattern)", options: []),
               let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
               let dayRange = Range(match.range(at: 1), in: lowered),
               let day = Int(lowered[dayRange]), (1...31).contains(day) {
                return (month, day)
            }
        }

        if let regex = try? NSRegularExpression(
            pattern: #"(\d{1,2})[/.-](\d{1,2})(?:[/.-]\d{2,4})?"#,
            options: []
        ),
           let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
           let firstRange = Range(match.range(at: 1), in: lowered),
           let secondRange = Range(match.range(at: 2), in: lowered),
           let first = Int(lowered[firstRange]),
           let second = Int(lowered[secondRange]) {

            if (1...12).contains(first), (1...31).contains(second) {
                return (first, second)
            }
            if (1...12).contains(second), (1...31).contains(first) {
                return (second, first)
            }
        }

        return nil
    }
}
