import Foundation

/// Pure maths for sizes and bitrates. No framework calls, so it is fully unit tested.
enum SizeEstimator {
    /// Lowest video bitrate that still produces a watchable picture on a phone screen.
    static let minVideoBitrate = 120_000
    /// Container, headers and rate-control drift. Aim this much under the target so the file ends up at or below it.
    static let safetyFactor = 0.955

    /// Video bitrate that makes the whole file about `targetBytes`.
    static func videoBitrate(forTargetBytes targetBytes: Int64, duration: Double, audioBitrate: Int) -> Int {
        guard duration > 0 else { return minVideoBitrate }
        let totalBits = Double(targetBytes) * 8 * safetyFactor
        let audioBits = Double(audioBitrate) * duration
        let videoBits = max(0, totalBits - audioBits)
        return max(minVideoBitrate, Int(videoBits / duration))
    }

    /// Expected file size for the given bitrates.
    static func estimatedBytes(videoBitrate: Int, audioBitrate: Int, duration: Double) -> Int64 {
        guard duration > 0 else { return 0 }
        let bits = Double(videoBitrate + audioBitrate) * duration
        return Int64(bits / 8 * 1.01)
    }

    /// Bitrate for a 0...1 quality slider. Bits per pixel per frame, scaled by codec efficiency.
    static func qualityBitrate(width: Int, height: Int, fps: Double, codec: VideoCodec, quality: Double) -> Int {
        let q = quality.clamped(0, 1)
        // Perceptual curve: small gains at the top, big savings at the bottom.
        let bpp = 0.022 + (0.115 - 0.022) * pow(q, 1.35)
        let bits = Double(width) * Double(height) * max(1, fps) * bpp * codec.efficiency
        return max(minVideoBitrate, Int(bits))
    }

    /// Output size for a maximum long side: never larger than the source, always even numbers (encoders need them).
    static func scaledSize(width: Int, height: Int, maxLongSide: Int?) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (2, 2) }
        var w = Double(width)
        var h = Double(height)
        if let maxLongSide, maxLongSide > 0, max(width, height) > maxLongSide {
            let scale = Double(maxLongSide) / Double(max(width, height))
            w *= scale
            h *= scale
        }
        return (even(w), even(h))
    }

    static func even(_ value: Double) -> Int {
        let v = Int(value.rounded())
        return max(2, v - (v % 2))
    }

    /// Frame rate the output uses.
    static func outputFPS(sourceFPS: Double, cap: Double?) -> Double {
        let src = sourceFPS > 1 ? sourceFPS : 30
        guard let cap else { return src }
        return src > cap + 1 ? cap : src
    }

    /// Smallest and largest total size the slider offers for this clip, in bytes.
    static func targetRange(duration: Double, sourceBytes: Int64, audioBitrate: Int) -> ClosedRange<Int64> {
        let floorBytes = estimatedBytes(videoBitrate: minVideoBitrate, audioBitrate: audioBitrate, duration: duration)
        let low = max(200_000, floorBytes)
        let high = max(low + 100_000, sourceBytes)
        return low...high
    }

    /// Adjust the bitrate after a first pass landed at `actualBytes` instead of `targetBytes`.
    static func correctedBitrate(current: Int, actualBytes: Int64, targetBytes: Int64) -> Int {
        guard actualBytes > 0 else { return current }
        let ratio = Double(targetBytes) / Double(actualBytes)
        return max(minVideoBitrate, Int(Double(current) * ratio * 0.97))
    }

    /// Percentage saved, 0...100.
    static func savedPercent(original: Int64, now: Int64) -> Int {
        guard original > 0 else { return 0 }
        return max(0, min(100, Int((Double(original - now) / Double(original) * 100).rounded())))
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

/// Turns what the person chose plus the facts about a clip into the final numbers.
enum SettingsResolver {
    struct Resolved: Equatable {
        var spec: OutputSpec
        var estimatedBytes: Int64
        /// True when the file is already smaller than the request and compression would gain nothing.
        var alreadySmaller: Bool
        /// The target could only be met by going below the lowest sensible bitrate.
        var targetTooSmall: Bool
    }

    static func resolve(info: MediaInfo, settings: CompressionSettings) -> Resolved {
        let size = SizeEstimator.scaledSize(width: info.width, height: info.height, maxLongSide: settings.maxLongSide)
        let fps = SizeEstimator.outputFPS(sourceFPS: info.fps, cap: settings.fps.cap)
        let audioBitrate = settings.audio.bitrate ?? 0
        let hasAudio = info.hasAudio && audioBitrate > 0
        let effectiveAudio = hasAudio ? audioBitrate : 0

        var trimDuration = info.duration
        var trim: ClosedRange<Double>? = nil
        if let s = settings.trimStart, let e = settings.trimEnd, e - s > 0.2, e - s < info.duration - 0.05 {
            trim = s...e
            trimDuration = e - s
        }

        var videoBitrate: Int
        var tooSmall = false
        switch settings.mode {
        case .targetSize(let bytes):
            let raw = SizeEstimator.videoBitrate(forTargetBytes: bytes, duration: trimDuration, audioBitrate: effectiveAudio)
            let needed = Double(bytes) * 8 * SizeEstimator.safetyFactor - Double(effectiveAudio) * trimDuration
            tooSmall = trimDuration > 0 && needed / trimDuration < Double(SizeEstimator.minVideoBitrate)
            videoBitrate = raw
        case .quality(let q):
            videoBitrate = SizeEstimator.qualityBitrate(width: size.width, height: size.height, fps: fps, codec: settings.codec, quality: q)
        }
        // Spending more bits than the source did only makes the file bigger.
        let sourceCap = info.videoBitrate > 0 ? info.videoBitrate : Int.max
        var alreadySmaller = false
        if videoBitrate >= sourceCap {
            videoBitrate = max(SizeEstimator.minVideoBitrate, Int(Double(sourceCap) * 0.9))
            alreadySmaller = true
        }

        let spec = OutputSpec(
            codec: settings.codec,
            container: .mp4,
            width: size.width,
            height: size.height,
            fps: fps,
            videoBitrate: videoBitrate,
            audio: hasAudio ? .keep(bitrate: audioBitrate) : .mute,
            stripMetadata: settings.stripMetadata,
            trim: trim,
            convertHDRToSDR: true
        )
        let estimate = SizeEstimator.estimatedBytes(videoBitrate: videoBitrate, audioBitrate: effectiveAudio, duration: trimDuration)
        return Resolved(spec: spec, estimatedBytes: estimate, alreadySmaller: alreadySmaller, targetTooSmall: tooSmall)
    }
}
