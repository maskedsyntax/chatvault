import SwiftUI
import SwiftData

struct ArchiveRowView: View {
    let archive: ChatArchive
    let lastMessagePreview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(archive.title)
                .font(.headline)
                .lineLimit(1)

            if let preview = lastMessagePreview, !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 4) {
                Text(subtitleLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("Imported \(archive.importedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var subtitleLine: String {
        var parts = ["\(archive.messageCount) messages"]
        if let lastDate = archive.lastMessageDate {
            parts.append("last active \(lastDate.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}
