import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreGraphics
import XCTest
@testable import Shrinkly

/// Generates license-free test clips on the fly (moving shapes plus noise, optional sine audio).
enum SyntheticVideo {
    struct Options {
        var duration: Double = 6
        var width: Int = 1280
        var height: Int = 720
        var fps: Int = 30
        var audio: Bool = true
        /// Portrait phone clips are stored sideways with a rotation transform.
        var rotated90: Bool = false
        var bitrate: Int = 8_000_000
        var name: String = "synthetic"
    }

    static func make(_ o: Options = Options()) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ShrinklyTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(o.name)-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let vSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: o.width, AVVideoHeightKey: o.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: o.bitrate]
        ]
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vIn.expectsMediaDataInRealTime = false
        if o.rotated90 { vIn.transform = CGAffineTransform(rotationAngle: .pi / 2) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vIn,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                          kCVPixelBufferWidthKey as String: o.width, kCVPixelBufferHeightKey as String: o.height]
        )
        writer.add(vIn)
        var aIn: AVAssetWriterInput?
        if o.audio {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000
            ])
            a.expectsMediaDataInRealTime = false
            writer.add(a)
            aIn = a
        }
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "test", code: 1) }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(o.duration * Double(o.fps))
        // Audio must be appended in step with video: AVAssetWriter interleaves the tracks and stops accepting video
        // once its audio input is far behind, so writing all video first deadlocks.
        let tone = aIn.map { ToneFeeder(input: $0, seconds: o.duration) }
        for i in 0..<frames {
            var waited = 0
            while !vIn.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
                waited += 1
                if waited > 10_000 { throw NSError(domain: "test", code: 5, userInfo: [NSLocalizedDescriptionKey: "video writer stalled"]) }
            }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, o.width, o.height, kCVPixelFormatType_32BGRA, nil, &pb)
            guard let buffer = pb else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: o.width, height: o.height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                let t = Double(i) / Double(o.fps)
                ctx.setFillColor(CGColor(red: 0.1 + 0.4 * (0.5 + 0.5 * sin(t)), green: 0.25, blue: 0.4, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: o.width, height: o.height))
                for _ in 0..<60 {
                    let x = CGFloat(Int.random(in: 0..<o.width)), y = CGFloat(Int.random(in: 0..<o.height))
                    ctx.setFillColor(CGColor(red: .random(in: 0...1), green: .random(in: 0...1), blue: .random(in: 0...1), alpha: 1))
                    ctx.fill(CGRect(x: x, y: y, width: 40, height: 24))
                }
                ctx.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.2, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: CGFloat(o.width) * CGFloat(0.5 + 0.4 * sin(t * 2)) - 60, y: CGFloat(o.height) / 2 - 60, width: 120, height: 120))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(o.fps)))
            try await tone?.feed(upTo: Double(i + 1) / Double(o.fps))
        }
        vIn.markAsFinished()
        try await tone?.finish()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "test", code: 2) }
        return url
    }

    /// Produces a 440 Hz tone and hands it to the audio input a little at a time.
    private final class ToneFeeder {
        let input: AVAssetWriterInput
        let total: Int
        let rate = 44_100
        var written = 0
        var format: CMAudioFormatDescription?

        init(input: AVAssetWriterInput, seconds: Double) {
            self.input = input
            self.total = Int(seconds * 44_100)
            var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                                                   mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                                   mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
                                                   mBitsPerChannel: 16, mReserved: 0)
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        }

        func feed(upTo seconds: Double) async throws {
            let target = min(total, Int(seconds * Double(rate)))
            let chunk = 4096
            while written < target {
                var waited = 0
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 2_000_000)
                    waited += 1
                    if waited > 5_000 { return }   // 10 s: the writer wants video first; the next call retries
                }
                try append(min(chunk, target - written))
            }
        }

        func finish() async throws {
            try await feed(upTo: Double(total) / Double(rate))
            input.markAsFinished()
        }

        private func append(_ n: Int) throws {
            guard let format else { throw NSError(domain: "test", code: 3) }
            var samples = [Int16](repeating: 0, count: n)
            for k in 0..<n { samples[k] = Int16(8000 * sin(2 * Double.pi * 440 * Double(written + k) / Double(rate))) }
            let bytes = n * 2
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
                                               offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
            guard let block else { throw NSError(domain: "test", code: 4) }
            samples.withUnsafeBytes { raw in
                _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
            }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: n,
                presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(rate)),
                packetDescriptions: nil, sampleBufferOut: &sample)
            if let sample { input.append(sample) }
            written += n
        }
    }
}

func fileBytes(_ url: URL) -> Int64 {
    Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
}

func outputDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("ShrinklyTestOut-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}
