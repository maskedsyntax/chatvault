import SwiftUI

struct DateSeparatorView: View {
    let date: Date
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(formattedLabel)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(ChatVaultTheme.dateSeparator(for: colorScheme))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private var formattedLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct EmptyStateView: View {
    var symbol: String? = nil
    var useLogo = false
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            if useLogo {
                ChatVaultLogoView(size: 88)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct SelectArchivePlaceholder: View {
    let hasArchives: Bool

    var body: some View {
        EmptyStateView(
            useLogo: !hasArchives,
            title: hasArchives ? "Select a Chat" : "Welcome to ChatVault",
            message: hasArchives
                ? "Choose an imported chat from the sidebar to view messages."
                : "Import a WhatsApp chat export (.txt or .zip) to get started."
        )
    }
}

struct EmptyArchivesView: View {
    let onImport: () -> Void

    var body: some View {
        EmptyStateView(
            useLogo: true,
            title: "No Chats Yet",
            message: "Export a chat from WhatsApp on Android as a .txt or .zip file, transfer it here, then import it.",
            actionTitle: "Import Chat",
            action: onImport
        )
    }
}
