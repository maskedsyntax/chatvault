import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ArchiveListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.chatStore) private var chatStore

    @Query(sort: \ChatArchive.importedAt, order: .reverse) private var archives: [ChatArchive]
    @Binding var selectedArchive: ChatArchive?

    @State private var isImporting = false
    @State private var importError: Error?
    @State private var showError = false
    @State private var isDropTargeted = false

    @State private var showImportSheet = false
    @State private var currentImport: ChatStore.ParsedImport?
    @State private var importQueue: [ChatStore.ParsedImport] = []
    @State private var importMode: ImportPreviewMode = .newImport
    @State private var pendingDuplicate: ChatArchive?

    @State private var archiveToRename: ChatArchive?
    @State private var newArchiveTitle: String = ""

    @State private var archiveToDelete: ChatArchive?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if archives.isEmpty {
                EmptyArchivesView { isImporting = true }
            } else {
                List(selection: $selectedArchive) {
                    ForEach(archives) { archive in
                        NavigationLink(value: archive) {
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
        .sheet(isPresented: $showImportSheet, onDismiss: cancelImportSession) {
            if let currentImport {
                ImportPreviewView(
                    parsedImport: currentImport,
                    mode: importMode,
                    possibleDuplicate: pendingDuplicate
                ) { archive in
                    handleImportComplete(archive)
                }
                .id(currentImport.id)
            }
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
        guard let chatStore else { return }

        Task {
            let result = await chatStore.parseImports(from: urls)

            if result.imports.isEmpty {
                importError = result.errors.first?.1 ?? ChatStore.ImportError.fileUnreadable
                showError = true
                return
            }

            if !result.errors.isEmpty {
                importError = result.errors.first?.1
                showError = true
            }

            beginImportSession(with: result.imports)
        }
    }

    private func beginImportSession(with imports: [ChatStore.ParsedImport]) {
        guard let first = imports.first else { return }

        importQueue = Array(imports.dropFirst())
        currentImport = first
        pendingDuplicate = chatStore?.findPossibleDuplicate(
            sourceFileName: first.sourceFileName,
            messageCount: first.parsed.messages.count
        )
        importMode = importQueue.isEmpty ? .newImport : .batch(remaining: importQueue.count)
        showImportSheet = true
    }

    private func handleImportComplete(_ archive: ChatArchive) {
        selectedArchive = archive
        currentImport?.cleanupTemporaryFiles()

        if importQueue.isEmpty {
            showImportSheet = false
            currentImport = nil
            pendingDuplicate = nil
            importMode = .newImport
            return
        }

        let next = importQueue.removeFirst()
        currentImport = next
        pendingDuplicate = chatStore?.findPossibleDuplicate(
            sourceFileName: next.sourceFileName,
            messageCount: next.parsed.messages.count
        )
        importMode = importQueue.isEmpty ? .newImport : .batch(remaining: importQueue.count)
    }

    private func cancelImportSession() {
        currentImport?.cleanupTemporaryFiles()
        for item in importQueue {
            item.cleanupTemporaryFiles()
        }
        currentImport = nil
        importQueue = []
        pendingDuplicate = nil
        importMode = .newImport
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
        archiveToDelete = archives[index]
        showDeleteConfirmation = true
    }

    private func deleteArchive(_ archive: ChatArchive) {
        if selectedArchive?.id == archive.id {
            selectedArchive = nil
        }
        chatStore?.deleteArchiveFiles(for: archive)
        modelContext.delete(archive)
        try? modelContext.save()
    }
}
