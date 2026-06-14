import Foundation

public enum MediaType: String, Codable, CaseIterable, Sendable {
    case image
    case video
    case audio
    case document
    case sticker
    case unknown

    public static func infer(from fileName: String) -> MediaType {
        let base = (fileName as NSString).lastPathComponent
        let upper = base.uppercased()
        let ext = (base as NSString).pathExtension.lowercased()

        if upper.hasPrefix("IMG-") || upper.hasPrefix("STK-") {
            return upper.hasPrefix("STK-") ? .sticker : .image
        }
        if upper.hasPrefix("VID-") { return .video }
        if upper.hasPrefix("PTT-") || upper.hasPrefix("AUD-") { return .audio }

        switch ext {
        case "jpg", "jpeg", "png", "webp", "heic", "gif":
            return ext == "gif" && upper.contains("STK") ? .sticker : .image
        case "mp4", "mov", "m4v":
            return .video
        case "opus", "m4a", "aac", "mp3", "ogg", "wav":
            return .audio
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "zip":
            return .document
        default:
            return .unknown
        }
    }

    public var systemImage: String {
        switch self {
        case .image: "photo"
        case .video: "video"
        case .audio: "waveform"
        case .document: "doc"
        case .sticker: "face.smiling"
        case .unknown: "paperclip"
        }
    }
}
