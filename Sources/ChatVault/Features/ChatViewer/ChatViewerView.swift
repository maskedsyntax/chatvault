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

    func scrollToMessage(_ id: UUID) {
        scrollToMessageAction?(id)
    }

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

    @Environment(\.chatStore) private var chatStore
    @Query private var archiveMessages: [ChatMessage]

    @State private var searchText: String = ""
    @State private var showArchiveDetails = false
    @State private var showMediaInspector = false
    @State private var highlightedMessageID: UUID?
    @State private var scrollCoordinator = MessageScrollCoordinator()

    init(archive: ChatArchive, selectedArchive: Binding<ChatArchive?>) {
        self.archive = archive
        self._selectedArchive = selectedArchive

        let archiveId = archive.id
        self._archiveMessages = Query(
            filter: #Predicate<ChatMessage> { message in
                message.chatArchive?.id == archiveId
            },
            sort: \ChatMessage.sequenceIndex,
            order: .forward
        )
    }

    private var chatLayout: ChatLayout {
        ChatLayout(archive: archive)
    }

    private var linkedMessagesByFileName: [String: ChatMessage] {
        Dictionary(uniqueKeysWithValues: archiveMessages.compactMap { message in
            guard let fileName = message.mediaFileName else { return nil }
            return (fileName, message)
        })
    }

    private var hasMediaLibrary: Bool {
        archive.mediaFileCount > 0 || archive.storageDirectory != nil
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if scrollCoordinator.isSearching, scrollCoordinator.searchResultCount > 0 {
                SearchResultsBar(
                    resultCount: scrollCoordinator.searchResultCount,
                    onPrevious: {
                        scrollCoordinator.navigateSearch(direction: -1, onHighlight: highlight)
                    },
                    onNext: {
                        scrollCoordinator.navigateSearch(direction: 1, onHighlight: highlight)
                    }
                )
            }
        }
        .navigationTitle(archive.title)
        .searchable(text: $searchText, prompt: "Search messages or sender")
        .toolbar {
            if !scrollCoordinator.isSearching, scrollCoordinator.messageCount > 20 {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        scrollCoordinator.scrollToTop()
                    } label: {
                        Image(systemName: "arrow.up.to.line")
                    }
                    .help("Jump to Earliest")

                    Button {
                        scrollCoordinator.scrollToBottom()
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                    }
                    .help("Jump to Latest")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showArchiveDetails = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .help("Archive Details")
            }

            if hasMediaLibrary {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showMediaInspector.toggle()
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    .help("Media Inspector")
                }
            }
        }
        .inspector(isPresented: $showMediaInspector) {
            if let chatStore {
                MediaInspectorView(
                    archive: archive,
                    mediaItems: chatStore.mediaItems(for: archive),
                    linkedMessages: linkedMessagesByFileName,
                    onSelectMessage: { id in
                        scrollCoordinator.scrollToMessage(id)
                        highlight(id)
                    }
                )
            }
        }
        .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        .sheet(isPresented: $showArchiveDetails) {
            ArchiveDetailsView(archive: archive, selectedArchive: $selectedArchive)
        }
        .onChange(of: searchText) { _, newValue in
            scrollCoordinator.isSearching = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    @Query private var allMessages: [ChatMessage]
    @Environment(\.colorScheme) private var colorScheme

    @State private var hasScrolledToBottomOnAppear = false

    private var messages: [ChatMessage] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allMessages }
        return allMessages.filter { message in
            message.body.localizedStandardContains(trimmed) ||
            (message.senderName?.localizedStandardContains(trimmed) ?? false)
        }
    }

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
        self._allMessages = Query(
            filter: #Predicate<ChatMessage> { message in
                message.chatArchive?.id == archiveId
            },
            sort: \ChatMessage.sequenceIndex,
            order: .forward
        )
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
                if messages.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                                        isHighlighted: highlightedMessageID == message.id,
                                        storageDirectory: archive.storageDirectory
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
                scrollCoordinator.messageCount = allMessages.count
                scrollCoordinator.isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                scrollCoordinator.updateSearchResults(messages.map(\.id))
                scrollToBottomIfNeeded(proxy: proxy)
            }
            .onChange(of: allMessages.count) { _, _ in
                scrollCoordinator.messageCount = allMessages.count
                scrollCoordinator.updateSearchResults(messages.map(\.id))
            }
            .onChange(of: searchText) { oldValue, newValue in
                scrollCoordinator.isSearching = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                scrollCoordinator.updateSearchResults(messages.map(\.id))
                if oldValue.isEmpty && !newValue.isEmpty {
                    hasScrolledToBottomOnAppear = true
                }
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let lastMessage = allMessages.last {
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
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !hasScrolledToBottomOnAppear,
              let lastMessage = allMessages.last else { return }
        proxy.scrollTo(lastMessage.id, anchor: .bottom)
        hasScrolledToBottomOnAppear = true
    }
}

struct MessageRow: View {
    let message: ChatMessage
    let chatLayout: ChatLayout
    let isHighlighted: Bool
    let storageDirectory: String?

    @Environment(\.colorScheme) private var colorScheme

    private var isRightAligned: Bool {
        chatLayout.isRightAligned(message)
    }

    private var resolvedMediaURL: URL? {
        guard let fileName = message.mediaFileName else { return nil }
        return ArchiveStorage.resolveMediaURL(fileName: fileName, in: storageDirectory)
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
                    } else if let mediaURL = resolvedMediaURL, message.hasResolvableMedia {
                        InlineMediaView(message: message, mediaURL: mediaURL)
                    } else if message.hasResolvableMedia {
                        HStack(spacing: 4) {
                            Image(systemName: message.mediaType?.systemImage ?? "paperclip")
                            Text(message.mediaFileName ?? "Attachment unavailable")
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
