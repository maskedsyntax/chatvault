import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
struct ChatVaultApp: App {
    let modelContainer: ModelContainer

    init() {
        #if os(macOS)
        // SPM executables default to a non-regular activation policy, which hides
        // the app from the Dock and keeps windows behind other applications.
        NSApplication.shared.setActivationPolicy(.regular)
        ChatVaultLogo.configureApplicationIconIfNeeded()
        #endif

        do {
            modelContainer = try ModelContainerFactory.make()
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear(perform: activateApplication)
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    #if os(macOS)
    private func activateApplication() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    #else
    private func activateApplication() {}
    #endif
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatArchive.importedAt, order: .reverse) private var archives: [ChatArchive]

    @State private var chatStore: ChatStore?
    @State private var selectedArchive: ChatArchive?
    @State private var birthdayReminders: [BirthdayReminder] = []

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ChatVaultLogoView(size: 28)
                    Text("ChatVault")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                BirthdaysTodayView(reminders: birthdayReminders) { reminder in
                    if let archive = archives.first(where: { $0.id == reminder.archiveID }) {
                        selectedArchive = archive
                    }
                }

                ArchiveListView(selectedArchive: $selectedArchive)
            }
        } detail: {
            NavigationStack {
                if let archive = selectedArchive {
                    ChatViewerView(archive: archive, selectedArchive: $selectedArchive)
                } else {
                    SelectArchivePlaceholder(hasArchives: !archives.isEmpty)
                }
            }
        }
        .task {
            if chatStore == nil {
                chatStore = ChatStore(modelContext: modelContext)
            }
            refreshBirthdays()
        }
        .onChange(of: archives.count) { _, _ in
            refreshBirthdays()
        }
        .environment(\.chatStore, chatStore)
    }

    private func refreshBirthdays() {
        birthdayReminders = chatStore?.birthdaysToday() ?? []
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
