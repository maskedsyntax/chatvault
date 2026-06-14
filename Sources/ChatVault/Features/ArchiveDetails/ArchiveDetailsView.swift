import SwiftUI
import SwiftData

struct ArchiveDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.chatStore) private var chatStore

    let archive: ChatArchive
    @Binding var selectedArchive: ChatArchive?

    @State private var showRenameAlert = false
    @State private var renameTitle: String = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Archive") {
                    LabeledContent("Title", value: archive.title)
                    LabeledContent("Source File", value: archive.sourceFileName)
                    LabeledContent("Imported", value: archive.importedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Messages", value: "\(archive.messageCount)")
                }

                Section("Date Range") {
                    LabeledContent("First Message", value: formattedFirstDate)
                    LabeledContent("Last Message", value: formattedLastDate)
                }

                if !archive.participants.isEmpty {
                    Section("Participants (\(archive.participants.count))") {
                        ForEach(archive.participants, id: \.self) { participant in
                            Text(participant)
                        }
                    }
                }

                Section {
                    Label("Stored locally on this device.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
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
                    modelContext.delete(archive)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\"\(archive.title)\" and all \(archive.messageCount) messages will be permanently deleted.")
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
}
