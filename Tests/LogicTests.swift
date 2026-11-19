import XCTest
@testable import Shrinkly

final class SizeEstimatorTests: XCTestCase {
    func testVideoBitrateForTarget() {
        // 10 MB over 60 s with 64 kbps audio.
        let v = SizeEstimator.videoBitrate(forTargetBytes: 10_000_000, duration: 60, audioBitrate: 64_000)
        let predicted = SizeEstimator.estimatedBytes(videoBitrate: v, audioBitrate: 64_000, duration: 60)
        XCTAssertLessThanOrEqual(predicted, 10_000_000)
        XCTAssertGreaterThan(predicted, 9_000_000)
    }

    func testBitrateFloor() {
        let v = SizeEstimator.videoBitrate(forTargetBytes: 10_000, duration: 600, audioBitrate: 128_000)
        XCTAssertEqual(v, SizeEstimator.minVideoBitrate)
    }

    func testZeroDurationDoesNotCrash() {
        XCTAssertEqual(SizeEstimator.videoBitrate(forTargetBytes: 1_000_000, duration: 0, audioBitrate: 0), SizeEstimator.minVideoBitrate)
        XCTAssertEqual(SizeEstimator.estimatedBytes(videoBitrate: 1_000_000, audioBitrate: 0, duration: 0), 0)
    }

    func testQualityMonotonic() {
        var last = 0
        for q in stride(from: 0.0, through: 1.0, by: 0.1) {
            let b = SizeEstimator.qualityBitrate(width: 1920, height: 1080, fps: 30, codec: .h264, quality: q)
            XCTAssertGreaterThanOrEqual(b, last)
            last = b
        }
    }

    func testHEVCUsesFewerBits() {
        let h264 = SizeEstimator.qualityBitrate(width: 1920, height: 1080, fps: 30, codec: .h264, quality: 0.6)
        let hevc = SizeEstimator.qualityBitrate(width: 1920, height: 1080, fps: 30, codec: .hevc, quality: 0.6)
        XCTAssertLessThan(hevc, h264)
    }

    func testScaledSizeIsEvenAndNeverUpscales() {
        let a = SizeEstimator.scaledSize(width: 3840, height: 2160, maxLongSide: 1280)
        XCTAssertEqual(a.width, 1280); XCTAssertEqual(a.height, 720)
        let b = SizeEstimator.scaledSize(width: 1080, height: 1920, maxLongSide: 1280)
        XCTAssertEqual(b.height, 1280); XCTAssertEqual(b.width % 2, 0)
        let c = SizeEstimator.scaledSize(width: 640, height: 360, maxLongSide: 1920)
        XCTAssertEqual(c.width, 640); XCTAssertEqual(c.height, 360)
        let d = SizeEstimator.scaledSize(width: 1001, height: 563, maxLongSide: nil)
        XCTAssertEqual(d.width % 2, 0); XCTAssertEqual(d.height % 2, 0)
    }

    func testOutputFPS() {
        XCTAssertEqual(SizeEstimator.outputFPS(sourceFPS: 60, cap: 30), 30)
        XCTAssertEqual(SizeEstimator.outputFPS(sourceFPS: 24, cap: 30), 24)
        XCTAssertEqual(SizeEstimator.outputFPS(sourceFPS: 29.97, cap: 30), 29.97)
        XCTAssertEqual(SizeEstimator.outputFPS(sourceFPS: 0, cap: nil), 30)
    }

    func testCorrectedBitrateShrinksWhenOvershooting() {
        let corrected = SizeEstimator.correctedBitrate(current: 2_000_000, actualBytes: 12_000_000, targetBytes: 10_000_000)
        XCTAssertLessThan(corrected, 2_000_000)
        XCTAssertGreaterThan(corrected, 1_500_000)
    }

    func testSavedPercent() {
        XCTAssertEqual(SizeEstimator.savedPercent(original: 100, now: 13), 87)
        XCTAssertEqual(SizeEstimator.savedPercent(original: 100, now: 200), 0)
        XCTAssertEqual(SizeEstimator.savedPercent(original: 0, now: 0), 0)
    }

    func testTargetRangeIsOrdered() {
        let r = SizeEstimator.targetRange(duration: 30, sourceBytes: 100_000_000, audioBitrate: 64_000)
        XCTAssertLessThan(r.lowerBound, r.upperBound)
        XCTAssertEqual(r.upperBound, 100_000_000)
    }
}

final class ResolverTests: XCTestCase {
    private func info(duration: Double = 60, width: Int = 1920, height: Int = 1080, bytes: Int64 = 200_000_000, bitrate: Int = 8_000_000, hasAudio: Bool = true) -> MediaInfo {
        MediaInfo(id: UUID(), url: URL(fileURLWithPath: "/tmp/a.mp4"), displayName: "a.mp4", fileSize: bytes, duration: duration, width: width, height: height,
                  fps: 30, codecName: "avc1", hasAudio: hasAudio, videoBitrate: bitrate, audioBitrate: 128_000, isHDR: false, route: .native)
    }

    func testTargetSizeEstimateIsNearTarget() {
        var s = CompressionSettings()
        s.mode = .targetSize(bytes: 16_000_000)
        s.audio = .reduced
        let r = SettingsResolver.resolve(info: info(), settings: s)
        XCTAssertLessThanOrEqual(r.estimatedBytes, 16_000_000)
        XCTAssertGreaterThan(r.estimatedBytes, 14_000_000)
        XCTAssertFalse(r.alreadySmaller)
    }

    func testAlreadySmallerFlagWhenSourceBitrateIsLow() {
        var s = CompressionSettings()
        s.mode = .targetSize(bytes: 150_000_000)
        let r = SettingsResolver.resolve(info: info(bitrate: 1_000_000), settings: s)
        XCTAssertTrue(r.alreadySmaller)
        XCTAssertLessThan(r.spec.videoBitrate, 1_000_000)
    }

    func testTooSmallTargetIsFlagged() {
        var s = CompressionSettings()
        s.mode = .targetSize(bytes: 200_000)
        let r = SettingsResolver.resolve(info: info(duration: 300), settings: s)
        XCTAssertTrue(r.targetTooSmall)
        XCTAssertEqual(r.spec.videoBitrate, SizeEstimator.minVideoBitrate)
    }

    func testMuteRemovesAudio() {
        var s = CompressionSettings()
        s.audio = .mute
        let r = SettingsResolver.resolve(info: info(), settings: s)
        XCTAssertEqual(r.spec.audio, .mute)
    }

    func testNoAudioTrackMeansMute() {
        let r = SettingsResolver.resolve(info: info(hasAudio: false), settings: CompressionSettings())
        XCTAssertEqual(r.spec.audio, .mute)
    }

    func testTrimIsAppliedOnlyWhenItShortensTheClip() {
        var s = CompressionSettings()
        s.trimStart = 10; s.trimEnd = 20
        XCTAssertEqual(SettingsResolver.resolve(info: info(), settings: s).spec.trim, 10...20)
        s.trimStart = 0; s.trimEnd = 60
        XCTAssertNil(SettingsResolver.resolve(info: info(), settings: s).spec.trim)
    }

    func testResolutionAndFPSCaps() {
        var s = CompressionSettings()
        s.maxLongSide = 1280
        s.fps = .fps24
        var i = info(); i.fps = 60
        let r = SettingsResolver.resolve(info: i, settings: s)
        XCTAssertEqual(r.spec.width, 1280); XCTAssertEqual(r.spec.height, 720); XCTAssertEqual(r.spec.fps, 24)
    }
}

final class PresetTests: XCTestCase {
    func testPresetIDsAreUnique() {
        XCTAssertEqual(Set(Presets.all.map(\.id)).count, Presets.all.count)
    }

    func testRequiredPresetsExist() {
        for id in ["whatsapp", "telegram", "discord", "email", "instagram", "tiktok", "x", "shorts", "messages"] {
            XCTAssertNotNil(Presets.preset(id: id), id)
        }
    }

    func testSizePresetsStayUnderPlatformLimits() {
        func mb(_ id: String) -> Double {
            guard case .targetSize(let b) = Presets.preset(id: id)!.mode else { return .infinity }
            return Double(b) / 1_000_000
        }
        XCTAssertLessThan(mb("whatsapp"), 16)
        XCTAssertLessThan(mb("discord"), 10)
        XCTAssertLessThan(mb("email"), 25)
    }

    func testApplyPresetSetsEverything() {
        let p = Presets.preset(id: "whatsapp")!
        let s = p.apply(to: CompressionSettings())
        XCTAssertEqual(s.presetID, "whatsapp")
        XCTAssertEqual(s.maxLongSide, 1280)
        XCTAssertEqual(s.mode, p.mode)
    }
}

final class FormatSupportTests: XCTestCase {
    func testEveryPromisedExtensionHasARoute() {
        for ext in FormatSupport.allExtensions {
            XCTAssertNotEqual(FormatSupport.route(forExtension: ext), .unsupported, ext)
        }
    }

    func testRoutes() {
        XCTAssertEqual(FormatSupport.route(forExtension: "MP4"), .native)
        XCTAssertEqual(FormatSupport.route(forExtension: "mov"), .native)
        XCTAssertEqual(FormatSupport.route(forExtension: "mkv"), .ffmpeg)
        XCTAssertEqual(FormatSupport.route(forExtension: "avi"), .ffmpeg)
        XCTAssertEqual(FormatSupport.route(forExtension: "webm"), .ffmpeg)
        XCTAssertEqual(FormatSupport.route(forExtension: "wmv"), .ffmpeg)
        XCTAssertEqual(FormatSupport.route(forExtension: "flv"), .ffmpeg)
        XCTAssertEqual(FormatSupport.route(forExtension: "ts"), .ffmpeg)
        XCTAssertEqual(FormatSupport.route(forExtension: "pdf"), .unsupported)
    }

    func testNativeAndFFmpegSetsDoNotOverlap() {
        XCTAssertTrue(FormatSupport.nativeExtensions.isDisjoint(with: FormatSupport.ffmpegExtensions))
    }

    func testUniqueOutputNames() throws {
        let dir = outputDir()
        let a = OutputNaming.outputURL(for: "Holiday.mkv", in: dir)
        XCTAssertEqual(a.lastPathComponent, "Holiday-shrunk.mp4")
        try Data().write(to: a)
        let b = OutputNaming.outputURL(for: "Holiday.mkv", in: dir)
        XCTAssertEqual(b.lastPathComponent, "Holiday-shrunk-2.mp4")
    }

    func testNamesAreSanitised() {
        XCTAssertEqual(OutputNaming.sanitized("a/b:c*d"), "a_b_c_d")
        XCTAssertEqual(OutputNaming.sanitized("   "), "Video")
    }

    func testErrorMapping() {
        XCTAssertEqual(TranscodeError.map(CancellationError()), .cancelled)
        XCTAssertEqual(TranscodeError.map(TranscodeError.diskFull), .diskFull)
        let disk = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        XCTAssertEqual(TranscodeError.map(disk), .diskFull)
        XCTAssertNotNil(TranscodeError.protectedContent.errorDescription)
        XCTAssertTrue(TranscodeError.map(NSError(domain: "x", code: 1)).errorDescription?.contains("couldn't be compressed") == true)
    }

    func testByteFormatting() {
        XCTAssertFalse(ByteFormat.string(1_500_000).isEmpty)
        XCTAssertEqual(ByteFormat.megabytes(2_500_000), 2.5, accuracy: 0.001)
    }
}
