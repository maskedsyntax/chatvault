import Foundation
import SwiftData

enum ModelContainerFactory {
    static func make() throws -> ModelContainer {
        let schema = Schema([ChatArchive.self, ChatMessage.self])
        let storeURL = try resolveStoreURL()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            try backupAndRemoveStore(at: storeURL)
            return try ModelContainer(for: schema, configurations: configuration)
        }
    }

    private static func resolveStoreURL() throws -> URL {
        let directory = try storeDirectory()
        let primaryURL = directory.appendingPathComponent("chatvault.store")

        if FileManager.default.fileExists(atPath: primaryURL.path) {
            return primaryURL
        }

        let legacyURL = try legacyStoreURL()
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        return primaryURL
    }

    private static func storeDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("ChatVault", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func legacyStoreURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("default.store")
    }

    private static func backupAndRemoveStore(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupBase = storeURL.deletingPathExtension().lastPathComponent + "-backup-\(timestamp)"

        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = storeURL.deletingLastPathComponent().appendingPathComponent(backupBase + suffix)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: source, to: destination)
        }
    }
}
