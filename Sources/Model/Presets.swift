import Foundation

/// One-tap settings for the places people actually send video to.
struct CompressionPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let mode: CompressionMode
    let maxLongSide: Int?
    let fps: FPSChoice
    let codec: VideoCodec
    let audio: AudioChoice

    func apply(to settings: CompressionSettings) -> CompressionSettings {
        var s = settings
        s.presetID = id
        s.mode = mode
        s.maxLongSide = maxLongSide
        s.fps = fps
        s.codec = codec
        s.audio = audio
        return s
    }
}

enum Presets {
    static let mb: Int64 = 1_000_000

    /// Order is the order on screen.
    static let all: [CompressionPreset] = [
        CompressionPreset(id: "whatsapp", title: "WhatsApp", subtitle: "Under 16 MB", symbol: "message.fill",
                          mode: .targetSize(bytes: 15 * mb), maxLongSide: 1280, fps: .fps30, codec: .h264, audio: .reduced),
        CompressionPreset(id: "email", title: "Email", subtitle: "Under 25 MB", symbol: "envelope.fill",
                          mode: .targetSize(bytes: 18 * mb), maxLongSide: 1280, fps: .fps30, codec: .h264, audio: .reduced),
        CompressionPreset(id: "discord", title: "Discord", subtitle: "Under 10 MB", symbol: "bubble.left.and.bubble.right.fill",
                          mode: .targetSize(bytes: 9 * mb), maxLongSide: 1280, fps: .fps30, codec: .h264, audio: .reduced),
        CompressionPreset(id: "messages", title: "Messages", subtitle: "Light for texting", symbol: "text.bubble.fill",
                          mode: .targetSize(bytes: 40 * mb), maxLongSide: 1280, fps: .fps30, codec: .hevc, audio: .keep),
        CompressionPreset(id: "telegram", title: "Telegram", subtitle: "Sharp, 1080p", symbol: "paperplane.fill",
                          mode: .quality(0.5), maxLongSide: 1920, fps: .fps30, codec: .h264, audio: .keep),
        CompressionPreset(id: "instagram", title: "Instagram", subtitle: "Reels and posts", symbol: "camera.fill",
                          mode: .quality(0.6), maxLongSide: 1920, fps: .fps30, codec: .h264, audio: .keep),
        CompressionPreset(id: "tiktok", title: "TikTok", subtitle: "Vertical 1080p", symbol: "music.note",
                          mode: .quality(0.6), maxLongSide: 1920, fps: .fps30, codec: .h264, audio: .keep),
        CompressionPreset(id: "x", title: "X (Twitter)", subtitle: "720p, light", symbol: "xmark",
                          mode: .quality(0.45), maxLongSide: 1280, fps: .fps30, codec: .h264, audio: .keep),
        CompressionPreset(id: "shorts", title: "YouTube Shorts", subtitle: "Vertical 1080p", symbol: "play.rectangle.fill",
                          mode: .quality(0.6), maxLongSide: 1920, fps: .fps30, codec: .h264, audio: .keep),
        CompressionPreset(id: "smallest", title: "Smallest", subtitle: "Tiny, 480p", symbol: "arrow.down.right.and.arrow.up.left",
                          mode: .quality(0.0), maxLongSide: 854, fps: .fps24, codec: .hevc, audio: .reduced)
    ]

    static func preset(id: String?) -> CompressionPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

/// Resolution choices on the setup screen.
enum ResolutionChoice: CaseIterable, Identifiable {
    case original, p2160, p1440, p1080, p720, p480, p360
    var id: Int { longSide ?? 0 }
    var longSide: Int? {
        switch self {
        case .original: return nil
        case .p2160: return 3840
        case .p1440: return 2560
        case .p1080: return 1920
        case .p720: return 1280
        case .p480: return 854
        case .p360: return 640
        }
    }
    var title: String {
        switch self {
        case .original: return "Original"
        case .p2160: return "4K"
        case .p1440: return "1440p"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        }
    }
    static func match(_ side: Int?) -> ResolutionChoice {
        allCases.first { $0.longSide == side } ?? .original
    }
}
