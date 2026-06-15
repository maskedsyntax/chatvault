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
    @State private var showDateJump = false
    @State private var messageDays: [MessageDaySummary] = []

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
                        showDateJump = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .help("Jump to Date")

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
        .sheet(isPresented: $showDateJump) {
            DateJumpView(days: messageDays) { day in
                scrollCoordinator.scrollToMessage(day.firstMessageID)
                highlight(day.firstMessageID)
            }
        }
        .task(id: archive.id) {
            try? chatStore?.ensureParticipantRecords(for: archive)
        }
        .task(id: archive.id) {
            if let chatStore {
                try? chatStore.rebuildSearchIndexIfNeeded(for: archive)
                messageDays = (try? chatStore.messageDays(for: archive)) ?? []
            }
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
    let archive: ChatArchive
    let isGroupChat: Bool
    let rightAlignedSender: String?
    private let displayNames: [String: String]

    init(archive: ChatArchive) {
        self.archive = archive

        if !archive.participantRecords.isEmpty {
            isGroupChat = archive.isGroupChat
            rightAlignedSender = archive.myParticipant?.exportName
            displayNames = Dictionary(
                uniqueKeysWithValues: archive.participantRecords.map { ($0.exportName, $0.resolvedName) }
            )
        } else {
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
            displayNames = Dictionary(uniqueKeysWithValues: participants.map { ($0, $0) })
        }
    }

    func displayName(for exportName: String?) -> String? {
        guard let exportName else { return nil }
        return displayNames[exportName] ?? exportName
    }

    func isRightAligned(_ message: ChatMessage) -> Bool {
        guard let sender = message.senderName, let rightAlignedSender else {
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
    @Environment(\.chatStore) private var chatStore

    @State private var hasScrolledToBottomOnAppear = false
    @State private var cachedSections: [MessageSection] = []
    @State private var filteredMessages: [ChatMessage] = []
    @State private var searchMatchIDs: Set<UUID>?
    @State private var searchTask: Task<Void, Never>?

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

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if filteredMessages.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "No Results",
                        message: "No messages matching \"\(searchText)\"."
                    )
                } else {
                    List {
                        ForEach(cachedSections) { section in
                            Section {
                                ForEach(section.messages) { message in
                                    MessageRow(
                                        message: message,
                                        chatLayout: chatLayout,
                                        isHighlighted: highlightedMessageID == message.id,
                                        storageDirectory: archive.storageDirectory
                                    )
                                    .id(message.id)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                                    .listRowBackground(Color.clear)
                                }
                            } header: {
                                if let date = section.date {
                                    DateSeparatorView(date: date)
                                        .id("date-\(section.id)")
                                        .textCase(nil)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }

                        Section {
                            Color.clear
                                .frame(height: 24)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ChatVaultTheme.chatBackground(for: colorScheme))
            .onAppear {
                rebuildCache()
                scrollCoordinator.register(
                    scrollToTop: {
                        if let first = filteredMessages.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    },
                    scrollToBottom: {
                        if let last = filteredMessages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    },
                    scrollToMessage: { id in
                        proxy.scrollTo(id, anchor: .center)
                    }
                )
                scrollCoordinator.messageCount = allMessages.count
                scrollCoordinator.isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                scrollCoordinator.updateSearchResults(filteredMessages.map(\.id))
                scrollToBottomIfNeeded(proxy: proxy)
            }
            .onChange(of: allMessages.count) { _, _ in
                rebuildCache()
                scrollCoordinator.messageCount = allMessages.count
                scrollCoordinator.updateSearchResults(filteredMessages.map(\.id))
            }
            .onChange(of: searchText) { oldValue, newValue in
                scheduleSearch(for: newValue)
                scrollCoordinator.isSearching = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if oldValue.isEmpty && !newValue.isEmpty {
                    hasScrolledToBottomOnAppear = true
                }
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let lastMessage = allMessages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .onChange(of: archive.id) { _, _ in
                hasScrolledToBottomOnAppear = false
                rebuildCache()
                scrollToBottomIfNeeded(proxy: proxy)
            }
        }
    }

    private func rebuildCache() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            filteredMessages = allMessages
        } else if let searchMatchIDs {
            filteredMessages = allMessages.filter { searchMatchIDs.contains($0.id) }
        } else {
            filteredMessages = []
        }
        cachedSections = Self.buildSections(from: filteredMessages)
    }

    private func scheduleSearch(for query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            searchMatchIDs = nil
            rebuildCache()
            scrollCoordinator.updateSearchResults(filteredMessages.map(\.id))
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            if let chatStore {
                if let ids = try? chatStore.searchMessages(in: archive, query: trimmed) {
                    guard !Task.isCancelled else { return }
                    searchMatchIDs = Set(ids)
                } else {
                    searchMatchIDs = Set(
                        allMessages.filter {
                            $0.body.localizedStandardContains(trimmed) ||
                            ($0.senderName?.localizedStandardContains(trimmed) ?? false)
                        }.map(\.id)
                    )
                }
            } else {
                searchMatchIDs = Set(
                    allMessages.filter {
                        $0.body.localizedStandardContains(trimmed) ||
                        ($0.senderName?.localizedStandardContains(trimmed) ?? false)
                    }.map(\.id)
                )
            }

            rebuildCache()
            scrollCoordinator.updateSearchResults(filteredMessages.map(\.id))
        }
    }

    private static func buildSections(from messages: [ChatMessage]) -> [MessageSection] {
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

    private static let maxBubbleWidth: CGFloat = 480
    private static let edgeMargin: CGFloat = 56
    private static let bubbleHPadding: CGFloat = 12
    private static let bubbleVPadding: CGFloat = 8

    private var isRightAligned: Bool {
        chatLayout.isRightAligned(message)
    }

    private var bubbleStyle: ChatBubbleShape.Style {
        isRightAligned ? .sent : .received
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
            HStack(alignment: .bottom, spacing: 0) {
                if isRightAligned {
                    Spacer(minLength: Self.edgeMargin)
                }

                VStack(alignment: .leading, spacing: 3) {
                    if chatLayout.shouldShowSenderName(message, isRightAligned: isRightAligned),
                       let sender = message.senderName {
                        Text(chatLayout.displayName(for: sender) ?? sender)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(ParticipantColor.color(for: sender))
                            .padding(.leading, 2)
                    }

                    bubbleBody
                }
                .frame(maxWidth: Self.maxBubbleWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

                if !isRightAligned {
                    Spacer(minLength: Self.edgeMargin)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var bubbleBody: some View {
        bubbleContent
            .background(bubbleColor)
            .clipShape(ChatBubbleShape(style: bubbleStyle))
            .overlay {
                if isHighlighted {
                    ChatBubbleShape(style: bubbleStyle)
                        .fill(ChatVaultTheme.highlightFlash)
                }
            }
            .shadow(
                color: bubbleShadowColor,
                radius: colorScheme == .dark ? 0 : 2,
                x: 0,
                y: 1
            )
    }

    @ViewBuilder
    private var bubbleContent: some View {
        Group {
            if message.isDeletedMessage {
                textBubble(
                    HStack(spacing: 4) {
                        Image(systemName: "nosign")
                        Text("Message deleted")
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
                )
            } else if message.isMediaPlaceholder {
                textBubble(
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                        Text("Media omitted")
                    }
                    .font(.body)
                    .foregroundStyle(ChatVaultTheme.mediaPlaceholder)
                    .italic()
                )
            } else if let mediaURL = resolvedMediaURL, message.hasResolvableMedia {
                mediaBubble(InlineMediaView(message: message, mediaURL: mediaURL))
            } else if message.hasResolvableMedia {
                textBubble(
                    HStack(spacing: 4) {
                        Image(systemName: message.mediaType?.systemImage ?? "paperclip")
                        Text(message.mediaFileName ?? "Attachment unavailable")
                    }
                    .font(.body)
                    .foregroundStyle(ChatVaultTheme.mediaPlaceholder)
                    .italic()
                )
            } else {
                textBubble(
                    Text(message.body)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                )
            }
        }
        .padding(.horizontal, Self.bubbleHPadding)
        .padding(.vertical, Self.bubbleVPadding)
    }

    @ViewBuilder
    private func textBubble<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: Self.maxBubbleWidth - Self.bubbleHPadding * 2, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, message.timestamp == nil ? 0 : timestampReserveWidth)
            .overlay(alignment: .bottomTrailing) {
                if let date = message.timestamp {
                    timestampView(date)
                }
            }
    }

    @ViewBuilder
    private func mediaBubble<Content: View>(_ content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if let date = message.timestamp {
                    timestampView(date)
                        .padding(6)
                        .background(Color.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(6)
                }
            }
    }

    private func timestampView(_ date: Date) -> some View {
        HStack(spacing: 3) {
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(timestampColor)

            if isRightAligned {
                HStack(spacing: -4) {
                    Image(systemName: "checkmark")
                    Image(systemName: "checkmark")
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ChatVaultTheme.sentCheckmark)
            }
        }
    }

    private var timestampReserveWidth: CGFloat {
        isRightAligned ? 62 : 44
    }

    private var bubbleColor: Color {
        isRightAligned
            ? ChatVaultTheme.sentBubble(for: colorScheme)
            : ChatVaultTheme.receivedBubble(for: colorScheme)
    }

    private var bubbleShadowColor: Color {
        isRightAligned
            ? ChatVaultTheme.sentBubbleShadow(for: colorScheme)
            : ChatVaultTheme.receivedBubbleShadow(for: colorScheme)
    }

    private var timestampColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.55)
            : Color.black.opacity(0.45)
    }
}
