import Foundation

/// Which engine reads which file type. The picker accepts everything in this list.
enum FormatSupport {
    /// Containers AVFoundation reads on every iPhone and iPad.
    static let nativeExtensions: Set<String> = [
        "mp4", "mov", "m4v", "3gp", "3g2", "heic", "hevc", "qt"
    ]

    /// Containers that need the bundled FFmpeg engine.
    static let ffmpegExtensions: Set<String> = [
        "mkv", "webm", "avi", "wmv", "asf", "flv", "f4v", "mpg", "mpeg", "mpe", "vob", "ts", "m2ts", "mts", "mxf",
        "ogv", "ogg", "rm", "rmvb", "dv", "mjpeg", "mjpg", "gif", "webp", "apng", "divx", "xvid", "m2v", "mp2", "3gpp"
    ]

    static var allExtensions: [String] { Array(nativeExtensions.union(ffmpegExtensions)).sorted() }

    enum Route: Equatable { case native, ffmpeg, unsupported }

    static func route(forExtension ext: String) -> Route {
        let e = ext.lowercased()
        if nativeExtensions.contains(e) { return .native }
        if ffmpegExtensions.contains(e) { return .ffmpeg }
        return .unsupported
    }

    /// Short, honest list for the store page and the in-app formats screen.
    static let promised: [(group: String, formats: String)] = [
        ("Phone and camera", "MP4, MOV, M4V, 3GP, HEVC, ProRes, slo-mo, Cinematic, Live Photo video"),
        ("Computer and download", "MKV, WebM, AVI, WMV, FLV, MPEG, VOB, TS, MTS, MXF"),
        ("Web and old formats", "OGV, RM, DV, GIF, animated WebP, AV1, VP8, VP9")
    ]
}

enum OutputNaming {
    /// "Holiday.mkv" -> "Holiday-shrunk.mp4", unique inside `directory`.
    static func outputURL(for original: String, in directory: URL, container: ContainerKind = .mp4) -> URL {
        let base = (original as NSString).deletingPathExtension
        let clean = sanitized(base.isEmpty ? "Video" : base)
        var candidate = directory.appendingPathComponent("\(clean)-shrunk").appendingPathExtension(container.fileExtension)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(clean)-shrunk-\(n)").appendingPathExtension(container.fileExtension)
            n += 1
        }
        return candidate
    }

    static func sanitized(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = name.components(separatedBy: bad).joined(separator: "_").trimmingCharacters(in: .whitespaces)
        let limited = String(cleaned.prefix(80))
        return limited.isEmpty ? "Video" : limited
    }
}

enum TranscodeError: LocalizedError, Equatable {
    case unsupportedFormat
    case protectedContent
    case noVideoTrack
    case diskFull
    case cancelled
    case codecUnavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "This file type can't be opened. Try another video, or export it as MP4 from the app that made it."
        case .protectedContent:
            return "This video is copy-protected (DRM), so no app can change it. Videos you recorded yourself work fine."
        case .noVideoTrack:
            return "This file has no video in it."
        case .diskFull:
            return "Not enough free space on this device. Free up some storage and try again."
        case .cancelled:
            return "Cancelled."
        case .codecUnavailable(let name):
            return "\(name) isn't available on this device. Choose H.264 instead."
        case .failed(let detail):
            return "The video couldn't be compressed. \(detail)"
        }
    }

    /// Maps framework errors to something a person can act on.
    static func map(_ error: Error) -> TranscodeError {
        if let known = error as? TranscodeError { return known }
        if error is CancellationError { return .cancelled }
        let ns = error as NSError
        if ns.domain == AVFoundationErrorDomainName {
            switch ns.code {
            case -11807, -11808: return .diskFull        // AVError.diskFull / .insufficientSpaceToPerformOperation style codes
            case -11800 where ns.userInfo[NSUnderlyingErrorKey] != nil:
                if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError, under.code == -12780 || under.code == -17913 {
                    return .failed("The video uses a format this device can't process.")
                }
            case -11828, -11829, -11821: return .unsupportedFormat // file format not recognised / cannot open / decoder not found
            default: break
            }
        }
        if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileWriteOutOfSpaceError) { return .diskFull }
        return .failed(ns.localizedDescription)
    }

    static let AVFoundationErrorDomainName = "AVFoundationErrorDomain"
}
