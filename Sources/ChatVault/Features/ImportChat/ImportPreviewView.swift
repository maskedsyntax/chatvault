import SwiftUI

struct ImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.chatStore) private var chatStore

    let parsedImport: ChatStore.ParsedImport
    let possibleDuplicate: ChatArchive?
    let onImport: (ChatArchive) -> Void

    @State private var title: String
    @State private var isImporting = false
    @State private var importError: Error?
    @State private var showWarnings = false

    init(
        parsedImport: ChatStore.ParsedImport,
        possibleDuplicate: ChatArchive?,
        onImport: @escaping (ChatArchive) -> Void
    ) {
        self.parsedImport = parsedImport
        self.possibleDuplicate = possibleDuplicate
        self.onImport = onImport
        _title = State(initialValue: parsedImport.suggestedTitle)
    }

    private var parsed: ParsedChat { parsedImport.parsed }

    private var sampleMessages: [ParsedMessage] {
        parsed.messages.filter { !$0.isSystemMessage }.prefix(5).map { $0 }
    }

    private var dateRangeText: String {
        let timestamps = parsed.messages.compactMap(\.timestamp)
        guard let first = timestamps.first, let last = timestamps.last else {
            return "Unknown"
        }
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return first.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let importError {
                    Section {
                        Label(importError.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if possibleDuplicate != nil {
                    Section {
                        Label {
                            Text("This file may already be imported as \"\(possibleDuplicate!.title)\". You can import anyway to create a duplicate.")
                        } icon: {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.orange)
                        }
                    }
                    .listRowBackground(ChatVaultTheme.duplicateBanner)
                }

                if !parsed.warnings.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showWarnings) {
                            ForEach(Array(parsed.warnings.enumerated()), id: \.offset) { _, warning in
                                if case .unparseableLine(let line, let index) = warning {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Line \(index + 1)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(line)
                                            .font(.caption)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        } label: {
                            Label("\(parsed.warnings.count) parsing warning(s)", systemImage: "exclamationmark.triangle")
                        }
                    }
                    .listRowBackground(ChatVaultTheme.warningBanner)
                }

                Section("Chat Title") {
                    TextField("Title", text: $title)
                }

                Section("Summary") {
                    LabeledContent("Messages", value: "\(parsed.messages.count)")
                    LabeledContent("Participants", value: "\(parsed.participants.count)")
                    LabeledContent("Date Range", value: dateRangeText)
                    LabeledContent("Encoding", value: parsedImport.encodingName)
                    LabeledContent("Source File", value: parsedImport.sourceFileName)
                    if parsedImport.mediaFileCount > 0 {
                        LabeledContent("Media Files", value: "\(parsedImport.mediaFileCount)")
                    }
                    if parsed.attachedMediaCount > 0 {
                        LabeledContent("Linked Attachments", value: "\(parsed.attachedMediaCount)")
                    }
                }

                if parsed.messages.count >= 10_000 {
                    Section {
                        Label("Large chat — import may take a moment.", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !parsed.participants.isEmpty {
                    Section("Participants") {
                        Text(parsed.participants.joined(separator: ", "))
                            .font(.subheadline)
                    }
                }

                if !sampleMessages.isEmpty {
                    Section("Sample Messages") {
                        ForEach(sampleMessages) { message in
                            VStack(alignment: .leading, spacing: 2) {
                                if let sender = message.senderName {
                                    Text(sender)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                }
                                Text(sampleText(for: message))
                                    .font(.subheadline)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { performImport() }
                        .disabled(trimmedTitle.isEmpty || isImporting)
                }
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.2)
                        ProgressView("Importing…")
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
    }

    private func sampleText(for message: ParsedMessage) -> String {
        if message.isMediaPlaceholder { return "Media omitted" }
        if let fileName = message.mediaFileName { return fileName }
        return message.body
    }

    private func performImport() {
        guard let chatStore else { return }
        isImporting = true
        importError = nil

        Task {
            do {
                let archive = try chatStore.saveArchive(
                    from: parsedImport,
                    title: trimmedTitle
                )
                onImport(archive)
                dismiss()
            } catch {
                importError = error
                isImporting = false
            }
        }
    }
}
