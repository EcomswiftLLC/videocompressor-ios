import Foundation
import AVFoundation

struct TranscodeJob {
    let info: MediaInfo
    let spec: OutputSpec
    let output: URL
}

struct ProgressUpdate: Equatable {
    /// 0...1 within the current pass.
    var fraction: Double
    /// 1 normally, 2 when the size had to be fine-tuned with a second pass.
    var pass: Int = 1
}

/// One engine turns a source file plus an `OutputSpec` into a finished file. Cancel by cancelling the Task.
protocol TranscodeEngine {
    func transcode(_ job: TranscodeJob, progress: @escaping @Sendable (ProgressUpdate) -> Void) async throws -> URL
}

enum EngineRouter {
    static func engine(for info: MediaInfo) -> TranscodeEngine {
        switch info.route {
        case .native: return NativeEngine()
        case .ffmpeg: return FFmpegEngine()
        }
    }
}

/// Runs the chosen engine and, in target-size mode, fine-tunes the bitrate once when the first pass lands too big.
enum CompressionRunner {
    static func run(
        info: MediaInfo,
        settings: CompressionSettings,
        outputDirectory: URL,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> CompressionResult {
        let resolved = SettingsResolver.resolve(info: info, settings: settings)
        try DiskSpace.ensure(bytes: max(resolved.estimatedBytes * 2, 30_000_000), at: outputDirectory)

        var spec = resolved.spec
        let engine = EngineRouter.engine(for: info)
        let output = OutputNaming.outputURL(for: info.displayName, in: outputDirectory, container: spec.container)

        var targetBytes: Int64? = nil
        if case .targetSize(let b) = settings.mode { targetBytes = b }

        var pass = 1
        var url = try await engine.transcode(TranscodeJob(info: info, spec: spec, output: output)) { p in
            progress(ProgressUpdate(fraction: p.fraction, pass: 1))
        }
        var size = fileSize(url)

        // Size accuracy: a hardware encoder can overshoot a bitrate on hard footage. One corrective pass fixes that.
        if let target = targetBytes, size > Int64(Double(target) * 1.02), !resolved.targetTooSmall, pass == 1 {
            pass = 2
            spec.videoBitrate = SizeEstimator.correctedBitrate(current: spec.videoBitrate, actualBytes: size, targetBytes: target)
            let second = OutputNaming.outputURL(for: info.displayName + "-b", in: outputDirectory, container: spec.container)
            let retry = try await engine.transcode(TranscodeJob(info: info, spec: spec, output: second)) { p in
                progress(ProgressUpdate(fraction: p.fraction, pass: 2))
            }
            let retrySize = fileSize(retry)
            if retrySize > 0 && retrySize < size {
                try? FileManager.default.removeItem(at: url)
                let finalURL = OutputNaming.outputURL(for: info.displayName, in: outputDirectory, container: spec.container)
                try? FileManager.default.moveItem(at: retry, to: finalURL)
                url = FileManager.default.fileExists(atPath: finalURL.path) ? finalURL : retry
                size = retrySize
            } else {
                try? FileManager.default.removeItem(at: retry)
            }
        }
        return CompressionResult(
            id: UUID(), sourceName: info.displayName, outputURL: url,
            originalBytes: info.fileSize, outputBytes: size,
            width: spec.width, height: spec.height, codec: spec.codec, passes: pass,
            targetBytes: targetBytes
        )
    }

    static func fileSize(_ url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(v?.fileSize ?? 0)
    }
}

struct CompressionResult: Identifiable, Equatable {
    let id: UUID
    let sourceName: String
    let outputURL: URL
    let originalBytes: Int64
    let outputBytes: Int64
    let width: Int
    let height: Int
    let codec: VideoCodec
    let passes: Int
    let targetBytes: Int64?

    var savedBytes: Int64 { max(0, originalBytes - outputBytes) }
    var savedPercent: Int { SizeEstimator.savedPercent(original: originalBytes, now: outputBytes) }
    /// Within 5% of the requested size (or below it).
    var metTarget: Bool {
        guard let t = targetBytes else { return true }
        return Double(outputBytes) <= Double(t) * 1.05
    }
}

enum DiskSpace {
    static func available(at url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let cap = v?.volumeAvailableCapacityForImportantUsage { return cap }
        return Int64.max
    }

    static func ensure(bytes: Int64, at url: URL) throws {
        if available(at: url) < bytes { throw TranscodeError.diskFull }
    }
}
