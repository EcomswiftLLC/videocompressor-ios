import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showAdvanced = false
    @State private var targetText = ""
    @FocusState private var targetFocused: Bool
    /// "Target size" or "Quality"
    @State private var modeIsTarget = false

    private var items: [SourceItem] { model.items }
    private var s: CompressionSettings { model.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK.Space.l) {
                // Regular width (iPad full screen, wide Split View, large landscape iPhones) gets two columns; compact width stacks.
                if hSize == .regular {
                    HStack(alignment: .top, spacing: SK.Space.l) {
                        VStack(alignment: .leading, spacing: SK.Space.l) {
                            clipsSection
                            presetsSection
                            estimateCard
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        VStack(alignment: .leading, spacing: SK.Space.l) {
                            modeSection
                            advancedSection
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                } else {
                    VStack(alignment: .leading, spacing: SK.Space.l) {
                        clipsSection
                        presetsSection
                        modeSection
                        estimateCard
                        advancedSection
                    }
                }
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, SK.Space.m)
            .padding(.top, SK.Space.s)
            .skReadable(maxWidth: 1040)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .skScreen()
        .navigationTitle("Compress")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onAppear { syncModeFromSettings() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { targetFocused = false }
            }
        }
    }

    // MARK: clips

    private var clipsSection: some View {
        VStack(alignment: .leading, spacing: SK.Space.s) {
            if items.count == 1, let item = items.first {
                SingleClipCard(item: item)
            } else {
                SKSectionTitle(text: "\(items.count) videos")
                SKCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipRow(item: item) { model.remove(item.id) }
                            if index < items.count - 1 { SKHairline().padding(.leading, 84) }
                        }
                    }
                }
            }
        }
    }

    // MARK: presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: SK.Space.s) {
            SKSectionTitle(text: "Where is it going?")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SK.Space.s) {
                    ForEach(Presets.all) { preset in
                        SKOptionChip(title: preset.title, subtitle: preset.subtitle, systemImage: preset.symbol,
                                     selected: s.presetID == preset.id) {
                            model.applyPreset(preset)
                            syncModeFromSettings()
                        }
                        .accessibilityIdentifier("preset-\(preset.id)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: SK.Space.m) {
            Picker("Mode", selection: Binding(get: { modeIsTarget }, set: { setMode(target: $0) })) {
                Text("Target size").tag(true)
                Text("Quality").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("modePicker")

            SKCard {
                if modeIsTarget { targetControls } else { qualityControls }
            }
        }
    }

    private var targetRange: ClosedRange<Double> {
        // Smallest clip sets the floor, biggest source the ceiling (in MB).
        let audio = s.audio.bitrate ?? 0
        var lows: [Double] = []
        var highs: [Double] = []
        for item in items {
            let r = SizeEstimator.targetRange(duration: item.info.duration, sourceBytes: item.info.fileSize, audioBitrate: item.info.hasAudio ? audio : 0)
            lows.append(ByteFormat.megabytes(r.lowerBound))
            highs.append(ByteFormat.megabytes(r.upperBound))
        }
        let low = max(0.2, lows.min() ?? 0.5)
        let high = max(low * 1.5, highs.max() ?? 100)
        return low...high
    }

    private var currentTargetMB: Double {
        if case .targetSize(let b) = s.mode { return ByteFormat.megabytes(b) }
        return targetRange.upperBound * 0.3
    }

    private var targetControls: some View {
        let range = targetRange
        let mb = currentTargetMB.clamped(range.lowerBound, range.upperBound)
        return VStack(alignment: .leading, spacing: SK.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(items.count > 1 ? "Size of each video" : "Final size")
                    .font(SK.Font.label).foregroundStyle(SK.Palette.mist)
                Spacer()
                HStack(spacing: 4) {
                    TextField("MB", text: $targetText)
                        .keyboardType(.decimalPad)
                        .focused($targetFocused)
                        .multilineTextAlignment(.trailing)
                        .font(SK.Font.display(30))
                        .foregroundStyle(SK.Palette.ivory)
                        .frame(maxWidth: 110)
                        .onChange(of: targetText) { _, text in
                            if targetFocused, let v = Double(text.replacingOccurrences(of: ",", with: ".")), v > 0 {
                                setTarget(mb: v)
                            }
                        }
                        .accessibilityLabel("Target size in megabytes")
                        .accessibilityIdentifier("targetField")
                    Text("MB").font(SK.Font.headline).foregroundStyle(SK.Palette.mist)
                }
            }
            Slider(
                value: Binding(
                    get: { position(of: mb, in: range) },
                    set: { p in
                        let v = value(at: p, in: range)
                        setTarget(mb: v)
                        targetText = formatMB(v)
                    }
                ),
                in: 0...1
            )
            .tint(SK.Palette.champagne)
            .accessibilityLabel("Target size")
            .accessibilityValue("\(formatMB(mb)) megabytes")
            .accessibilityIdentifier("targetSlider")
            HStack {
                Text("\(formatMB(range.lowerBound)) MB").font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                Spacer()
                Text("\(formatMB(range.upperBound)) MB").font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
            }
        }
    }

    private var qualityControls: some View {
        var q = 0.55
        if case .quality(let v) = s.mode { q = v }
        return VStack(alignment: .leading, spacing: SK.Space.m) {
            HStack {
                Text("Quality").font(SK.Font.label).foregroundStyle(SK.Palette.mist)
                Spacer()
                Text(qualityLabel(q)).font(SK.Font.title(22)).foregroundStyle(SK.Palette.ivory)
            }
            Slider(value: Binding(get: { q }, set: { model.settings.mode = .quality($0); model.settings.presetID = nil }), in: 0...1)
                .tint(SK.Palette.champagne)
                .accessibilityLabel("Quality")
                .accessibilityValue(qualityLabel(q))
                .accessibilityIdentifier("qualitySlider")
            HStack {
                Text("Smaller file").font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                Spacer()
                Text("Sharper picture").font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
            }
        }
    }

    // MARK: estimate

    private var estimate: (original: Int64, now: Int64, tooSmall: Bool, already: Bool) {
        var original: Int64 = 0
        var now: Int64 = 0
        var tooSmall = false
        var already = false
        for item in items {
            let r = SettingsResolver.resolve(info: item.info, settings: batchSettings)
            original += item.info.fileSize
            now += min(r.estimatedBytes, item.info.fileSize)
            tooSmall = tooSmall || r.targetTooSmall
            already = already || r.alreadySmaller
        }
        return (original, now, tooSmall, already)
    }

    private var batchSettings: CompressionSettings {
        var c = s
        if items.count != 1 { c.trimStart = nil; c.trimEnd = nil }
        return c
    }

    private var estimateCard: some View {
        let e = estimate
        let saved = SizeEstimator.savedPercent(original: e.original, now: e.now)
        return SKCard {
            VStack(alignment: .leading, spacing: SK.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(items.count > 1 ? "Estimated total" : "Estimated size")
                            .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                        Text("≈ \(ByteFormat.string(e.now))")
                            .font(SK.Font.display(34)).foregroundStyle(SK.Palette.ivory)
                            .accessibilityIdentifier("estimateText")
                    }
                    Spacer()
                    Text("-\(saved)%")
                        .font(SK.Font.display(34)).foregroundStyle(SK.Palette.glacier)
                }
                SKSizeBars(before: e.original, after: e.now)
                if e.tooSmall {
                    note("That's very small, so the picture will look soft. Lower the resolution to keep it sharper.", systemImage: "exclamationmark.triangle")
                } else if e.already && saved < 10 {
                    note("This video is already compact. Pick a smaller size or a lower resolution to save more.", systemImage: "info.circle")
                }
            }
        }
    }

    private func note(_ text: String, systemImage: String) -> some View {
        Label { Text(text).font(SK.Font.caption).foregroundStyle(SK.Palette.mist).fixedSize(horizontal: false, vertical: true) }
            icon: { Image(systemName: systemImage).foregroundStyle(SK.Palette.champagne) }
    }

    // MARK: advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: SK.Space.s) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                HStack {
                    SKSectionTitle(text: "Advanced")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                        .foregroundStyle(SK.Palette.mist)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced options")
            .accessibilityValue(showAdvanced ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("advancedToggle")

            if showAdvanced {
                SKCard {
                    VStack(alignment: .leading, spacing: SK.Space.l) {
                        group("Resolution") {
                            chips(ResolutionChoice.allCases, selected: ResolutionChoice.match(s.maxLongSide), title: { $0.title }) { choice in
                                model.settings.maxLongSide = choice.longSide; model.settings.presetID = nil
                            }
                        }
                        group("Frame rate") {
                            chips(FPSChoice.allCases, selected: s.fps, title: { $0.title }) { model.settings.fps = $0; model.settings.presetID = nil }
                        }
                        group("Video format") {
                            HStack(spacing: SK.Space.s) {
                                ForEach(VideoCodec.allCases) { codec in
                                    SKOptionChip(title: codec.title, subtitle: codec.detail, selected: s.codec == codec) {
                                        model.settings.codec = codec; model.settings.presetID = nil
                                    }
                                }
                            }
                        }
                        group("Sound") {
                            chips(AudioChoice.allCases, selected: s.audio, title: { $0.title }) { model.settings.audio = $0; model.settings.presetID = nil }
                        }
                        Toggle(isOn: Binding(get: { s.stripMetadata }, set: { model.settings.stripMetadata = $0 })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remove location and metadata").font(SK.Font.label).foregroundStyle(SK.Palette.ivory)
                                Text("Keeps where and when you filmed private.").font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                            }
                        }
                        .tint(SK.Palette.glacier)
                        if items.count == 1, let info = items.first?.info, info.duration > 2 {
                            TrimControls(duration: info.duration)
                        }
                        if items.contains(where: { $0.info.isHDR }) {
                            Label("HDR video is converted to standard colours so it looks right everywhere.", systemImage: "sun.max")
                                .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                        }
                    }
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SK.Space.s) {
            Text(title).font(SK.Font.label).foregroundStyle(SK.Palette.mist)
            content()
        }
    }

    private func chips<T: Identifiable & Equatable>(_ all: [T], selected: T, title: @escaping (T) -> String, pick: @escaping (T) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SK.Space.s) {
                ForEach(all) { option in
                    SKOptionChip(title: title(option), selected: option == selected) { pick(option) }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            SKHairline()
            Button {
                targetFocused = false
                model.start()
            } label: {
                Text(items.count == 1 ? "Compress video" : "Compress \(items.count) videos")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.skPrimaryWide)
            .disabled(items.isEmpty)
            .accessibilityIdentifier("compressButton")
            .padding(.horizontal, SK.Space.m)
            .padding(.vertical, SK.Space.s)
            .skReadable()
        }
        .background(SK.Palette.ink.opacity(0.96))
    }

    // MARK: helpers

    private func setMode(target: Bool) {
        modeIsTarget = target
        model.settings.presetID = nil
        if target {
            let range = targetRange
            let mb = (ByteFormat.megabytes(items.map { $0.info.fileSize }.max() ?? 0) * 0.3).clamped(range.lowerBound, range.upperBound)
            setTarget(mb: mb)
            targetText = formatMB(mb)
        } else {
            model.settings.mode = .quality(0.55)
        }
    }

    private func setTarget(mb: Double) {
        model.settings.mode = .targetSize(bytes: Int64(mb * 1_000_000))
        model.settings.presetID = nil
    }

    private func syncModeFromSettings() {
        if case .targetSize(let b) = s.mode {
            modeIsTarget = true
            targetText = formatMB(ByteFormat.megabytes(b))
        } else {
            modeIsTarget = false
        }
    }

    private func position(of mb: Double, in r: ClosedRange<Double>) -> Double {
        guard r.upperBound > r.lowerBound, mb > 0 else { return 0 }
        return (log(mb / r.lowerBound) / log(r.upperBound / r.lowerBound)).clamped(0, 1)
    }

    private func value(at p: Double, in r: ClosedRange<Double>) -> Double {
        r.lowerBound * pow(r.upperBound / r.lowerBound, p.clamped(0, 1))
    }

    private func formatMB(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }

    private func qualityLabel(_ q: Double) -> String {
        switch q {
        case ..<0.2: return "Smallest"
        case ..<0.45: return "Small"
        case ..<0.7: return "Balanced"
        case ..<0.9: return "High"
        default: return "Best"
        }
    }
}

// MARK: - Pieces

struct SingleClipCard: View {
    let item: SourceItem
    var body: some View {
        SKCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ClipThumbnail(image: item.thumbnail)
                    .frame(height: 210)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: SK.Radius.card, topTrailingRadius: SK.Radius.card, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Text(Format.duration(item.info.duration))
                            .font(SK.Font.number).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(10)
                    }
                VStack(alignment: .leading, spacing: SK.Space.s) {
                    Text(item.info.displayName).font(SK.Font.headline).foregroundStyle(SK.Palette.ivory).lineLimit(1)
                    FactChips(info: item.info)
                }
                .padding(SK.Space.m)
            }
        }
    }
}

struct ClipRow: View {
    let item: SourceItem
    var onRemove: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            ClipThumbnail(image: item.thumbnail)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.info.displayName).font(SK.Font.label).foregroundStyle(SK.Palette.ivory).lineLimit(1)
                Text("\(ByteFormat.string(item.info.fileSize)) · \(Format.duration(item.info.duration)) · \(item.info.shortLabel)")
                    .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
            }
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(SK.Palette.mist).imageScale(.large)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Remove \(item.info.displayName)")
        }
        .padding(.horizontal, SK.Space.m)
        .padding(.vertical, 10)
    }
}

struct ClipThumbnail: View {
    let image: UIImage?
    var body: some View {
        ZStack {
            SK.Palette.raised
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "film").foregroundStyle(SK.Palette.mist).font(.title2)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct FactChips: View {
    let info: MediaInfo
    var body: some View {
        HStack(spacing: 6) {
            SKChip(text: ByteFormat.string(info.fileSize), tint: SK.Palette.ivory)
            SKChip(text: "\(info.shortLabel) \(Int(info.fps.rounded())) fps")
            SKChip(text: MediaProbe.codecLabel(info.codecName))
            if info.isHDR { SKChip(text: "HDR", tint: SK.Palette.champagne) }
            if info.route == .ffmpeg { SKChip(text: "Converted", tint: SK.Palette.glacier) }
        }
        .lineLimit(1)
    }
}

struct TrimControls: View {
    @EnvironmentObject private var model: AppModel
    let duration: Double

    private var start: Double { model.settings.trimStart ?? 0 }
    private var end: Double { model.settings.trimEnd ?? duration }

    var body: some View {
        VStack(alignment: .leading, spacing: SK.Space.s) {
            HStack {
                Text("Trim").font(SK.Font.label).foregroundStyle(SK.Palette.mist)
                Spacer()
                Text("\(Format.duration(start)) to \(Format.duration(end))").font(SK.Font.number).foregroundStyle(SK.Palette.ivory)
            }
            Slider(value: Binding(get: { start }, set: { v in
                model.settings.trimStart = min(v, end - 0.5)
                if model.settings.trimEnd == nil { model.settings.trimEnd = duration }
            }), in: 0...duration)
                .tint(SK.Palette.glacier)
                .accessibilityLabel("Trim start")
            Slider(value: Binding(get: { end }, set: { v in
                model.settings.trimEnd = max(v, start + 0.5)
                if model.settings.trimStart == nil { model.settings.trimStart = 0 }
            }), in: 0...duration)
                .tint(SK.Palette.glacier)
                .accessibilityLabel("Trim end")
            if model.settings.trimStart != nil || model.settings.trimEnd != nil {
                Button("Reset trim") { model.settings.trimStart = nil; model.settings.trimEnd = nil }
                    .font(SK.Font.label)
            }
        }
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
