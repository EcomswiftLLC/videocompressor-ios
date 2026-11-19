import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia

/// AVAssetReader + AVAssetWriter engine: hardware H.264 / HEVC, streams frame by frame (never loads a file into memory).
final class NativeEngine: TranscodeEngine {
    func transcode(_ job: TranscodeJob, progress: @escaping @Sendable (ProgressUpdate) -> Void) async throws -> URL {
        let session = NativeSession(job: job, progress: progress)
        return try await withTaskCancellationHandler {
            do {
                return try await session.run()
            } catch {
                session.removeOutput()
                throw TranscodeError.map(error)
            }
        } onCancel: {
            session.cancel()
        }
    }
}

final class NativeSession: @unchecked Sendable {
    private let job: TranscodeJob
    private let progress: @Sendable (ProgressUpdate) -> Void
    private let lock = NSLock()
    private var cancelledFlag = false
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var lastReported: Double = -1

    init(job: TranscodeJob, progress: @escaping @Sendable (ProgressUpdate) -> Void) {
        self.job = job
        self.progress = progress
    }

    func cancel() {
        lock.lock()
        cancelledFlag = true
        let r = reader
        let w = writer
        lock.unlock()
        r?.cancelReading()
        w?.cancelWriting()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelledFlag
    }

    /// Removes the output and the writer's hidden ".sb-" scratch file, which can outlive a cancelled write for a moment.
    func removeOutput() {
        let fm = FileManager.default
        let dir = job.output.deletingLastPathComponent()
        let prefix = job.output.lastPathComponent + ".sb-"
        // Sweep, give the writer a moment to finish tearing down, sweep again.
        for pass in 0..<3 {
            try? fm.removeItem(at: job.output)
            let scratch = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(prefix) }
            for name in scratch { try? fm.removeItem(at: dir.appendingPathComponent(name)) }
            if pass < 2 { Thread.sleep(forTimeInterval: 0.15) }
        }
    }

    func run() async throws -> URL {
        if isCancelled { throw TranscodeError.cancelled }
        let info = job.info
        let spec = job.spec

        let asset = AVURLAsset(url: info.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard try await asset.load(.isReadable) else { throw TranscodeError.unsupportedFormat }
        if try await asset.load(.hasProtectedContent) { throw TranscodeError.protectedContent }
        guard let vTrack = try await asset.loadTracks(withMediaType: .video).first else { throw TranscodeError.noVideoTrack }
        let aTrack = try await asset.loadTracks(withMediaType: .audio).first
        let assetDuration = try await asset.load(.duration)
        let natural = try await vTrack.load(.naturalSize)
        let transform = try await vTrack.load(.preferredTransform)

        // MARK: video composition (scale, rotate, frame rate, colour) done by the system on the GPU.
        let oriented = CGRect(origin: .zero, size: natural).applying(transform)
        let ow = max(1, abs(oriented.width))
        let oh = max(1, abs(oriented.height))
        var t = transform.concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
        t = t.concatenating(CGAffineTransform(scaleX: CGFloat(spec.width) / ow, y: CGFloat(spec.height) / oh))

        let comp = AVMutableVideoComposition()
        comp.renderSize = CGSize(width: spec.width, height: spec.height)
        comp.frameDuration = Self.frameDuration(for: spec.fps)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: assetDuration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
        layer.setTransform(t, at: .zero)
        instruction.layerInstructions = [layer]
        comp.instructions = [instruction]
        let convertHDR = info.isHDR && spec.convertHDRToSDR
        if convertHDR {
            comp.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            comp.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
            comp.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        }

        // MARK: reader
        let reader = try AVAssetReader(asset: asset)
        var startSeconds = 0.0
        var span = assetDuration.seconds
        if let trim = spec.trim {
            startSeconds = trim.lowerBound
            span = trim.upperBound - trim.lowerBound
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: trim.lowerBound, preferredTimescale: 600),
                duration: CMTime(seconds: span, preferredTimescale: 600)
            )
        }
        let vOut = AVAssetReaderVideoCompositionOutput(
            videoTracks: [vTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        vOut.videoComposition = comp
        vOut.alwaysCopiesSampleData = false
        guard reader.canAdd(vOut) else { throw TranscodeError.failed("The video track can't be read.") }
        reader.add(vOut)

        var audioOut: AVAssetReaderAudioMixOutput?
        var audioSettings: [String: Any]?
        if case .keep(let bitrate) = spec.audio, let aTrack {
            let formats = try await aTrack.load(.formatDescriptions)
            var channels = 2
            var sampleRate = 44_100.0
            if let fd = formats.first, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
                channels = max(1, min(2, Int(asbd.mChannelsPerFrame)))
                sampleRate = asbd.mSampleRate > 46_000 ? 48_000 : 44_100
            }
            let pcm: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let out = AVAssetReaderAudioMixOutput(audioTracks: [aTrack], audioSettings: pcm)
            out.alwaysCopiesSampleData = false
            if reader.canAdd(out) {
                reader.add(out)
                audioOut = out
                audioSettings = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: channels == 1 ? min(bitrate, 96_000) : bitrate
                ]
            }
        }

        // MARK: writer
        try? FileManager.default.removeItem(at: job.output)
        let writer = try AVAssetWriter(outputURL: job.output, fileType: spec.container == .mp4 ? .mp4 : .mov)
        writer.shouldOptimizeForNetworkUse = true

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: spec.videoBitrate,
            AVVideoExpectedSourceFrameRateKey: Int(spec.fps.rounded()),
            AVVideoMaxKeyFrameIntervalDurationKey: 2
        ]
        if spec.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            compression[AVVideoAllowFrameReorderingKey] = true
        } else {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
        }
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: spec.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: spec.width,
            AVVideoHeightKey: spec.height,
            AVVideoCompressionPropertiesKey: compression
        ]
        if convertHDR {
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        }
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw spec.codec == .hevc ? TranscodeError.codecUnavailable("HEVC") : TranscodeError.failed("This device can't encode these settings.")
        }
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(vIn) else { throw TranscodeError.failed("The output video track can't be created.") }
        writer.add(vIn)

        var aIn: AVAssetWriterInput?
        if let audioSettings, audioOut != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                aIn = input
            } else {
                // Rare: audio settings rejected. Ship the video without sound rather than fail.
                audioOut = nil
            }
        }
        if !spec.stripMetadata {
            if let items = try? await asset.load(.metadata) { writer.metadata = items }
        }

        lock.lock()
        self.reader = reader
        self.writer = writer
        lock.unlock()
        if isCancelled { throw TranscodeError.cancelled }

        guard writer.startWriting() else { throw TranscodeError.map(writer.error ?? TranscodeError.failed("Writing could not start.")) }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw TranscodeError.map(reader.error ?? TranscodeError.failed("Reading could not start."))
        }
        writer.startSession(atSourceTime: CMTime(seconds: startSeconds, preferredTimescale: 600))

        // MARK: pump samples
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            pump(input: vIn, output: vOut, label: "shrinkly.video", group: group, isVideo: true, start: startSeconds, span: span)
            if let aIn, let audioOut {
                pump(input: aIn, output: audioOut, label: "shrinkly.audio", group: group, isVideo: false, start: startSeconds, span: span)
            }
            group.notify(queue: .global(qos: .userInitiated)) { cont.resume() }
        }

        if isCancelled {
            writer.cancelWriting()
            reader.cancelReading()
            throw TranscodeError.cancelled
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw TranscodeError.map(reader.error ?? TranscodeError.failed("Reading failed."))
        }
        if writer.status == .failed {
            throw TranscodeError.map(writer.error ?? TranscodeError.failed("Writing failed."))
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw TranscodeError.map(writer.error ?? TranscodeError.failed("Writing did not finish."))
        }
        progress(ProgressUpdate(fraction: 1))
        return job.output
    }

    private func pump(
        input: AVAssetWriterInput,
        output: AVAssetReaderOutput,
        label: String,
        group: DispatchGroup,
        isVideo: Bool,
        start: Double,
        span: Double
    ) {
        group.enter()
        let queue = DispatchQueue(label: label)
        var finished = false
        input.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self else { return }
            if finished { return }
            while input.isReadyForMoreMediaData {
                if self.isCancelled {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
                guard let sample = output.copyNextSampleBuffer() else {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
                if isVideo, span > 0 {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    self.report((pts - start) / span)
                }
                if !input.append(sample) {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
    }

    private func report(_ raw: Double) {
        let f = min(0.999, max(0, raw))
        lock.lock()
        let shouldSend = f - lastReported >= 0.004
        if shouldSend { lastReported = f }
        lock.unlock()
        if shouldSend { progress(ProgressUpdate(fraction: f)) }
    }

    static func frameDuration(for fps: Double) -> CMTime {
        switch fps {
        case 29.9..<30.0: return CMTime(value: 1001, timescale: 30_000)
        case 23.9..<24.0: return CMTime(value: 1001, timescale: 24_000)
        case 59.9..<60.0: return CMTime(value: 1001, timescale: 60_000)
        default: return CMTime(value: 1, timescale: CMTimeScale(max(1, Int(fps.rounded()))))
        }
    }
}
