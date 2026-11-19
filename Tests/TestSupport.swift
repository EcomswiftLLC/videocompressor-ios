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
        for i in 0..<frames {
            while !vIn.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
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
        }
        vIn.markAsFinished()

        if let aIn { try await writeTone(into: aIn, seconds: o.duration) }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "test", code: 2) }
        return url
    }

    private static func writeTone(into input: AVAssetWriterInput, seconds: Double) async throws {
        let rate = 44_100
        var asbd = AudioStreamBasicDescription(mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
                                               mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { return }
        let chunk = 4096
        var written = 0
        let total = Int(seconds * Double(rate))
        while written < total {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            let n = min(chunk, total - written)
            var samples = [Int16](repeating: 0, count: n)
            for k in 0..<n { samples[k] = Int16(8000 * sin(2 * Double.pi * 440 * Double(written + k) / Double(rate))) }
            let bytes = n * 2
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
                                               offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
            guard let block else { return }
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
        input.markAsFinished()
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
