import Foundation

/// File I/O import parsing off the main actor so the UI stays responsive.
enum ZipImportParser {
    static func parseImports(from urls: [URL]) -> (imports: [ChatStore.ParsedImport], errors: [(URL, Error)]) {
        let parser = WhatsAppChatParser()
        var imports: [ChatStore.ParsedImport] = []
        var errors: [(URL, Error)] = []

        for url in urls {
            do {
                imports.append(try parseImport(from: url, parser: parser))
            } catch {
                errors.append((url, error))
            }
        }

        return (imports, errors)
    }

    private static func parseImport(from url: URL, parser: WhatsAppChatParser) throws -> ChatStore.ParsedImport {
        if url.pathExtension.lowercased() == "zip" {
            return try parseZipImport(from: url, parser: parser)
        }
        return try parseTextImport(from: url, parser: parser)
    }

    private static func parseTextImport(from url: URL, parser: WhatsAppChatParser) throws -> ChatStore.ParsedImport {
        let data = try readData(from: url)
        let (text, encodingName) = try decodeText(from: data)
        let parsedChat = try parseText(text, parser: parser)
        let setup = ChatTitleSuggester.buildImportSetup(
            fileName: url.lastPathComponent,
            parsed: parsedChat
        )

        return ChatStore.ParsedImport(
            parsed: parsedChat,
            suggestedTitle: setup.suggestedTitle,
            sourceFileName: url.lastPathComponent,
            encodingName: encodingName,
            extractedBundleURL: nil,
            mediaFileCount: 0
        )
    }

    private static func parseZipImport(from url: URL, parser: WhatsAppChatParser) throws -> ChatStore.ParsedImport {
        let tempDirectory = try ArchiveStorage.makeTemporaryImportDirectory()
        do {
            try ArchiveStorage.extractZip(from: url, to: tempDirectory)
            guard let chatFileURL = ArchiveStorage.findChatTextFile(in: tempDirectory) else {
                try? FileManager.default.removeItem(at: tempDirectory)
                throw ChatStore.ImportError.chatTextNotFoundInZip
            }

            let data = try readData(from: chatFileURL)
            let (text, encodingName) = try decodeText(from: data)
            let parsedChat = try parseText(text, parser: parser)
            let setup = ChatTitleSuggester.buildImportSetup(
                fileName: url.lastPathComponent,
                parsed: parsedChat
            )

            return ChatStore.ParsedImport(
                parsed: parsedChat,
                suggestedTitle: setup.suggestedTitle,
                sourceFileName: url.lastPathComponent,
                encodingName: encodingName,
                extractedBundleURL: tempDirectory,
                mediaFileCount: ArchiveStorage.mediaCount(in: tempDirectory)
            )
        } catch {
            try? FileManager.default.removeItem(at: tempDirectory)
            throw error
        }
    }

    private static func parseText(_ text: String, parser: WhatsAppChatParser) throws -> ParsedChat {
        let normalized = WhatsAppChatParser.normalizeInput(text)
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChatStore.ImportError.emptyFile }

        let parsedChat = parser.parse(text: normalized)
        guard !parsedChat.messages.isEmpty else { throw ChatStore.ImportError.noMessagesFound }
        return parsedChat
    }

    private static func readData(from url: URL) throws -> Data {
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw ChatStore.ImportError.emptyFile }
            return data
        } catch let error as ChatStore.ImportError {
            throw error
        } catch {
            throw ChatStore.ImportError.fileUnreadable
        }
    }

    private static func decodeText(from data: Data) throws -> (String, String) {
        var payload = data
        if payload.starts(with: [0xEF, 0xBB, 0xBF]) {
            payload.removeFirst(3)
        }

        let encodings: [(String.Encoding, String)] = [
            (.utf8, "UTF-8"),
            (.utf16, "UTF-16"),
            (.windowsCP1252, "Windows-1252"),
            (.isoLatin1, "ISO Latin-1"),
        ]

        for (encoding, name) in encodings {
            if let text = String(data: payload, encoding: encoding), !text.isEmpty {
                return (text, name)
            }
        }

        throw ChatStore.ImportError.encodingFailed
    }
}
