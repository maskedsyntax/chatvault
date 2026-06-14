import SwiftUI
import SwiftData

@MainActor
@Observable
final class MessageScrollCoordinator {
    var messageCount = 0
    var isSearching = false
    var searchResultCount = 0
    var searchResultIndex = 0

    private var scrollToTopAction: (() -> Void)?
    private var scrollToBottomAction: (() -> Void)?
    private var scrollToMessageAction: ((UUID) -> Void)?
    private var searchResults: [UUID] = []

    func register(
        scrollToTop: @escaping () -> Void,
        scrollToBottom: @escaping () -> Void,
        scrollToMessage: @escaping (UUID) -> Void
    ) {
        scrollToTopAction = scrollToTop
        scrollToBottomAction = scrollToBottom
        scrollToMessageAction = scrollToMessage
    }

    func updateSearchResults(_ messageIDs: [UUID]) {
        searchResults = messageIDs
        searchResultCount = messageIDs.count
        if searchResultIndex >= messageIDs.count {
            searchResultIndex = 0
        }
    }

    func scrollToTop() { scrollToTopAction?() }
    func scrollToBottom() { scrollToBottomAction?() }

    func navigateSearch(direction: Int, onHighlight: (UUID) -> Void) {
        guard !searchResults.isEmpty else { return }
        searchResultIndex = (searchResultIndex + direction + searchResults.count) % searchResults.count
        let id = searchResults[searchResultIndex]
        scrollToMessageAction?(id)
        onHighlight(id)
    }
}

struct ChatViewerView: View {
    let archive: ChatArchive
    @Binding var selectedArchive: ChatArchive?

    @State private var searchText: String = ""
    @State private var showArchiveDetails = false
    @State private var highlightedMessageID: UUID?
    @State private var scrollCoordinator = MessageScrollCoordinator()

    private var chatLayout: ChatLayout {
        ChatLayout(archive: archive)
    }

    var body: some View {
        MessageListView(
            archive: archive,
            searchText: searchText,
            chatLayout: chatLayout,
            highlightedMessageID: highlightedMessageID,
            scrollCoordinator: scrollCoordinator,
            onHighlight: { id in
                highlightedMessageID = id
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    if highlightedMessageID == id {
                        highlightedMessageID = nil
                    }
                }
            }
        )
        .id("\(archive.id)-\(searchText)")
        .navigationTitle(archive.title)
        .searchable(text: $searchText, prompt: "Search messages or sender")
        .toolbar {
            if scrollCoordinator.isSearching {
                ToolbarItem(placement: .automatic) {
                    Text("\(scrollCoordinator.searchResultCount) result\(scrollCoordinator.searchResultCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItemGroup(placement: .automatic) {
                if scrollCoordinator.isSearching {
                    if scrollCoordinator.searchResultCount > 0 {
                        Button {
                            scrollCoordinator.navigateSearch(direction: -1, onHighlight: highlight)
                        } label: {
                            Label("Previous Result", systemImage: "chevron.up")
                        }
                        Button {
                            scrollCoordinator.navigateSearch(direction: 1, onHighlight: highlight)
                        } label: {
                            Label("Next Result", systemImage: "chevron.down")
                        }
                    }
                } else if scrollCoordinator.messageCount > 20 {
                    Button {
                        scrollCoordinator.scrollToTop()
                    } label: {
                        Label("Jump to Earliest", systemImage: "arrow.up.to.line")
                    }
                    Button {
                        scrollCoordinator.scrollToBottom()
                    } label: {
                        Label("Jump to Latest", systemImage: "arrow.down.to.line")
                    }
                }
                Button {
                    showArchiveDetails = true
                } label: {
                    Label("Archive Details", systemImage: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showArchiveDetails) {
            ArchiveDetailsView(archive: archive, selectedArchive: $selectedArchive)
        }
        .onChange(of: searchText) { _, newValue in
            scrollCoordinator.isSearching = !newValue.isEmpty
            scrollCoordinator.searchResultIndex = 0
        }
    }

    private func highlight(_ id: UUID) {
        highlightedMessageID = id
        Task {
            try? await Task.sleep(for: .seconds(1))
            if highlightedMessageID == id {
                highlightedMessageID = nil
            }
        }
    }
}

struct ChatLayout {
    let isGroupChat: Bool
    let rightAlignedSender: String?

    init(archive: ChatArchive) {
        let participants = archive.participants
        if participants.count == 2 {
            isGroupChat = false
            if let contact = participants.first(where: { archive.title.localizedCaseInsensitiveContains($0) }) {
                rightAlignedSender = participants.first(where: { $0 != contact })
            } else {
                rightAlignedSender = participants.last
            }
        } else if participants.count > 2 {
            isGroupChat = true
            rightAlignedSender = nil
        } else {
            isGroupChat = false
            rightAlignedSender = nil
        }
    }

    func isRightAligned(_ message: ChatMessage) -> Bool {
        guard !isGroupChat, let sender = message.senderName, let rightAlignedSender else {
            return false
        }
        return sender == rightAlignedSender
    }

    func shouldShowSenderName(_ message: ChatMessage, isRightAligned: Bool) -> Bool {
        isGroupChat && !isRightAligned && message.senderName != nil
    }
}

struct MessageSection: Identifiable {
    let id: String
    let date: Date?
    let messages: [ChatMessage]
}

struct MessageListView: View {
    let archive: ChatArchive
    let searchText: String
    let chatLayout: ChatLayout
    let highlightedMessageID: UUID?
    let scrollCoordinator: MessageScrollCoordinator
    let onHighlight: (UUID) -> Void

    @Query private var messages: [ChatMessage]
    @Environment(\.colorScheme) private var colorScheme

    @State private var hasScrolledToBottomOnAppear = false

    init(
        archive: ChatArchive,
        searchText: String,
        chatLayout: ChatLayout,
        highlightedMessageID: UUID?,
        scrollCoordinator: MessageScrollCoordinator,
        onHighlight: @escaping (UUID) -> Void
    ) {
        self.archive = archive
        self.searchText = searchText
        self.chatLayout = chatLayout
        self.highlightedMessageID = highlightedMessageID
        self.scrollCoordinator = scrollCoordinator
        self.onHighlight = onHighlight

        let archiveId = archive.id
        let queryText = searchText

        if queryText.isEmpty {
            self._messages = Query(
                filter: #Predicate<ChatMessage> { message in
                    message.chatArchive?.id == archiveId
                },
                sort: \ChatMessage.sequenceIndex,
                order: .forward
            )
        } else {
            self._messages = Query(
                filter: #Predicate<ChatMessage> { message in
                    message.chatArchive?.id == archiveId &&
                    (message.body.localizedStandardContains(queryText) ||
                     (message.senderName != nil && message.senderName!.localizedStandardContains(queryText)))
                },
                sort: \ChatMessage.sequenceIndex,
                order: .forward
            )
        }
    }

    private var sections: [MessageSection] {
        var result: [MessageSection] = []
        var currentDay: Date?
        var currentMessages: [ChatMessage] = []

        let calendar = Calendar.current

        for message in messages {
            let messageDay = message.timestamp.map { calendar.startOfDay(for: $0) }
            if messageDay != currentDay {
                if !currentMessages.isEmpty {
                    result.append(MessageSection(
                        id: "section-\(result.count)",
                        date: currentDay,
                        messages: currentMessages
                    ))
                }
                currentDay = messageDay
                currentMessages = [message]
            } else {
                currentMessages.append(message)
            }
        }

        if !currentMessages.isEmpty {
            result.append(MessageSection(
                id: "section-\(result.count)",
                date: currentDay,
                messages: currentMessages
            ))
        }

        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if messages.isEmpty && !searchText.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "No Results",
                        message: "No messages matching \"\(searchText)\"."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(sections) { section in
                                if let date = section.date {
                                    DateSeparatorView(date: date)
                                        .id("date-\(section.id)")
                                }
                                ForEach(section.messages) { message in
                                    MessageRow(
                                        message: message,
                                        chatLayout: chatLayout,
                                        isHighlighted: highlightedMessageID == message.id
                                    )
                                    .id(message.id)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(ChatVaultTheme.chatBackground(for: colorScheme))
            .onAppear {
                scrollCoordinator.register(
                    scrollToTop: {
                        if let first = messages.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    },
                    scrollToBottom: {
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    },
                    scrollToMessage: { id in
                        proxy.scrollTo(id, anchor: .center)
                    }
                )
                scrollCoordinator.messageCount = messages.count
                scrollCoordinator.isSearching = !searchText.isEmpty
                scrollCoordinator.updateSearchResults(messages.map(\.id))
                scrollToBottomIfNeeded(proxy: proxy)
            }
            .onChange(of: messages.count) { _, newCount in
                scrollCoordinator.messageCount = newCount
                scrollCoordinator.updateSearchResults(messages.map(\.id))
            }
            .onChange(of: searchText) { oldValue, newValue in
                scrollCoordinator.isSearching = !newValue.isEmpty
                if oldValue.isEmpty && !newValue.isEmpty {
                    hasScrolledToBottomOnAppear = true
                }
                if newValue.isEmpty, let lastMessage = messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .onChange(of: archive.id) { _, _ in
                hasScrolledToBottomOnAppear = false
                scrollToBottomIfNeeded(proxy: proxy)
            }
        }
    }

    private func scrollToBottomIfNeeded(proxy: ScrollViewProxy) {
        guard searchText.isEmpty, !hasScrolledToBottomOnAppear, let lastMessage = messages.last else { return }
        proxy.scrollTo(lastMessage.id, anchor: .bottom)
        hasScrolledToBottomOnAppear = true
    }
}

struct MessageRow: View {
    let message: ChatMessage
    let chatLayout: ChatLayout
    let isHighlighted: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var isRightAligned: Bool {
        chatLayout.isRightAligned(message)
    }

    var body: some View {
        if message.isSystemMessage {
            Text(message.body)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ChatVaultTheme.systemPill(for: colorScheme))
                .clipShape(Capsule())
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            HStack {
                if isRightAligned {
                    Spacer(minLength: 50)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if chatLayout.shouldShowSenderName(message, isRightAligned: isRightAligned),
                       let sender = message.senderName {
                        Text(sender)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(ParticipantColor.color(for: sender))
                    }

                    if message.isMediaPlaceholder {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                            Text("Media omitted")
                        }
                        .font(.body)
                        .foregroundStyle(ChatVaultTheme.mediaPlaceholder)
                        .italic()
                    } else {
                        Text(message.body)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }

                    if let date = message.timestamp {
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                .overlay {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(ChatVaultTheme.highlightFlash)
                    }
                }

                if !isRightAligned {
                    Spacer(minLength: 50)
                }
            }
            .frame(maxWidth: .infinity, alignment: isRightAligned ? .trailing : .leading)
            .padding(.vertical, 2)
        }
    }

    private var bubbleColor: Color {
        isRightAligned
            ? ChatVaultTheme.sentBubble(for: colorScheme)
            : ChatVaultTheme.receivedBubble(for: colorScheme)
    }
}
