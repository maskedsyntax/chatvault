import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ArchiveListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.chatStore) private var chatStore

    @Query(sort: \ChatArchive.importedAt, order: .reverse) private var archives: [ChatArchive]
    @Binding var selectedArchiveID: UUID?

    @State private var isImporting = false
    @State private var importError: Error?
    @State private var showError = false
    @State private var isDropTargeted = false

    @State private var currentImport: ChatStore.ParsedImport?
    @State private var importURLQueue: [URL] = []
    @State private var importSessionURLs: [URL] = []
    @State private var importMode: ImportPreviewMode = .newImport
    @State private var pendingDuplicate: ChatArchive?
    @State private var shouldCleanupImportOnSheetDismiss = true
    @State private var isParsingImports = false
    @State private var parsingLabel = "Reading files…"

    @State private var archiveToRename: ChatArchive?
    @State private var newArchiveTitle: String = ""

    @State private var archiveToDelete: ChatArchive?
    @State private var showDeleteConfirmation = false
    @State private var pendingDeletionIDs = Set<UUID>()

    private var visibleArchives: [ChatArchive] {
        archives.filter { !pendingDeletionIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if visibleArchives.isEmpty {
                EmptyArchivesView { isImporting = true }
            } else {
                List(selection: $selectedArchiveID) {
                    ForEach(visibleArchives) { archive in
                        NavigationLink(value: archive.id) {
                            ArchiveRowView(
                                archive: archive,
                                lastMessagePreview: archive.lastMessagePreview(in: modelContext)
                            )
                        }
                        .contextMenu {
                            Button("Rename") {
                                archiveToRename = archive
                                newArchiveTitle = archive.title
                            }
                            Button("Delete", role: .destructive) {
                                archiveToDelete = archive
                                showDeleteConfirmation = true
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                archiveToDelete = archive
                                showDeleteConfirmation = true
                            }
                        }
                    }
                    .onDelete(perform: requestDeleteAtOffsets)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isImporting = true } label: {
                    Label("Import Chat", systemImage: "plus")
                }
            }

            if selectedArchiveID != nil {
                ToolbarItem(placement: .automatic) {
                    Button(role: .destructive) {
                        if let selectedArchiveID {
                            archiveToDelete = visibleArchives.first(where: { $0.id == selectedArchiveID })
                            showDeleteConfirmation = true
                        }
                    } label: {
                        Label("Delete Chat", systemImage: "trash")
                    }
                    .help("Delete the selected chat")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.plainText, .zip],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result: result)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isParsingImports {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(parsingLabel)
                            .font(.headline)
                        Text("This usually takes a few seconds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .sheet(item: $currentImport, onDismiss: handleImportSheetDismiss) { item in
            ImportPreviewView(
                parsedImport: item,
                mode: importMode,
                possibleDuplicate: pendingDuplicate
            ) { archive in
                handleImportComplete(archive)
            }
            .id(item.id)
        }
        .alert("Import Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let importError {
                Text(importError.localizedDescription)
            }
        }
        .alert("Rename Archive", isPresented: renameAlertBinding) {
            TextField("New Title", text: $newArchiveTitle)
            Button("Cancel", role: .cancel) {
                archiveToRename = nil
            }
            Button("Rename") {
                renameArchive()
            }
            .disabled(newArchiveTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(
            "Delete Archive?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let archive = archiveToDelete {
                    deleteArchive(archive)
                }
                archiveToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                archiveToDelete = nil
            }
        } message: {
            if let archive = archiveToDelete {
                Text("\"\(archive.title)\" and all \(archive.messageCount) messages will be permanently deleted.")
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { archiveToRename != nil },
            set: { if !$0 { archiveToRename = nil } }
        )
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let validURLs = urls.filter { isSupportedImportURL($0) }
            guard !validURLs.isEmpty else {
                importError = ChatStore.ImportError.fileUnreadable
                showError = true
                return
            }
            importURLs(validURLs)
        case .failure(let error):
            importError = error
            showError = true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await loadDroppedURL(from: provider), isSupportedImportURL(url) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else {
                importError = ChatStore.ImportError.fileUnreadable
                showError = true
                return
            }
            importURLs(urls)
        }
        return true
    }

    private func loadDroppedURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func isSupportedImportURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "txt" || ext == "zip"
    }

    private func importURLs(_ urls: [URL]) {
        guard chatStore != nil else {
            importError = ImportBatchError.storeUnavailable
            showError = true
            return
        }

        let scopedAccess = urls.map { url -> (URL, Bool) in
            (url, url.startAccessingSecurityScopedResource())
        }

        isParsingImports = true
        parsingLabel = "Reading \(urls.count) file\(urls.count == 1 ? "" : "s")…"

        Task {
            defer {
                for (url, accessed) in scopedAccess where accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let localURLs = try ImportFilePreparer.copyToTemporaryDirectory(urls: urls)
                beginImportSession(with: localURLs)
            } catch {
                importError = error
                showError = true
                isParsingImports = false
            }
        }
    }

    private func handleImportSheetDismiss() {
        guard shouldCleanupImportOnSheetDismiss else {
            shouldCleanupImportOnSheetDismiss = true
            return
        }
        cancelImportSession()
    }

    private func beginImportSession(with urls: [URL]) {
        importSessionURLs = urls
        importURLQueue = urls
        currentImport = nil
        pendingDuplicate = nil
        importMode = urls.count <= 1 ? .newImport : .batch(remaining: max(urls.count - 1, 0))
        parseNextQueuedImport()
    }

    private func handleImportComplete(_ archive: ChatArchive) {
        currentImport?.cleanupTemporaryFiles()

        shouldCleanupImportOnSheetDismiss = false
        currentImport = nil
        pendingDuplicate = nil

        if importURLQueue.isEmpty {
            selectedArchiveID = archive.id
            shouldCleanupImportOnSheetDismiss = false
            cleanupImportSessionFiles()
            importMode = .newImport
            return
        }

        parseNextQueuedImport()
    }

    private func cancelImportSession() {
        currentImport?.cleanupTemporaryFiles()
        currentImport = nil
        importURLQueue = []
        cleanupImportSessionFiles()
        pendingDuplicate = nil
        importMode = .newImport
    }

    private func parseNextQueuedImport() {
        guard let store = chatStore else {
            importError = ImportBatchError.storeUnavailable
            showError = true
            cancelImportSession()
            return
        }
        guard currentImport == nil else { return }
        guard !importURLQueue.isEmpty else {
            cleanupImportSessionFiles()
            importMode = .newImport
            return
        }

        let url = importURLQueue.removeFirst()
        isParsingImports = true
        parsingLabel = "Reading \(url.lastPathComponent)…"

        Task {
            let result = await store.parseImports(from: [url])
            isParsingImports = false

            if let parsedImport = result.imports.first {
                currentImport = parsedImport
                pendingDuplicate = chatStore?.findPossibleDuplicate(
                    sourceFileName: parsedImport.sourceFileName,
                    messageCount: parsedImport.parsed.messages.count
                )
                importMode = importURLQueue.isEmpty ? .newImport : .batch(remaining: importURLQueue.count)
                return
            }

            if let error = result.errors.first?.1 {
                importError = error
                showError = true
            }

            if importURLQueue.isEmpty {
                cleanupImportSessionFiles()
                importMode = .newImport
            } else {
                parseNextQueuedImport()
            }
        }
    }

    private func cleanupImportSessionFiles() {
        ImportFilePreparer.removeTemporaryDirectories(for: importSessionURLs)
        importSessionURLs = []
    }

    private func renameArchive() {
        let trimmed = newArchiveTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let archive = archiveToRename, !trimmed.isEmpty else { return }
        archive.title = trimmed
        archive.updatedAt = Date()
        try? modelContext.save()
        archiveToRename = nil
    }

    private func requestDeleteAtOffsets(_ offsets: IndexSet) {
        guard let index = offsets.first else { return }
        archiveToDelete = visibleArchives[index]
        showDeleteConfirmation = true
    }

    private func deleteArchive(_ archive: ChatArchive) {
        let archiveID = archive.id
        pendingDeletionIDs.insert(archiveID)
        chatStore?.scheduleArchiveDeletion(id: archiveID) {
            if selectedArchiveID == archiveID {
                selectedArchiveID = nil
            }
        }
    }
}

private enum ImportBatchError: LocalizedError {
    case storeUnavailable
    case partialFailure(imported: Int, failed: Int, failedNames: String, underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "ChatVault is still starting up. Please try importing again in a moment."
        case .partialFailure(let imported, let failed, let failedNames, let underlying):
            var message = "Imported \(imported) file(s), but \(failed) failed (\(failedNames))."
            if let underlying {
                message += " \(underlying.localizedDescription)"
            }
            return message
        }
    }
}
