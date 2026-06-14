import SwiftUI
import SwiftData

struct ArchiveListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.chatStore) private var chatStore

    @Query(sort: \ChatArchive.importedAt, order: .reverse) private var archives: [ChatArchive]
    @Binding var selectedArchive: ChatArchive?

    @State private var isImporting = false
    @State private var importError: Error?
    @State private var showError = false

    @State private var pendingImport: ChatStore.ParsedImport?
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
        .navigationTitle("Archives")
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
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .sheet(item: $pendingImport) { item in
            ImportPreviewView(
                parsedImport: item,
                possibleDuplicate: pendingDuplicate
            ) { archive in
                selectedArchive = archive
                pendingDuplicate = nil
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
            guard let url = urls.first, let chatStore else { return }
            Task {
                do {
                    let parsedImport = try await chatStore.parseChat(from: url)
                    pendingDuplicate = chatStore.findPossibleDuplicate(
                        sourceFileName: parsedImport.sourceFileName,
                        messageCount: parsedImport.parsed.messages.count
                    )
                    pendingImport = parsedImport
                } catch {
                    importError = error
                    showError = true
                }
            }
        case .failure(let error):
            importError = error
            showError = true
        }
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
        modelContext.delete(archive)
        try? modelContext.save()
    }
}

extension ChatStore.ParsedImport: Identifiable {
    public var id: String { "\(sourceFileName)-\(parsed.messages.count)-\(encodingName)" }
}
