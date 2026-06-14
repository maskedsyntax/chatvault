import SwiftUI
import SwiftData

@main
struct ChatVaultApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: ChatArchive.self, ChatMessage.self)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 960, height: 640)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatArchive.importedAt, order: .reverse) private var archives: [ChatArchive]

    @State private var chatStore: ChatStore?
    @State private var selectedArchive: ChatArchive?

    var body: some View {
        NavigationSplitView {
            ArchiveListView(selectedArchive: $selectedArchive)
        } detail: {
            if let archive = selectedArchive {
                ChatViewerView(archive: archive, selectedArchive: $selectedArchive)
            } else {
                SelectArchivePlaceholder(hasArchives: !archives.isEmpty)
            }
        }
        .task {
            if chatStore == nil {
                chatStore = ChatStore(modelContext: modelContext)
            }
        }
        .environment(\.chatStore, chatStore)
    }
}

private struct ChatStoreKey: EnvironmentKey {
    static let defaultValue: ChatStore? = nil
}

extension EnvironmentValues {
    var chatStore: ChatStore? {
        get { self[ChatStoreKey.self] }
        set { self[ChatStoreKey.self] = newValue }
    }
}
