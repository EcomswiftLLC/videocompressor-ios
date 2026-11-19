import SwiftUI
import AVKit

/// Before and after on the same frame: drag the divider, scrub the time.
struct CompareView: View {
    let job: Job
    @Environment(\.dismiss) private var dismiss
    @State private var original: UIImage?
    @State private var compressed: UIImage?
    @State private var time: Double = 0
    @State private var split: CGFloat = 0.5
    @State private var loading = false
    @State private var playing = false

    private var result: CompressionResult? {
        if case .done(let r) = job.state { return r }
        return nil
    }
    private var duration: Double { job.item.info.duration }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SK.Space.l) {
                    comparison
                    if duration > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Frame at \(Format.duration(time))").font(SK.Font.label).foregroundStyle(SK.Palette.mist)
                            Slider(value: $time, in: 0...max(0.5, duration - 0.2)) { editing in
                                if !editing { Task { await loadFrames() } }
                            }
                            .tint(SK.Palette.champagne)
                            .accessibilityLabel("Frame time")
                            .accessibilityIdentifier("compareTime")
                        }
                    }
                    if let r = result {
                        SKCard {
                            VStack(alignment: .leading, spacing: SK.Space.m) {
                                SKSizeBars(before: r.originalBytes, after: r.outputBytes)
                                HStack(spacing: 6) {
                                    SKChip(text: "\(r.width)×\(r.height)")
                                    SKChip(text: r.codec.title)
                                    SKChip(text: "-\(r.savedPercent)%", tint: SK.Palette.glacier)
                                }
                            }
                        }
                        Button { playing = true } label: {
                            Label("Play compressed video", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.skSecondaryWide)
                        .accessibilityIdentifier("playCompressed")
                    }
                }
                .padding(SK.Space.m)
                .skReadable()
            }
            .skScreen()
            .navigationTitle(job.item.info.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task {
                time = min(1, max(0, duration / 3))
                await loadFrames()
            }
            .fullScreenCover(isPresented: $playing) {
                if let url = result?.outputURL { PlayerScreen(url: url) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var comparison: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .leading) {
                frame(original).frame(width: w, height: proxy.size.height)
                frame(compressed)
                    .frame(width: w, height: proxy.size.height)
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: max(0, w * (1 - split)))
                    }
                Rectangle().fill(SK.Palette.ivory).frame(width: 2)
                    .offset(x: w * split - 1)
                Circle().fill(SK.Palette.ivory).frame(width: 34, height: 34)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.caption.weight(.bold)).foregroundStyle(SK.Palette.ink))
                    .position(x: w * split, y: proxy.size.height / 2)
                VStack {
                    HStack {
                        label("Original")
                        Spacer()
                        label("Compressed")
                    }
                    Spacer()
                }
                .padding(10)
                if loading { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .clipShape(RoundedRectangle(cornerRadius: SK.Radius.card, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(0.98, max(0.02, value.location.x / max(1, w)))
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Before and after comparison")
            .accessibilityValue("Divider at \(Int(split * 100)) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: split = min(0.98, split + 0.1)
                case .decrement: split = max(0.02, split - 0.1)
                @unknown default: break
                }
            }
        }
        .aspectRatio(CGFloat(max(1, job.item.info.width)) / CGFloat(max(1, job.item.info.height)), contentMode: .fit)
        .frame(maxHeight: 420)
        .frame(maxWidth: .infinity)
        .background(SK.Palette.surface, in: RoundedRectangle(cornerRadius: SK.Radius.card, style: .continuous))
    }

    private func frame(_ image: UIImage?) -> some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                SK.Palette.raised
            }
        }
        .clipped()
    }

    private func label(_ text: String) -> some View {
        Text(text).font(SK.Font.caption.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
    }

    private func loadFrames() async {
        loading = true
        async let a = Thumbnailer.image(for: job.item.info, at: time, maxDimension: 1100)
        async let b: UIImage? = {
            guard let url = result?.outputURL else { return nil }
            return await Thumbnailer.image(url: url, at: time, maxDimension: 1100)
        }()
        original = await a
        compressed = await b
        loading = false
    }
}

struct PlayerScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).ignoresSafeArea() }
            Button { player?.pause(); dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.9)).padding()
            }
            .accessibilityLabel("Close player")
        }
        .onAppear { let p = AVPlayer(url: url); player = p; p.play() }
        .onDisappear { player?.pause() }
    }
}
