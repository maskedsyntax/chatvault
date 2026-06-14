import Foundation
import ZIPFoundation

enum ArchiveStorage {
    private static let rootFolderName = "ChatVault/archives"

    static func rootDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport.appendingPathComponent(rootFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func permanentDirectory(for archiveID: UUID) throws -> URL {
        let directory = try rootDirectory().appendingPathComponent(archiveID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func makeTemporaryImportDirectory() throws -> URL {
        let directory = try rootDirectory().appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func extractZip(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try fileManager.unzipItem(at: sourceURL, to: destinationURL)
    }

    static func findChatTextFile(in directoryURL: URL) -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var textFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "txt" else { continue }
            textFiles.append(fileURL)
        }

        if let chatFile = textFiles.first(where: { $0.lastPathComponent.lowercased() == "_chat.txt" }) {
            return chatFile
        }
        if let chatFile = textFiles.first(where: { $0.lastPathComponent.lowercased().contains("whatsapp chat") }) {
            return chatFile
        }
        return textFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first
    }

    static func mediaFiles(in directoryURL: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() != "txt" else { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            files.append(fileURL)
        }
        return files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func mediaCount(in directoryURL: URL) -> Int {
        mediaFiles(in: directoryURL).count
    }

    static func moveTemporaryBundle(from temporaryURL: URL, to archiveID: UUID) throws -> URL {
        let destination = try permanentDirectory(for: archiveID)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    static func deleteBundle(at path: String?) {
        guard let path else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    static func resolveMediaURL(fileName: String, in storagePath: String?) -> URL? {
        guard let storagePath else { return nil }
        let baseURL = URL(fileURLWithPath: storagePath, isDirectory: true)
        let direct = baseURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }

        let targetName = (fileName as NSString).lastPathComponent
        guard let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == targetName {
                return fileURL
            }
        }
        return nil
    }
}
