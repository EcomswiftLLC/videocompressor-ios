import Foundation
import UIKit

/// FFmpeg-backed engine for files AVFoundation cannot open (MKV, AVI, WebM, WMV, FLV, TS ...).
/// Not wired yet in this build: every call reports the file as unsupported.
final class FFmpegEngine: TranscodeEngine {
    func transcode(_ job: TranscodeJob, progress: @escaping @Sendable (ProgressUpdate) -> Void) async throws -> URL {
        throw TranscodeError.unsupportedFormat
    }

    static func probe(url: URL, displayName: String, fileSize: Int64) async throws -> MediaInfo? {
        nil
    }

    static func thumbnail(for info: MediaInfo, at seconds: Double, maxDimension: CGFloat) async -> UIImage? {
        nil
    }
}
