import SwiftUI

struct RunView: View {
    @EnvironmentObject private var model: AppModel
    @State private var startedAt = Date()
    @State private var now = Date()
    @State private var compareJob: Job?
    @State private var shareItems: [URL] = []
    @State private var showShare = false
    @State private var showFiles = false
    @State private var banner: Banner?
    @State private var working = false
    @State private var offerDelete = false
    @State private var confirmDiscard = false
    @State private var exported = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    struct Banner: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK.Space.l) {
                if model.isRunning { progressHeader } else { resultHeader }
                jobList
                if !model.isRunning { actions }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, SK.Space.m)
            .padding(.top, SK.Space.s)
            .skReadable()
        }
        .scrollIndicators(.hidden)
        .skScreen()
        .navigationTitle(model.isRunning ? "Compressing" : "Done")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !model.isRunning {
                    Button { model.backToSetup() } label: { Label("Settings", systemImage: "chevron.left") }
                        .accessibilityIdentifier("backToSetup")
                }
            }
        }
        .onAppear { startedAt = Date() }
        .onReceive(ticker) { now = $0 }
        .sheet(item: $compareJob) { job in CompareView(job: job) }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) { RewardedGate.shared.exportEnded() }.ignoresSafeArea() }
        .sheet(isPresented: $showFiles) { FilesExporter(urls: model.results.map(\.outputURL)) { showFiles = false; RewardedGate.shared.exportEnded() }.ignoresSafeArea() }
        .confirmationDialog("Start over?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard and start over", role: .destructive) { model.finish() }
            Button("Keep working", role: .cancel) {}
        } message: {
            Text("Compressed videos that you haven't saved or shared will be deleted.")
        }
        .alert("Delete the originals?", isPresented: $offerDelete) {
            Button("Delete originals", role: .destructive) {
                Task {
                    let ids = model.jobs.compactMap { $0.item.photoIdentifier }
                    let ok = await PhotoSaver.deleteOriginals(localIdentifiers: ids)
                    banner = Banner(text: ok ? "Originals moved to Recently Deleted." : "Originals were kept.", isError: !ok)
                }
            }
            Button("Keep originals", role: .cancel) {}
        } message: {
            Text("The compressed copies are in Photos. Deleted originals stay in Recently Deleted for 30 days.")
        }
    }

    // MARK: running

    private var overallFraction: Double {
        let count = max(1, model.jobs.count)
        var sum = 0.0
        for job in model.jobs {
            switch job.state {
            case .done, .failed, .cancelled: sum += 1
            case .running(let f, let pass): sum += pass == 2 ? 0.99 : f
            case .waiting: break
            }
        }
        return min(1, sum / Double(count))
    }

    private var currentIndex: Int {
        (model.jobs.firstIndex { if case .running = $0.state { return true } else { return false } } ?? model.jobs.count - 1) + 1
    }

    private var progressHeader: some View {
        let f = overallFraction
        let elapsed = now.timeIntervalSince(startedAt)
        let eta: String? = f > 0.05 ? Format.duration(max(0, elapsed / f - elapsed)) : nil
        let current = model.jobs.first { if case .running = $0.state { return true } else { return false } }
        var pass = 1
        if let current, case .running(_, let p) = current.state { pass = p }
        return SKCard {
            VStack(spacing: SK.Space.m) {
                ZStack {
                    Circle().stroke(SK.Palette.raised, lineWidth: 12)
                    Circle().trim(from: 0, to: max(0.003, f))
                        .stroke(SK.Palette.glacier, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: f)
                    VStack(spacing: 0) {
                        Text("\(Int((f * 100).rounded()))%")
                            .font(SK.Font.display(44)).foregroundStyle(SK.Palette.ivory)
                            .contentTransition(.numericText())
                        if let eta {
                            Text("\(eta) left").font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                        }
                    }
                }
                .frame(width: 190, height: 190)
                .padding(.vertical, SK.Space.s)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Compressing")
                .accessibilityValue("\(Int((f * 100).rounded())) percent")
                .accessibilityIdentifier("progressRing")

                VStack(spacing: 4) {
                    Text(model.jobs.count > 1 ? "Video \(currentIndex) of \(model.jobs.count)" : (current?.item.info.displayName ?? "Working"))
                        .font(SK.Font.headline).foregroundStyle(SK.Palette.ivory).lineLimit(1)
                    Text(pass == 2 ? "Fine-tuning the size…" : "Keep Shrinkly open while it works.")
                        .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                }
                Button(role: .cancel) { model.cancel() } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.skSecondaryWide)
                .accessibilityIdentifier("cancelButton")
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: finished

    private var resultHeader: some View {
        let results = model.results
        let saved = SizeEstimator.savedPercent(original: model.totalOriginal, now: model.totalOutput)
        return VStack(alignment: .leading, spacing: SK.Space.m) {
            if results.isEmpty {
                SKCard {
                    VStack(alignment: .leading, spacing: SK.Space.s) {
                        Text(model.failures.isEmpty ? "Nothing was compressed" : "Compression didn't finish")
                            .font(SK.Font.title(24)).foregroundStyle(SK.Palette.ivory)
                        Text(model.failures.first?.1 ?? "The job was cancelled before any video finished.")
                            .font(SK.Font.callout).foregroundStyle(SK.Palette.mist)
                    }
                }
            } else {
                SKCard {
                    VStack(alignment: .leading, spacing: SK.Space.m) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(results.count > 1 ? "You saved" : "Saved")
                                    .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                                Text(ByteFormat.string(max(0, model.totalOriginal - model.totalOutput)))
                                    .font(SK.Font.display(40)).foregroundStyle(SK.Palette.glacier)
                                    .accessibilityIdentifier("savedText")
                            }
                            Spacer()
                            Text("-\(saved)%").font(SK.Font.display(40)).foregroundStyle(SK.Palette.glacier)
                        }
                        SKSizeBars(before: model.totalOriginal, after: model.totalOutput)
                    }
                }
            }
            if let banner {
                Label(banner.text, systemImage: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(SK.Font.label)
                    .foregroundStyle(banner.isError ? SK.Palette.danger : SK.Palette.glacier)
                    .accessibilityIdentifier("banner")
            }
        }
    }

    private var jobList: some View {
        VStack(alignment: .leading, spacing: SK.Space.s) {
            if model.jobs.count > 1 || !model.isRunning { SKSectionTitle(text: model.isRunning ? "Queue" : "Your videos") }
            SKCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(model.jobs.enumerated()), id: \.element.id) { index, job in
                        JobRow(job: job, running: model.isRunning) { compareJob = job }
                        if index < model.jobs.count - 1 { SKHairline().padding(.leading, 84) }
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: SK.Space.s) {
            if !model.results.isEmpty {
                Button { exportToPhotos() } label: {
                    Label(model.results.count > 1 ? "Save all to Photos" : "Save to Photos", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.skPrimaryWide)
                .disabled(working)
                .accessibilityIdentifier("saveToPhotos")

                HStack(spacing: SK.Space.s) {
                    Button { exportShare() } label: {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.skSecondaryWide)
                    .accessibilityIdentifier("share")
                    Button { exportFiles() } label: {
                        Label("Save to Files", systemImage: "folder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.skSecondaryWide)
                    .accessibilityIdentifier("saveToFiles")
                }
                Text("Shrinkly is free because of ads. Saving or sharing asks you to watch one short ad.")
                    .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                    .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
            }
            Button { if model.results.isEmpty || exported { model.finish() } else { confirmDiscard = true } } label: {
                Text("Compress more videos").frame(maxWidth: .infinity)
            }
            .buttonStyle(.skQuiet)
            .accessibilityIdentifier("compressMore")
        }
    }

    // MARK: export (each one goes through the rewarded gate)

    private func exportToPhotos() {
        RewardedGate.shared.requestExport {
            Task {
                working = true
                defer { working = false; RewardedGate.shared.exportEnded() }
                do {
                    for r in model.results { try await PhotoSaver.save(r.outputURL) }
                    exported = true
                    banner = Banner(text: model.results.count > 1 ? "Saved \(model.results.count) videos to Photos." : "Saved to Photos.", isError: false)
                    if model.jobs.contains(where: { $0.item.photoIdentifier != nil }) { offerDelete = true }
                } catch {
                    banner = Banner(text: error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func exportShare() {
        RewardedGate.shared.requestExport {
            shareItems = model.results.map(\.outputURL)
            exported = true
            showShare = true
        }
    }

    private func exportFiles() {
        RewardedGate.shared.requestExport { exported = true; showFiles = true }
    }
}

struct JobRow: View {
    let job: Job
    let running: Bool
    var onCompare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ClipThumbnail(image: job.item.thumbnail)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(job.item.info.displayName).font(SK.Font.label).foregroundStyle(SK.Palette.ivory).lineLimit(1)
                detail
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, SK.Space.m)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var detail: some View {
        switch job.state {
        case .waiting:
            Text("Waiting").font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
        case .running(let f, _):
            ProgressView(value: f).tint(SK.Palette.glacier)
        case .done(let r):
            Text("\(ByteFormat.string(r.originalBytes)) to \(ByteFormat.string(r.outputBytes))")
                .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
            if let t = r.targetBytes, !r.metTarget {
                Text("Closest possible to \(ByteFormat.string(t))").font(SK.Font.caption).foregroundStyle(SK.Palette.champagne)
            }
        case .failed(let m):
            Text(m).font(SK.Font.caption).foregroundStyle(SK.Palette.danger).lineLimit(3)
        case .cancelled:
            Text("Cancelled").font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch job.state {
        case .done(let r):
            VStack(alignment: .trailing, spacing: 4) {
                Text("-\(r.savedPercent)%").font(SK.Font.number).foregroundStyle(SK.Palette.glacier)
                if !running {
                    Button("Compare", action: onCompare)
                        .font(SK.Font.label)
                        .accessibilityIdentifier("compare-\(job.item.info.displayName)")
                }
            }
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SK.Palette.danger)
        case .running:
            EmptyView()
        default:
            EmptyView()
        }
    }
}
