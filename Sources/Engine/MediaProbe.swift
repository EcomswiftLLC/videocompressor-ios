import Foundation
import AVFoundation
import UIKit
import CoreMedia

enum MediaProbe {
    /// Reads the facts about a file. AVFoundation first (fast, handles phone videos), then the FFmpeg engine for everything else.
    static func load(url: URL, displayName: String? = nil) async throws -> MediaInfo {
        let name = displayName ?? url.lastPathComponent
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let readable = (try? await asset.load(.isReadable)) ?? false
        if readable {
            if (try? await asset.load(.hasProtectedContent)) == true { throw TranscodeError.protectedContent }
            if let info = try await nativeInfo(asset: asset, url: url, name: name, size: size) { return info }
        }
        if let info = try await FFmpegEngine.probe(url: url, displayName: name, fileSize: size) { return info }
        if FormatSupport.route(forExtension: url.pathExtension) == .unsupported { throw TranscodeError.unsupportedFormat }
        throw TranscodeError.unsupportedFormat
    }

    private static func nativeInfo(asset: AVURLAsset, url: URL, name: String, size: Int64) async throws -> MediaInfo? {
        guard let vTrack = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let aTrack = try await asset.loadTracks(withMediaType: .audio).first
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { return nil }
        let natural = try await vTrack.load(.naturalSize)
        let transform = try await vTrack.load(.preferredTransform)
        let nominal = try await vTrack.load(.nominalFrameRate)
        let estimated = try await vTrack.load(.estimatedDataRate)
        let formats = try await vTrack.load(.formatDescriptions)

        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        var codec = "video"
        var hdr = false
        if let fd = formats.first {
            codec = fourCC(CMFormatDescriptionGetMediaSubType(fd))
            if let tf = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String {
                hdr = tf == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
                    || tf == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
            }
        }
        var audioRate = 0
        if let aTrack { audioRate = Int(try await aTrack.load(.estimatedDataRate)) }
        var videoRate = Int(estimated)
        if videoRate <= 0, size > 0 { videoRate = max(0, Int(Double(size) * 8 / duration) - audioRate) }

        return MediaInfo(
            id: UUID(), url: url, displayName: name, fileSize: size, duration: duration,
            width: Int(abs(rect.width).rounded()), height: Int(abs(rect.height).rounded()),
            fps: Double(nominal) > 1 ? Double(nominal) : 30,
            codecName: codec, hasAudio: aTrack != nil, videoBitrate: videoRate, audioBitrate: audioRate,
            isHDR: hdr, route: .native
        )
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(bytes: bytes, encoding: .macOSRoman)?.trimmingCharacters(in: .whitespaces) ?? "video"
    }

    /// Friendly codec label for chips.
    static func codecLabel(_ name: String) -> String {
        switch name.lowercased() {
        case "avc1", "avc3", "h264": return "H.264"
        case "hvc1", "hev1", "hevc": return "HEVC"
        case "apcn", "apch", "apcs", "apco", "ap4h", "prores": return "ProRes"
        case "mp4v", "mpeg4": return "MPEG-4"
        case "vp8", "vp9", "av1", "av01": return name.uppercased()
        case "jpeg", "mjpeg": return "MJPEG"
        default: return name.uppercased()
        }
    }
}

enum Thumbnailer {
    /// A still from the clip. Native files use AVAssetImageGenerator; FFmpeg-only files use the FFmpeg engine.
    static func image(for info: MediaInfo, at seconds: Double, maxDimension: CGFloat = 640) async -> UIImage? {
        if info.route == .ffmpeg { return await FFmpegEngine.thumbnail(for: info, at: seconds, maxDimension: maxDimension) }
        let asset = AVURLAsset(url: info.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let time = CMTime(seconds: max(0, min(seconds, max(0, info.duration - 0.1))), preferredTimescale: 600)
        do {
            let cg = try await generator.image(at: time).image
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }

    static func image(url: URL, at seconds: Double, maxDimension: CGFloat = 640) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let t = CMTime(seconds: max(0, min(seconds, max(0, duration - 0.1))), preferredTimescale: 600)
        do {
            return UIImage(cgImage: try await generator.image(at: t).image)
        } catch {
            return nil
        }
    }
}
