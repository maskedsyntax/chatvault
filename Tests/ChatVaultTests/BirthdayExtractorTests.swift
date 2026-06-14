import XCTest
@testable import ChatVault

final class BirthdayExtractorTests: XCTestCase {
    func testExtractBirthdayFromMessageBody() {
        let messages = [
            ParsedMessage(
                timestamp: nil,
                senderName: "Alice",
                body: "My birthday is March 15!",
                isSystemMessage: false,
                isMediaPlaceholder: false,
                rawText: ""
            ),
        ]

        let birthdays = BirthdayExtractor.extract(from: messages)

        XCTAssertEqual(birthdays["Alice"]?.month, 3)
        XCTAssertEqual(birthdays["Alice"]?.day, 15)
    }

    func testExtractNamedBirthday() {
        let messages = [
            ParsedMessage(
                timestamp: nil,
                senderName: "Bob",
                body: "Alice's birthday is on 7/22",
                isSystemMessage: false,
                isMediaPlaceholder: false,
                rawText: ""
            ),
        ]

        let birthdays = BirthdayExtractor.extract(from: messages, participants: ["Alice", "Bob"])

        XCTAssertEqual(birthdays["Alice"]?.month, 7)
        XCTAssertEqual(birthdays["Alice"]?.day, 22)
    }

    func testSuggestedTitleUsesContactName() {
        let parsed = ParsedChat(
            messages: [],
            participants: ["Aftaab", "Akanksha"],
            warnings: []
        )

        let setup = ChatTitleSuggester.buildImportSetup(
            fileName: "WhatsApp Chat with Akanksha.txt",
            parsed: parsed
        )

        XCTAssertEqual(setup.suggestedTitle, "Akanksha")
        XCTAssertTrue(setup.participantDrafts.first(where: { $0.exportName == "Aftaab" })?.isMe == true)
    }
}
