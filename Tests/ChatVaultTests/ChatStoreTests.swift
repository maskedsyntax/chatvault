import XCTest
import SwiftData
@testable import ChatVault

@MainActor
final class ChatStoreTests: XCTestCase {
    private func makeStore() throws -> (ChatStore, ModelContainer) {
        let container = try ModelContainer(
            for: ChatArchive.self, ChatMessage.self, ChatParticipant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = ChatStore(modelContext: container.mainContext)
        return (store, container)
    }

    func testParseSampleChat() async throws {
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SampleChat.txt")

        let (store, _) = try makeStore()
        let result = try await store.parseChat(from: sampleURL)

        XCTAssertEqual(result.parsed.messages.count, 8)
        XCTAssertEqual(result.parsed.participants.count, 2)
        XCTAssertEqual(result.encodingName, "UTF-8")
    }

    func testSaveAndLoadArchive() throws {
        let (store, container) = try makeStore()
        let text = """
        12/05/24, 9:42 PM - Aftaab: Hello
        12/05/24, 9:43 PM - Akanksha: Hi
        """
        let parsed = WhatsAppChatParser().parse(text: text)
        let archive = try store.saveArchive(
            parsed: parsed,
            title: "Test Chat",
            sourceFileName: "test.txt"
        )

        XCTAssertEqual(archive.messageCount, 2)
        XCTAssertEqual(archive.title, "Test Chat")

        let descriptor = FetchDescriptor<ChatMessage>()
        let messages = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(messages.count, 2)
    }

    func testRejectEmptyTitle() throws {
        let (store, _) = try makeStore()
        let parsed = WhatsAppChatParser().parse(text: "12/05/24, 9:42 PM - A: Hi")

        XCTAssertThrowsError(try store.saveArchive(parsed: parsed, title: "   ", sourceFileName: "a.txt")) { error in
            XCTAssertEqual(error as? ChatStore.ImportError, .invalidTitle)
        }
    }

    func testDetectDuplicateArchive() throws {
        let (store, container) = try makeStore()
        let parsed = WhatsAppChatParser().parse(text: "12/05/24, 9:42 PM - A: Hi")

        _ = try store.saveArchive(parsed: parsed, title: "First", sourceFileName: "chat.txt")
        let archives = try container.mainContext.fetch(FetchDescriptor<ChatArchive>())
        let duplicate = archives.first { $0.sourceFileName == "chat.txt" && $0.messageCount == 1 }

        XCTAssertNotNil(duplicate)
        XCTAssertEqual(duplicate?.title, "First")
    }

    func testReimportArchiveReplacesMessages() throws {
        let (store, container) = try makeStore()
        let initial = WhatsAppChatParser().parse(text: "12/05/24, 9:42 PM - A: Hello")
        let archive = try store.saveArchive(parsed: initial, title: "Chat", sourceFileName: "old.txt")

        let updated = WhatsAppChatParser().parse(text: """
        12/05/24, 9:42 PM - A: Hello
        12/05/24, 9:43 PM - B: New message
        """)
        let importValue = ChatStore.ParsedImport(
            parsed: updated,
            suggestedTitle: "Chat",
            sourceFileName: "new.txt",
            encodingName: "UTF-8",
            extractedBundleURL: nil,
            mediaFileCount: 0
        )
        let configuration = ImportConfiguration(
            title: "Chat",
            participants: importValue.importSetup.participantDrafts
        )

        let reimported = try store.reimportArchive(archive, from: importValue, configuration: configuration)

        XCTAssertEqual(reimported.id, archive.id)
        XCTAssertEqual(reimported.messageCount, 2)
        XCTAssertEqual(reimported.sourceFileName, "new.txt")

        let messages = try container.mainContext.fetch(FetchDescriptor<ChatMessage>())
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last?.body, "New message")
    }

    func testEmptyFileThrows() async throws {
        let (store, _) = try makeStore()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).txt")
        try Data().write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await store.parseChat(from: tempURL)
            XCTFail("Expected empty file error")
        } catch ChatStore.ImportError.emptyFile {
            // expected
        }
    }

    func testNoMessagesThrows() async throws {
        let (store, _) = try makeStore()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("junk-\(UUID().uuidString).txt")
        try "Not a whatsapp export".data(using: .utf8)!.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await store.parseChat(from: tempURL)
            XCTFail("Expected no messages error")
        } catch ChatStore.ImportError.noMessagesFound {
            // expected
        }
    }

    func testParseZipSampleExports() async throws {
        let (store, _) = try makeStore()
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/sample-exports")

        let zips = [
            "WhatsApp Chat with Sarah.zip",
            "WhatsApp Chat with Weekend Hikers.zip",
            "WhatsApp Chat with David Chen.zip",
        ]

        for name in zips {
            let url = base.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw XCTSkip("Sample ZIP not found at \(url.path)")
            }
            let parsed = try await store.parseImport(from: url)
            XCTAssertGreaterThan(parsed.parsed.messages.count, 0)
            XCTAssertGreaterThan(parsed.mediaFileCount, 0)
        }
    }
}
