import Foundation
import UIKit

/// Owns the one integer the C code polls to know it should stop. Freed only after the C call returned.
final class FFCancelFlag: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<Int32>
    init() {
        pointer = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        pointer.initialize(to: 0)
    }
    func cancel() { pointer.pointee = 1 }
    deinit { pointer.deallocate() }
}

private final class FFProgressBox {
    let callback: (Double) -> Void
    init(_ callback: @escaping (Double) -> Void) { self.callback = callback }
}

/// FFmpeg-backed engine (LGPL build, in process) for files AVFoundation cannot open: MKV, AVI, WebM, WMV, FLV, TS ...
/// Decodes in software, encodes with the same hardware H.264 / HEVC encoders as the native engine.
final class FFmpegEngine: TranscodeEngine {
    func transcode(_ job: TranscodeJob, progress: @escaping @Sendable (ProgressUpdate) -> Void) async throws -> URL {
        let flag = FFCancelFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(with: Result { try Self.run(job, flag: flag, progress: progress) })
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }

    private static func run(_ job: TranscodeJob, flag: FFCancelFlag, progress: @escaping @Sendable (ProgressUpdate) -> Void) throws -> URL {
        try? FileManager.default.removeItem(at: job.output)
        let spec = job.spec
        var audioBitrate: Int64 = 0
        if case .keep(let b) = spec.audio, job.info.hasAudio { audioBitrate = Int64(b) }
        var errorBuffer = [CChar](repeating: 0, count: 256)
        let box = FFProgressBox { f in progress(ProgressUpdate(fraction: f)) }
        let context = Unmanaged.passRetained(box)
        defer { context.release() }

        let result: Int32 = job.info.url.path.withCString { input in
            job.output.path.withCString { output in
                var params = ShkParams(
                    input: input, output: output,
                    width: Int32(spec.width), height: Int32(spec.height), fps: spec.fps,
                    video_bitrate: Int64(spec.videoBitrate), audio_bitrate: audioBitrate,
                    hevc: spec.codec == .hevc ? 1 : 0,
                    trim_start: spec.trim?.lowerBound ?? 0, trim_end: spec.trim?.upperBound ?? 0,
                    strip_metadata: spec.stripMetadata ? 1 : 0
                )
                return shk_transcode(&params, { fraction, ctx in
                    guard let ctx else { return }
                    Unmanaged<FFProgressBox>.fromOpaque(ctx).takeUnretainedValue().callback(fraction)
                }, context.toOpaque(), flag.pointer, &errorBuffer, Int32(errorBuffer.count))
            }
        }
        if result == 1 {
            try? FileManager.default.removeItem(at: job.output)
            throw TranscodeError.cancelled
        }
        if result != 0 {
            try? FileManager.default.removeItem(at: job.output)
            let message = String(cString: errorBuffer)
            if message.contains("can't be decoded") { throw TranscodeError.unsupportedFormat }
            if message.contains("hardware video encoder") { throw TranscodeError.codecUnavailable(spec.codec == .hevc ? "HEVC" : "H.264") }
            throw TranscodeError.failed(message.isEmpty ? "Unknown error \(result)." : message + ".")
        }
        progress(ProgressUpdate(fraction: 1))
        return job.output
    }

    // MARK: probe and thumbnail

    static func probe(url: URL, displayName: String, fileSize: Int64) async throws -> MediaInfo? {
        await withCheckedContinuation { (cont: CheckedContinuation<MediaInfo?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var probe = ShkProbe()
                let code = url.path.withCString { shk_probe($0, &probe) }
                guard code == 0, probe.ok != 0 else { cont.resume(returning: nil); return }
                let codec = withUnsafePointer(to: &probe.video_codec) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 32) { String(cString: $0) }
                }
                let duration = probe.duration > 0 ? probe.duration : 0
                var vRate = Int(probe.video_bitrate)
                if vRate <= 0, duration > 0, fileSize > 0 { vRate = max(0, Int(Double(fileSize) * 8 / duration) - Int(probe.audio_bitrate)) }
                cont.resume(returning: MediaInfo(
                    id: UUID(), url: url, displayName: displayName, fileSize: fileSize, duration: duration,
                    width: Int(probe.width), height: Int(probe.height), fps: probe.fps > 1 ? probe.fps : 30,
                    codecName: codec, hasAudio: probe.has_audio != 0, videoBitrate: vRate, audioBitrate: Int(probe.audio_bitrate),
                    isHDR: probe.is_hdr != 0, route: .ffmpeg
                ))
            }
        }
    }

    static func thumbnail(for info: MediaInfo, at seconds: Double, maxDimension: CGFloat) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var rgba: UnsafeMutablePointer<UInt8>? = nil
                var w: Int32 = 0
                var h: Int32 = 0
                let code = info.url.path.withCString { shk_thumbnail($0, seconds, Int32(maxDimension), &rgba, &w, &h) }
                guard code == 0, let rgba else { cont.resume(returning: nil); return }
                let data = Data(bytes: rgba, count: Int(w) * Int(h) * 4)
                shk_free(rgba)
                let provider = CGDataProvider(data: data as CFData)
                let image = provider.flatMap {
                    CGImage(width: Int(w), height: Int(h), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(w) * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: $0, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                }
                cont.resume(returning: image.map { UIImage(cgImage: $0) })
            }
        }
    }

    /// For the licences screen and tests.
    static var licenceLine: String { String(cString: shk_license()) }
    static func hasEncoder(_ name: String) -> Bool { shk_has_encoder(name) != 0 }
    static func hasDecoder(_ name: String) -> Bool { shk_has_decoder(name) != 0 }
}
