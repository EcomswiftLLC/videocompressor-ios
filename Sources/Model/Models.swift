import Foundation
import CoreGraphics

enum VideoCodec: String, CaseIterable, Codable, Identifiable {
    case h264, hevc
    var id: String { rawValue }
    var title: String { self == .h264 ? "H.264" : "HEVC" }
    var detail: String { self == .h264 ? "Plays everywhere" : "Smaller files" }
    /// Bits needed relative to H.264 for the same look.
    var efficiency: Double { self == .h264 ? 1.0 : 0.62 }
}

enum ContainerKind: String, CaseIterable, Codable {
    case mp4, mov
    var fileExtension: String { rawValue }
}

enum AudioMode: Equatable, Codable {
    case keep(bitrate: Int)
    case mute
}

/// Facts about a source file, read once when it is added.
struct MediaInfo: Equatable, Identifiable {
    let id: UUID
    var url: URL
    var displayName: String
    var fileSize: Int64
    var duration: Double
    /// Width and height as the person sees them (rotation applied).
    var width: Int
    var height: Int
    var fps: Double
    var codecName: String
    var hasAudio: Bool
    var videoBitrate: Int
    var audioBitrate: Int
    var isHDR: Bool
    var route: EngineRoute

    var longSide: Int { max(width, height) }
    var resolutionLabel: String { "\(width)×\(height)" }
    var shortLabel: String {
        let s = min(width, height)
        switch s {
        case 2160...: return "4K"
        case 1440...: return "1440p"
        case 1080...: return "1080p"
        case 720...: return "720p"
        case 480...: return "480p"
        default: return "\(s)p"
        }
    }
}

enum EngineRoute: String, Equatable {
    case native, ffmpeg
}

/// What the engines are asked to produce. All numbers are final (no "original" placeholders left).
struct OutputSpec: Equatable {
    var codec: VideoCodec = .h264
    var container: ContainerKind = .mp4
    var width: Int
    var height: Int
    var fps: Double
    var videoBitrate: Int
    var audio: AudioMode = .keep(bitrate: 128_000)
    var stripMetadata: Bool = true
    var trim: ClosedRange<Double>? = nil
    var convertHDRToSDR: Bool = true
}

enum CompressionMode: Equatable {
    /// Aim at this many bytes in total.
    case targetSize(bytes: Int64)
    /// 0 (smallest) ... 1 (best looking).
    case quality(Double)
}

enum FPSChoice: String, CaseIterable, Identifiable {
    case original, fps60, fps30, fps24
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return "Original"
        case .fps60: return "60 fps"
        case .fps30: return "30 fps"
        case .fps24: return "24 fps"
        }
    }
    var cap: Double? {
        switch self {
        case .original: return nil
        case .fps60: return 60
        case .fps30: return 30
        case .fps24: return 24
        }
    }
}

enum AudioChoice: String, CaseIterable, Identifiable {
    case keep, reduced, mute
    var id: String { rawValue }
    var title: String {
        switch self {
        case .keep: return "Keep"
        case .reduced: return "Smaller"
        case .mute: return "Mute"
        }
    }
    var bitrate: Int? {
        switch self {
        case .keep: return 128_000
        case .reduced: return 64_000
        case .mute: return nil
        }
    }
}

/// Everything the person can change on the setup screen.
struct CompressionSettings: Equatable {
    var mode: CompressionMode = .quality(0.55)
    var presetID: String? = nil
    /// nil = keep the original size.
    var maxLongSide: Int? = nil
    var fps: FPSChoice = .original
    var codec: VideoCodec = .h264
    var audio: AudioChoice = .keep
    var stripMetadata: Bool = true
    var trimStart: Double? = nil
    var trimEnd: Double? = nil
}
