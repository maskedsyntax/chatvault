import XCTest
@testable import ChatVault

final class WhatsAppChatParserTests: XCTestCase {
    
    var parser: WhatsAppChatParser!
    
    override func setUp() {
        super.setUp()
        parser = WhatsAppChatParser()
    }
    
    override func tearDown() {
        parser = nil
        super.tearDown()
    }
    
    func testParseBasic12HourFormat() {
        let text = """
        12/05/24, 9:42 PM - Aftaab: Hey, are you free?
        12/05/24, 9:43 PM - Akanksha: Yes
        """
        
        let chat = parser.parse(text: text)
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.participants.count, 2)
        XCTAssertTrue(chat.participants.contains("Aftaab"))
        XCTAssertTrue(chat.participants.contains("Akanksha"))
        
        XCTAssertEqual(chat.messages[0].senderName, "Aftaab")
        XCTAssertEqual(chat.messages[0].body, "Hey, are you free?")
        XCTAssertFalse(chat.messages[0].isSystemMessage)
        
        XCTAssertEqual(chat.messages[1].senderName, "Akanksha")
        XCTAssertEqual(chat.messages[1].body, "Yes")
    }
    
    func testParseBasic24HourFormat() {
        let text = """
        12/05/2024, 21:42 - Aftaab: Hey
        """
        
        let chat = parser.parse(text: text)
        
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(chat.messages[0].senderName, "Aftaab")
        XCTAssertEqual(chat.messages[0].body, "Hey")
        XCTAssertNotNil(chat.messages[0].timestamp)
    }
    
    func testParseSystemMessage() {
        let text = """
        12/05/24, 9:44 PM - Messages and calls are end-to-end encrypted.
        """
        
        let chat = parser.parse(text: text)
        
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertNil(chat.messages[0].senderName)
        XCTAssertEqual(chat.messages[0].body, "Messages and calls are end-to-end encrypted.")
        XCTAssertTrue(chat.messages[0].isSystemMessage)
    }
    
    func testParseMultiLineMessage() {
        let text = """
        12/05/24, 9:42 PM - Aftaab: This is a long message
        that continues on another line
        and another line.
        12/05/24, 9:43 PM - Akanksha: Yes
        """
        
        let chat = parser.parse(text: text)
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[0].senderName, "Aftaab")
        XCTAssertEqual(chat.messages[0].body, "This is a long message\nthat continues on another line\nand another line.")
        
        XCTAssertEqual(chat.messages[1].senderName, "Akanksha")
        XCTAssertEqual(chat.messages[1].body, "Yes")
    }
    
    func testParseMediaOmitted() {
        let text = """
        12/05/24, 9:42 PM - Aftaab: <Media omitted>
        """
        
        let chat = parser.parse(text: text)
        
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertTrue(chat.messages[0].isMediaPlaceholder)
        XCTAssertEqual(chat.messages[0].body, "<Media omitted>")
    }
    
    func testUnparseableLineWarning() {
        let text = """
        Some random header text that is not a message
        12/05/24, 9:42 PM - Aftaab: Hey
        """
        
        let chat = parser.parse(text: text)
        
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(chat.warnings.count, 1)
        XCTAssertEqual(chat.warnings[0], .unparseableLine("Some random header text that is not a message", 0))
    }
    
    func testSenderWithColonInMessage() {
        let text = """
        12/05/24, 9:42 PM - Aftaab: Here is a URL: https://apple.com
        """
        let chat = parser.parse(text: text)
        
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(chat.messages[0].senderName, "Aftaab")
        XCTAssertEqual(chat.messages[0].body, "Here is a URL: https://apple.com")
    }
}
