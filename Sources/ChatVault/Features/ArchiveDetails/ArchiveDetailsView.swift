import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ArchiveDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.chatStore) private var chatStore

    let archive: ChatArchive
    @Binding var selectedArchive: ChatArchive?

    @State private var showRenameAlert = false
    @State private var renameTitle: String = ""
    @State private var showDeleteConfirmation = false

    @State private var isReimporting = false
    @State private var showReimportSheet = false
    @State private var reimportPreview: ChatStore.ParsedImport?
    @State private var reimportError: Error?
    @State private var showReimportError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Archive") {
                    LabeledContent("Title", value: archive.title)
                    LabeledContent("Source File", value: archive.sourceFileName)
                    LabeledContent("Imported", value: archive.importedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Messages", value: "\(archive.messageCount)")
                    if archive.mediaFileCount > 0 {
                        LabeledContent("Media Files", value: "\(archive.mediaFileCount)")
                    }
                }

                Section("Date Range") {
                    LabeledContent("First Message", value: formattedFirstDate)
                    LabeledContent("Last Message", value: formattedLastDate)
                }

                if !archive.participantRecords.isEmpty {
                    Section {
                        ForEach(archive.participantRecords.sorted(by: { $0.resolvedName < $1.resolvedName }), id: \.id) { participant in
                            ParticipantDetailRow(participant: participant, archive: archive) {
                                try? modelContext.save()
                                archive.updatedAt = Date()
                            }
                        }

                        Button("Scan Chat for Birthdays") {
                            try? chatStore?.rescanBirthdays(for: archive)
                        }
                    } header: {
                        Text("People")
                    } footer: {
                        Text("Display names appear in the chat viewer. Birthdays are detected from messages mentioning dates.")
                            .font(.caption)
                    }
                } else if !archive.participants.isEmpty {
                    Section {
                        ForEach(archive.participants, id: \.self) { participant in
                            Text(participant)
                        }
                    } header: {
                        Text("Participants (\(archive.participants.count))")
                    }
                }

                Section {
                    Label("Stored locally on this device.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Re-import from File") {
                        isReimporting = true
                    }
                    Button("Rename Archive") {
                        renameTitle = archive.title
                        showRenameAlert = true
                    }
                    Button("Delete Archive", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Archive Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isReimporting,
                allowedContentTypes: [.plainText, .zip],
                allowsMultipleSelection: false
            ) { result in
                handleReimportSelection(result: result)
            }
            .sheet(isPresented: $showReimportSheet, onDismiss: cancelReimport) {
                if let preview = reimportPreview {
                    ImportPreviewView(
                        parsedImport: preview,
                        mode: .reimport(archive),
                        possibleDuplicate: nil
                    ) { _ in
                        preview.cleanupTemporaryFiles()
                        showReimportSheet = false
                        reimportPreview = nil
                    }
                }
            }
            .alert("Re-import Error", isPresented: $showReimportError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let reimportError {
                    Text(reimportError.localizedDescription)
                }
            }
            .alert("Rename Archive", isPresented: $showRenameAlert) {
                TextField("New Title", text: $renameTitle)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let trimmed = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    archive.title = trimmed
                    archive.updatedAt = Date()
                    try? modelContext.save()
                }
                .disabled(renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .confirmationDialog(
                "Delete Archive?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if selectedArchive?.id == archive.id {
                        selectedArchive = nil
                    }
                    chatStore?.deleteArchiveFiles(for: archive)
                    try? chatStore?.deleteSearchIndex(for: archive)
                    modelContext.delete(archive)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\"\(archive.title)\" and all \(archive.messageCount) messages will be permanently deleted.")
            }
            .task {
                try? chatStore?.ensureParticipantRecords(for: archive)
            }
        }
        .frame(minWidth: 400, minHeight: 480)
    }

    private var formattedFirstDate: String {
        if let date = chatStore?.firstMessageDate(for: archive) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return "Unknown"
    }

    private var formattedLastDate: String {
        if let date = archive.lastMessageDate {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return "Unknown"
    }

    private func handleReimportSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            startReimport(from: url)
        case .failure(let error):
            reimportError = error
            showReimportError = true
        }
    }

    private func startReimport(from url: URL) {
        guard let chatStore else { return }
        let ext = url.pathExtension.lowercased()
        guard ext == "txt" || ext == "zip" else {
            reimportError = ChatStore.ImportError.fileUnreadable
            showReimportError = true
            return
        }

        Task {
            do {
                let parsed = try await chatStore.parseImport(from: url)
                reimportPreview = parsed
                showReimportSheet = true
            } catch {
                reimportError = error
                showReimportError = true
            }
        }
    }

    private func cancelReimport() {
        reimportPreview?.cleanupTemporaryFiles()
        reimportPreview = nil
    }
}

private struct ParticipantDetailRow: View {
    @Bindable var participant: ChatParticipant
    let archive: ChatArchive
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Display name", text: $participant.displayName)
                .onSubmit { onSave() }

            Toggle("This is me", isOn: $participant.isMe)
                .onChange(of: participant.isMe) { _, isMe in
                    if isMe {
                        for other in archive.participantRecords where other.id != participant.id {
                            other.isMe = false
                        }
                    }
                    onSave()
                }

            Text("Export name: \(participant.exportName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let birthday = participant.formattedBirthday {
                Label(birthday, systemImage: "birthday.cake")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = participant.birthdayNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
