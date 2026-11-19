import XCTest
import AVFoundation
@testable import Shrinkly

/// Runs the real LGPL FFmpeg build on clips AVFoundation cannot open. CI generates the clips and sets
/// TEST_RUNNER_SHRINKLY_FIXTURES; without it these tests skip, so a local run never fails for lack of clips.
final class FFmpegEngineTests: XCTestCase {
    private func fixtureURL(_ name: String) throws -> URL {
        guard let dir = ProcessInfo.processInfo.environment["SHRINKLY_FIXTURES"] else { throw XCTSkip("SHRINKLY_FIXTURES not set") }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("\(name) was not generated") }
        // The simulator app reads straight from the host disk, but copy to the app's temp folder like a real import.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("fx-\(UUID().uuidString)-\(name)")
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    func testLibraryIsTheLGPLBuild() {
        XCTAssertTrue(FFmpegEngine.licenceLine.contains("LGPL"), FFmpegEngine.licenceLine)
        XCTAssertFalse(FFmpegEngine.licenceLine.contains("GPL version 2 or later") && !FFmpegEngine.licenceLine.contains("LGPL"))
        XCTAssertTrue(FFmpegEngine.hasEncoder("h264_videotoolbox"))
        XCTAssertFalse(FFmpegEngine.hasEncoder("libx264"), "GPL encoder must not be present")
        XCTAssertFalse(FFmpegEngine.hasEncoder("libx265"), "GPL encoder must not be present")
        for decoder in ["h264", "hevc", "vp9", "libdav1d", "wmv3", "mpeg4", "theora"] {
            XCTAssertTrue(FFmpegEngine.hasDecoder(decoder), "\(decoder) decoder missing")
        }
    }

    private func roundTrip(_ name: String, expectAudio: Bool = true) async throws {
        let src = try fixtureURL(name)
        let info = try await MediaProbe.load(url: src)
        XCTAssertEqual(info.route, .ffmpeg, "\(name) should be handled by FFmpeg")
        XCTAssertEqual(info.width, 640, name)
        XCTAssertEqual(info.height, 360, name)
        XCTAssertEqual(info.duration, 3, accuracy: 0.6, name)
        XCTAssertEqual(info.hasAudio, expectAudio, name)

        let thumb = await Thumbnailer.image(for: info, at: 1, maxDimension: 200)
        XCTAssertNotNil(thumb, "\(name) thumbnail")

        var settings = CompressionSettings()
        settings.mode = .quality(0.5)
        final class Box: @unchecked Sendable { var last = 0.0 }
        let box = Box()
        let result = try await CompressionRunner.run(info: info, settings: settings, outputDirectory: outputDir()) { box.last = $0.fraction }
        XCTAssertGreaterThan(result.outputBytes, 1_000, name)
        XCTAssertEqual(box.last, 1, accuracy: 0.001, name)

        let asset = AVURLAsset(url: result.outputURL)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 3, accuracy: 0.6, "\(name) output duration")
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(video.count, 1, name)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(!audio.isEmpty, expectAudio, "\(name) output audio")
        if let track = video.first {
            let size = try await track.load(.naturalSize)
            XCTAssertEqual(Int(size.width), 640, name)
            XCTAssertEqual(Int(size.height), 360, name)
        }
    }

    func testMKV() async throws { try await roundTrip("sample.mkv") }
    func testAVI() async throws { try await roundTrip("sample.avi") }
    func testWebM() async throws { try await roundTrip("sample.webm") }
    func testWMV() async throws { try await roundTrip("sample.wmv") }
    func testFLV() async throws { try await roundTrip("sample.flv") }
    func testTransportStream() async throws { try await roundTrip("sample.ts") }
    func testMPEG() async throws { try await roundTrip("sample.mpg") }
    func testOGV() async throws { try await roundTrip("sample.ogv") }

    func testDownscaleAndTrimOnTheFFmpegRoute() async throws {
        let src = try fixtureURL("sample.mkv")
        let info = try await MediaProbe.load(url: src)
        var settings = CompressionSettings()
        settings.maxLongSide = 320
        settings.fps = .fps24
        settings.trimStart = 0.5
        settings.trimEnd = 2.5
        let result = try await CompressionRunner.run(info: info, settings: settings, outputDirectory: outputDir()) { _ in }
        let asset = AVURLAsset(url: result.outputURL)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.6)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(Int(size.width), 320)
        XCTAssertEqual(Int(size.height), 180)
    }

    func testCancelOnTheFFmpegRoute() async throws {
        let src = try fixtureURL("sample.mkv")
        let info = try await MediaProbe.load(url: src)
        let dir = outputDir()
        let task = Task { () -> CompressionResult in
            try await CompressionRunner.run(info: info, settings: CompressionSettings(), outputDirectory: dir) { _ in }
        }
        task.cancel()
        do { _ = try await task.value } catch {
            XCTAssertEqual(TranscodeError.map(error), .cancelled)
            let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            XCTAssertTrue(leftovers.isEmpty, "cancelled job left \(leftovers)")
        }
    }

    func testGarbageWithAVideoExtensionIsRejected() async throws {
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("junk-\(UUID().uuidString).mkv")
        try Data((0..<8192).map { UInt8(($0 * 31) & 0xFF) }).write(to: junk)
        do {
            _ = try await MediaProbe.load(url: junk)
            XCTFail("junk must not open")
        } catch {
            XCTAssertEqual(TranscodeError.map(error), .unsupportedFormat)
        }
    }
}
