import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MediaInspectorView: View {
    let archive: ChatArchive
    let mediaItems: [MediaItem]
    let linkedMessages: [String: ChatMessage]
    let onSelectMessage: (UUID) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Media")
                    .font(.headline)
                Text("\(mediaItems.count) file\(mediaItems.count == 1 ? "" : "s") in this archive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if mediaItems.isEmpty {
                ContentUnavailableView {
                    Label("No Media Files", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Import a WhatsApp ZIP export with media included to browse attachments here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(mediaItems) { item in
                            MediaInspectorTile(
                                item: item,
                                linkedMessage: linkedMessages[item.fileName],
                                onSelect: {
                                    if let message = linkedMessages[item.fileName] {
                                        onSelectMessage(message.id)
                                    } else {
                                        #if os(macOS)
                                        NSWorkspace.shared.open(item.fileURL)
                                        #endif
                                    }
                                },
                                onOpen: {
                                    #if os(macOS)
                                    NSWorkspace.shared.open(item.fileURL)
                                    #endif
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .frame(minWidth: 240, idealWidth: 280)
    }
}

private struct MediaInspectorTile: View {
    let item: MediaItem
    let linkedMessage: ChatMessage?
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var thumbnail: Image?

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail {
                        thumbnail
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.12))
                            .overlay {
                                Image(systemName: item.mediaType.systemImage)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if item.mediaType == .video {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .padding(4)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding(4)
                }
            }

            Text(item.fileName)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(linkedMessage == nil ? .secondary : .primary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Open File") { onOpen() }
            if linkedMessage != nil {
                Button("Show in Chat") { onSelect() }
            }
        }
        .onAppear(perform: loadThumbnail)
    }

    private func loadThumbnail() {
        guard item.mediaType == .image || item.mediaType == .sticker else { return }
        #if os(macOS)
        if let nsImage = NSImage(contentsOf: item.fileURL) {
            thumbnail = Image(nsImage: nsImage)
        }
        #endif
    }
}
