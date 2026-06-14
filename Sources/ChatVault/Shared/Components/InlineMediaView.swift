import SwiftUI
import AVKit
#if os(macOS)
import AppKit
import AVFoundation
#endif

struct InlineMediaView: View {
    let message: ChatMessage
    let mediaURL: URL

    @State private var image: Image?
    @State private var showVideoPlayer = false

    var body: some View {
        Group {
            switch message.mediaType ?? .unknown {
            case .image, .sticker:
                imageContent
            case .video:
                videoContent
            case .audio:
                audioContent
            case .document, .unknown:
                documentContent
            }
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let image {
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            ProgressView()
                .frame(width: 120, height: 80)
                .onAppear(perform: loadImage)
        }
    }

    private var videoContent: some View {
        Button {
            showVideoPlayer = true
        } label: {
            ZStack {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .onAppear(perform: loadVideoThumbnail)
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
            }
            .frame(width: 220, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showVideoPlayer) {
            #if os(macOS)
            VideoPlayerSheet(url: mediaURL)
            #endif
        }
    }

    private var audioContent: some View {
        Button {
            #if os(macOS)
            NSWorkspace.shared.open(mediaURL)
            #endif
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                Text(message.mediaFileName ?? "Voice note")
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var documentContent: some View {
        Button {
            #if os(macOS)
            NSWorkspace.shared.open(mediaURL)
            #endif
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                Text(message.mediaFileName ?? message.body)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func loadImage() {
        #if os(macOS)
        if let nsImage = NSImage(contentsOf: mediaURL) {
            image = Image(nsImage: nsImage)
        }
        #endif
    }

    private func loadVideoThumbnail() {
        #if os(macOS)
        let asset = AVURLAsset(url: mediaURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            image = Image(decorative: cgImage, scale: 2, orientation: .up)
        }
        #endif
    }
}

#if os(macOS)
private struct VideoPlayerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .padding()
            }
            VideoPlayer(player: AVPlayer(url: url))
                .frame(minWidth: 640, minHeight: 420)
        }
    }
}
#endif
