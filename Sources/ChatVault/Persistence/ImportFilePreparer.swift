import Foundation

enum ImportFilePreparer {
    /// Copies user-selected files into a temporary directory while security-scoped access is active.
    static func copyToTemporaryDirectory(urls: [URL]) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatvault-pick-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try urls.map { source in
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
    }

    static func removeTemporaryDirectory(containing url: URL) {
        let parent = url.deletingLastPathComponent()
        guard parent.lastPathComponent.hasPrefix("chatvault-pick-") else { return }
        try? FileManager.default.removeItem(at: parent)
    }

    static func removeTemporaryDirectories(for urls: [URL]) {
        let parents = Set(urls.map { $0.deletingLastPathComponent().path })
        for path in parents where URL(fileURLWithPath: path).lastPathComponent.hasPrefix("chatvault-pick-") {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
