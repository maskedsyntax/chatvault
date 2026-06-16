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
    @Binding var selectedArchiveID: UUID?

    @Environment(\.chatStore) private var chatStore

    @State private var searchText: String = ""
    @State private var showArchiveDetails = false
    @State private var showMediaInspector = false
    @State private var highlightedMessageID: UUID?
    @State private var scrollCoordinator = MessageScrollCoordinator()
    @State private var showDateJump = false
    @State private var messageDays: [MessageDaySummary] = []
    @State private var chatLayout: ChatLayout?
    @State private var linkedMessagesByFileName: [String: ChatMessage] = [:]

    init(archive: ChatArchive, selectedArchiveID: Binding<UUID?>) {
        self.archive = archive
        self._selectedArchiveID = selectedArchiveID
        self._chatLayout = State(initialValue: ChatLayout(archive: archive))
    }

    private var resolvedChatLayout: ChatLayout {
        chatLayout ?? ChatLayout(archive: archive)
    }

    private var hasMediaLibrary: Bool {
        archive.mediaFileCount > 0 || archive.storageDirectory != nil
    }

    var body: some View {
        MessageListView(
            archive: archive,
            searchText: searchText,
            chatLayout: resolvedChatLayout,
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
        .onChange(of: archive.id) { _, _ in
            showMediaInspector = false
            linkedMessagesByFileName = [:]
        }
        .sheet(isPresented: $showArchiveDetails) {
            ArchiveDetailsView(archive: archive, selectedArchiveID: $selectedArchiveID)
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
                messageDays = (try? chatStore.messageDays(for: archive)) ?? []
            }
        }
        .task(id: "\(archive.id)-\(showMediaInspector)") {
            guard showMediaInspector, let chatStore else { return }
            linkedMessagesByFileName = (try? chatStore.mediaLinkedMessages(for: archive)) ?? [:]
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
    private let displayNames: [String: String]

    init(archive: ChatArchive) {
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
    private static let pageSize = 500

    let archive: ChatArchive
    let searchText: String
    let chatLayout: ChatLayout
    let highlightedMessageID: UUID?
    let scrollCoordinator: MessageScrollCoordinator
    let onHighlight: (UUID) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.chatStore) private var chatStore

    @State private var hasScrolledToBottomOnAppear = false
    @State private var cachedSections: [MessageSection] = []
    @State private var loadedMessages: [ChatMessage] = []
    @State private var visibleMessages: [ChatMessage] = []
    @State private var loadedSearchIDs: [UUID] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isLoadingMessages = false
    @State private var canLoadEarlier = false

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
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if visibleMessages.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "No Results",
                        message: "No messages matching \"\(searchText)\"."
                    )
                } else {
                    List {
                        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           canLoadEarlier {
                            Section {
                                Button {
                                    loadEarlierMessages()
                                } label: {
                                    HStack {
                                        Spacer()
                                        if isLoadingMessages {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                        Text(isLoadingMessages ? "Loading earlier..." : "Load Earlier")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoadingMessages)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }

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
                                .id("chat-bottom")
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
                loadInitialMessages()
                scrollCoordinator.register(
                    scrollToTop: {
                        if let first = visibleMessages.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    },
                    scrollToBottom: {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    },
                    scrollToMessage: { id in
                        if visibleMessages.contains(where: { $0.id == id }) {
                            proxy.scrollTo(id, anchor: .center)
                        } else {
                            loadWindow(containing: id)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(50))
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                )
                scrollCoordinator.messageCount = archive.messageCount
                scrollCoordinator.isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                scrollCoordinator.updateSearchResults(visibleMessages.map(\.id))
                scrollToBottomIfNeeded(proxy: proxy)
            }
            .onChange(of: cachedSections.count) { _, _ in
                scrollToBottomIfNeeded(proxy: proxy)
            }
            .onChange(of: searchText) { oldValue, newValue in
                scheduleSearch(for: newValue)
                scrollCoordinator.isSearching = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if oldValue.isEmpty && !newValue.isEmpty {
                    hasScrolledToBottomOnAppear = true
                }
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    visibleMessages = loadedMessages
                    cachedSections = Self.buildSections(from: visibleMessages)
                    scrollCoordinator.updateSearchResults(visibleMessages.map(\.id))
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            .onChange(of: archive.id) { _, _ in
                hasScrolledToBottomOnAppear = false
                loadedMessages = []
                visibleMessages = []
                cachedSections = []
                loadedSearchIDs = []
                loadInitialMessages()
                scrollToBottomIfNeeded(proxy: proxy)
            }
        }
    }

    private func loadInitialMessages() {
        guard loadedMessages.isEmpty, !isLoadingMessages, let chatStore else { return }
        isLoadingMessages = true
        do {
            loadedMessages = try chatStore.recentMessages(for: archive, limit: Self.pageSize)
            visibleMessages = loadedMessages
            cachedSections = Self.buildSections(from: visibleMessages)
            canLoadEarlier = (loadedMessages.first?.sequenceIndex ?? 0) > 0
            scrollCoordinator.messageCount = archive.messageCount
            scrollCoordinator.updateSearchResults(visibleMessages.map(\.id))
        } catch {
            loadedMessages = []
            visibleMessages = []
            cachedSections = []
            canLoadEarlier = false
        }
        isLoadingMessages = false
    }

    private func loadWindow(containing messageID: UUID) {
        guard !isLoadingMessages, let chatStore else { return }
        isLoadingMessages = true
        do {
            let window = try chatStore.messageWindow(
                archive: archive,
                containing: messageID,
                radius: Self.pageSize / 2
            )
            if !window.isEmpty {
                loadedMessages = window
                visibleMessages = window
                cachedSections = Self.buildSections(from: visibleMessages)
                canLoadEarlier = (loadedMessages.first?.sequenceIndex ?? 0) > 0
                scrollCoordinator.updateSearchResults(visibleMessages.map(\.id))
                hasScrolledToBottomOnAppear = true
            }
        } catch {
            // Keep the current page if a jump target cannot be loaded.
        }
        isLoadingMessages = false
    }

    private func loadEarlierMessages() {
        guard !isLoadingMessages,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let firstIndex = loadedMessages.first?.sequenceIndex,
              firstIndex > 0,
              let chatStore else { return }

        isLoadingMessages = true
        do {
            let earlier = try chatStore.messagesBefore(
                archive: archive,
                sequenceIndex: firstIndex,
                limit: Self.pageSize
            )
            loadedMessages.insert(contentsOf: earlier, at: 0)
            visibleMessages = loadedMessages
            cachedSections = Self.buildSections(from: visibleMessages)
            canLoadEarlier = (loadedMessages.first?.sequenceIndex ?? 0) > 0
            scrollCoordinator.updateSearchResults(visibleMessages.map(\.id))
        } catch {
            canLoadEarlier = false
        }
        isLoadingMessages = false
    }

    private func scheduleSearch(for query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            loadedSearchIDs = []
            visibleMessages = loadedMessages
            cachedSections = Self.buildSections(from: visibleMessages)
            scrollCoordinator.updateSearchResults(visibleMessages.map(\.id))
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            if let chatStore {
                if let ids = try? chatStore.searchMessages(in: archive, query: trimmed) {
                    guard !Task.isCancelled else { return }
                    loadedSearchIDs = ids
                    visibleMessages = (try? chatStore.messages(matching: ids, in: archive)) ?? []
                } else {
                    visibleMessages = loadedMessages.filter {
                            $0.body.localizedStandardContains(trimmed) ||
                            ($0.senderName?.localizedStandardContains(trimmed) ?? false)
                    }
                    loadedSearchIDs = visibleMessages.map(\.id)
                }
            } else {
                visibleMessages = loadedMessages.filter {
                        $0.body.localizedStandardContains(trimmed) ||
                        ($0.senderName?.localizedStandardContains(trimmed) ?? false)
                }
                loadedSearchIDs = visibleMessages.map(\.id)
            }

            cachedSections = Self.buildSections(from: visibleMessages)
            scrollCoordinator.updateSearchResults(loadedSearchIDs)
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
              !visibleMessages.isEmpty else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            proxy.scrollTo("chat-bottom", anchor: .bottom)
            hasScrolledToBottomOnAppear = true
        }
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
