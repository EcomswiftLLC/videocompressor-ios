import XCTest
import AVFoundation
@testable import Shrinkly

/// Runs the real AVFoundation engine on generated clips in the simulator.
final class NativeEngineTests: XCTestCase {
    private func probe(_ url: URL) async throws -> MediaInfo { try await MediaProbe.load(url: url) }

    private func verify(_ url: URL, duration: Double, tolerance: Double = 0.4, width: Int? = nil, height: Int? = nil, audio: Bool, codec: String? = nil, file: StaticString = #filePath, line: UInt = #line) async throws {
        let asset = AVURLAsset(url: url)
        let d = try await asset.load(.duration).seconds
        XCTAssertEqual(d, duration, accuracy: tolerance, "duration", file: file, line: line)
        let v = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(v.count, 1, "video track", file: file, line: line)
        let a = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(!a.isEmpty, audio, "audio track", file: file, line: line)
        if let track = v.first {
            let size = try await track.load(.naturalSize)
            let t = try await track.load(.preferredTransform)
            let rect = CGRect(origin: .zero, size: size).applying(t)
            if let width { XCTAssertEqual(Int(abs(rect.width).rounded()), width, "width", file: file, line: line) }
            if let height { XCTAssertEqual(Int(abs(rect.height).rounded()), height, "height", file: file, line: line) }
            if let codec, let fd = try await track.load(.formatDescriptions).first {
                XCTAssertEqual(MediaProbe.fourCC(CMFormatDescriptionGetMediaSubType(fd)), codec, "codec", file: file, line: line)
            }
        }
    }

    func testProbeReadsGeneratedClip() async throws {
        let src = try await SyntheticVideo.make(.init(duration: 4, name: "probe"))
        let info = try await probe(src)
        XCTAssertEqual(info.width, 1280); XCTAssertEqual(info.height, 720)
        XCTAssertEqual(info.duration, 4, accuracy: 0.3)
        XCTAssertTrue(info.hasAudio)
        XCTAssertEqual(info.route, .native)
        XCTAssertEqual(MediaProbe.codecLabel(info.codecName), "H.264")
        XCTAssertGreaterThan(info.fileSize, 0)
    }

    func testTargetSizeIsMetWithinFivePercent() async throws {
        let src = try await SyntheticVideo.make(.init(duration: 8, name: "target"))
        let info = try await probe(src)
        var settings = CompressionSettings()
        settings.mode = .targetSize(bytes: 1_500_000)
        settings.audio = .reduced
        let result = try await CompressionRunner.run(info: info, settings: settings, outputDirectory: outputDir()) { _ in }
        XCTAssertLessThanOrEqual(Double(result.outputBytes), 1_500_000 * 1.05, "output \(result.outputBytes) bytes after \(result.passes) pass(es)")
        XCTAssertGreaterThan(result.outputBytes, 400_000, "should not collapse far below the target")
        XCTAssertLessThan(result.outputBytes, info.fileSize)
        try await verify(result.outputURL, duration: 8, audio: true, codec: "avc1")
    }

    func testQualityModeShrinksAndKeepsTracks() async throws {
        let src = try await SyntheticVideo.make(.init(duration: 5, name: "quality"))
        let info = try await probe(src)
        var settings = CompressionSettings()
        settings.mode = .quality(0.3)
        let result = try await CompressionRunner.run(info: info, settings: settings, outputDirectory: outputDir()) { _ in }
        XCTAssertLessThan(result.outputBytes, info.fileSize)
        try await verify(result.outputURL, duration: 5, width: 1280, height: 720, audio: true)
    }

    func testDownscaleAndFPSCap() async throws {
        let src = try await SyntheticVideo.make(.init(duration: 4, width: 1920, height: 1080, fps: 30, name: "scale"))
        let info = try await probe(src)
        var settings = CompressionSettings()
        settings.maxLongSide = 640
        settings.fps = .fps24
        let result = try await CompressionRunner.run(info: info, settings: settings, outputDirectory: outputDir()) { _ in }
        try await verify(result.outputURL, duration: 4, width: 640, height: 360, audio: true)
        let track = try await AVURLAsset(url: result.outputURL).loadTracks(withMediaType: .video).first!
        let fps = try await track.load(.nominalFrameRate)
        XCTAssertEqual(Double(fps), 24, accuracy: 1.5)
    }

    func testMuteDropsAudio() async throws {
        let src = try await SyntheticVideo.make(.init(duration: 3, name: "mute"))
        let info = try await probe(src)
        var settings = CompressionSettings()
        settings.audio = .mute
        let result = try await CompressionRunner.run(info: info, settings: settings, outputDirectory: outputDir()) { _ in }
        try await verify(result.outputURL, duration: 3, audio: false)
    }

    func testTrimShortensOutput() async throws {
        let src = try await SyntheticVideo.make(.init(duration: 8, name: "trim"))
        let info = try await probe(src)
        var settings = CompressionSettings()
        settings.trimStart = 2
        settings.trimEnd = 5
        let result = try await CompressionRunner.run(info: info, settings: settings, outputDirectory: outputDir()) { _ in }
        try await verify(result.outputURL, duration: 3, tolerance: 0.6, audio: true)
    }

    func testPortraitClipKeepsOrientation() async throws {
        // Stored 1280x720 with a 90 degree rotation: appears as 720x1280.
        let src = try await SyntheticVideo.make(.init(duration: 3, rotated90: true, name: "portrait"))
        let info = try await probe(src)
        XCTAssertEqual(info.width, 720); XCTAssertEqual(info.height, 1280)
        var settings = CompressionSettings()
        settings.maxLongSide = 640
        let result = try await CompressionRunner.run(info: info, settings: settings, outputDirectory: outputDir()) { _ in }
        try await verify(result.outputURL, duration: 3, width: 360, height: 640, audio: true)
    }

    func testHEVCOutputWhenAvailable() async throws {
        let src = try await SyntheticVideo.make(.init(duration: 3, name: "hevc"))
        let info = try await probe(src)
        var settings = CompressionSettings()
        settings.codec = .hevc
        do {
            let result = try await CompressionRunner.run(info: info, settings: settings, outputDirectory: outputDir()) { _ in }
            try await verify(result.outputURL, duration: 3, audio: true, codec: "hvc1")
        } catch let e as TranscodeError {
            // A device or simulator without an HEVC encoder reports it clearly instead of crashing.
            guard case .codecUnavailable = e else { throw e }
        }
    }

    func testCancelStopsAndRemovesOutput() async throws {
        let src = try await SyntheticVideo.make(.init(duration: 30, name: "cancel"))
        let info = try await probe(src)
        let dir = outputDir()
        let task = Task { () -> CompressionResult in
            try await CompressionRunner.run(info: info, settings: CompressionSettings(), outputDirectory: dir) { _ in }
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        task.cancel()
        do {
            _ = try await task.value
            // A fast machine may finish before the cancel lands; that is fine, nothing may be left half-written then.
        } catch {
            XCTAssertEqual(TranscodeError.map(error), .cancelled)
            let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            XCTAssertTrue(leftovers.isEmpty, "cancelled job left \(leftovers)")
        }
    }

    func testProgressIsReportedMonotonic() async throws {
        let src = try await SyntheticVideo.make(.init(duration: 6, name: "progress"))
        let info = try await probe(src)
        final class Box: @unchecked Sendable { var values: [Double] = [] }
        let box = Box()
        _ = try await CompressionRunner.run(info: info, settings: CompressionSettings(), outputDirectory: outputDir()) { box.values.append($0.fraction) }
        XCTAssertFalse(box.values.isEmpty)
        XCTAssertEqual(box.values, box.values.sorted())
        XCTAssertEqual(box.values.last ?? 0, 1, accuracy: 0.001)
    }

    func testCompressingAnAlreadySmallClipDoesNotGrowIt() async throws {
        let src = try await SyntheticVideo.make(.init(duration: 4, bitrate: 600_000, name: "small"))
        let info = try await probe(src)
        var settings = CompressionSettings()
        settings.mode = .quality(1.0)
        let result = try await CompressionRunner.run(info: info, settings: settings, outputDirectory: outputDir()) { _ in }
        XCTAssertLessThanOrEqual(Double(result.outputBytes), Double(info.fileSize) * 1.15)
    }

    func testUnreadableFileIsRejectedWithAClearError() async throws {
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("junk-\(UUID().uuidString).mp4")
        try Data(repeating: 7, count: 4096).write(to: junk)
        do {
            _ = try await MediaProbe.load(url: junk)
            XCTFail("junk file should not open")
        } catch {
            XCTAssertEqual(TranscodeError.map(error), .unsupportedFormat)
        }
    }

    func testDiskSpaceGuard() {
        XCTAssertThrowsError(try DiskSpace.ensure(bytes: Int64.max - 1, at: FileManager.default.temporaryDirectory)) { error in
            XCTAssertEqual(error as? TranscodeError, .diskFull)
        }
    }
}
