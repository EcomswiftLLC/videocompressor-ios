import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var history: HistoryStore
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var showSettings = false
    @State private var showFormats = false
    @State private var dropTargeted = false

    var body: some View {
        NavigationStack(path: $model.path) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: SK.Space.l) {
                        hero
                        if history.totalSavedBytes > 0 { savedCard }
                        actions
                        formatsRow
                        if !history.entries.isEmpty { recent }
                        Color.clear.frame(height: 70)
                    }
                    .padding(.horizontal, SK.Space.m)
                    .padding(.top, SK.Space.s)
                    .skReadable()
                }
                .scrollIndicators(.hidden)

                VStack(spacing: 0) {
                    BannerAdView()
                }
                .frame(maxWidth: .infinity)
                .background(SK.Palette.ink.opacity(0.0))
            }
            .skScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Shrinkly").font(SK.Font.title(20)).foregroundStyle(SK.Palette.ivory)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .setup: SetupView()
                case .run: RunView()
                }
            }
            .onDrop(of: [UTType.movie, UTType.fileURL], isTargeted: $dropTargeted) { providers in
                handleDrop(providers)
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: SK.Radius.card)
                        .strokeBorder(SK.Palette.champagne, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .background(SK.Palette.champagne.opacity(0.08), in: RoundedRectangle(cornerRadius: SK.Radius.card))
                        .overlay(Text("Drop videos to compress").font(SK.Font.title(22)).foregroundStyle(SK.Palette.ivory))
                        .padding(SK.Space.m)
                        .allowsHitTesting(false)
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showFormats) { FormatsView() }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: FileImport.allowedTypes, allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task {
                    var copies: [URL] = []
                    for u in urls { if let c = try? FileImport.copyIn(u) { copies.append(c) } }
                    await model.add(urls: copies)
                }
            }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                let items = newItems
                pickerItems = []
                Task { await load(items) }
            }
            .alert("Some videos weren't added", isPresented: Binding(get: { model.loadMessage != nil }, set: { if !$0 { model.loadMessage = nil } })) {
                Button("OK", role: .cancel) { model.loadMessage = nil }
            } message: {
                Text(model.loadMessage ?? "")
            }
            .overlay {
                if model.isLoading {
                    ProgressView("Opening video…")
                        .padding(SK.Space.l)
                        .background(SK.Palette.surface, in: RoundedRectangle(cornerRadius: SK.Radius.card))
                        .tint(SK.Palette.champagne)
                }
            }
        }
    }

    /// Drag and drop from Files, Photos or another window (iPad Split View). Each provider is copied into the workspace.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let candidates = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !candidates.isEmpty else { return false }
        model.isLoading = true
        Task {
            var urls: [URL] = []
            for provider in candidates.prefix(AppModel.maxItems) {
                if let url = await DroppedFile.copy(from: provider) { urls.append(url) }
            }
            model.isLoading = false
            if urls.isEmpty {
                model.loadMessage = "The dropped item couldn't be opened as a video."
            } else {
                await model.add(urls: urls)
            }
        }
        return true
    }

    private func load(_ items: [PhotosPickerItem]) async {
        model.isLoading = true
        var urls: [URL] = []
        var ids: [String?] = []
        for item in items {
            if let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                urls.append(movie.url)
                ids.append(item.itemIdentifier)
            }
        }
        model.isLoading = false
        if urls.isEmpty {
            model.loadMessage = "The video couldn't be loaded from Photos. If it is in iCloud, wait for it to download and try again."
            return
        }
        await model.add(urls: urls, photoIdentifiers: ids)
    }

    // MARK: sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: SK.Space.s) {
            Text("Make any video small enough to send.")
                .font(SK.Font.display(38))
                .tracking(-0.6)
                .foregroundStyle(SK.Palette.ivory)
                .fixedSize(horizontal: false, vertical: true)
            Text("Compress on your device. Nothing is uploaded.")
                .font(SK.Font.callout)
                .foregroundStyle(SK.Palette.mist)
        }
        .padding(.top, SK.Space.m)
    }

    private var savedCard: some View {
        SKCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You've saved")
                        .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                    Text(ByteFormat.string(history.totalSavedBytes))
                        .font(SK.Font.display(34))
                        .foregroundStyle(SK.Palette.glacier)
                }
                Spacer()
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.title3)
                    .foregroundStyle(SK.Palette.glacier.opacity(0.8))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: SK.Space.s) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: AppModel.maxItems, matching: .videos, preferredItemEncoding: .current) {
                Label("Choose videos", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.skPrimaryWide)
            .accessibilityIdentifier("chooseVideos")

            Button { showFiles = true } label: {
                Label("Import from Files", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.skSecondaryWide)
            .accessibilityIdentifier("importFiles")

            if let sample = SampleClips.all().first {
                Button {
                    Task {
                        if let url = try? SampleClips.copy(sample) { await model.add(urls: [url]) }
                    }
                } label: {
                    Text("Try a sample clip").frame(maxWidth: .infinity)
                }
                .buttonStyle(.skQuiet)
                .accessibilityIdentifier("trySample")
            }
        }
    }

    private var formatsRow: some View {
        Button { showFormats = true } label: {
            SKCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "film.stack").foregroundStyle(SK.Palette.champagne).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Opens MP4, MOV, MKV, AVI, WebM, WMV and more")
                            .font(SK.Font.label).foregroundStyle(SK.Palette.ivory)
                            .multilineTextAlignment(.leading)
                        Text("See all supported formats")
                            .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(SK.Palette.mist).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("formatsRow")
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: SK.Space.s) {
            SKSectionTitle(text: "Recent")
            SKCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(history.entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).font(SK.Font.label).foregroundStyle(SK.Palette.ivory).lineLimit(1)
                                Text("\(ByteFormat.string(entry.originalBytes)) to \(ByteFormat.string(entry.outputBytes))")
                                    .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                            }
                            Spacer()
                            Text("-\(SizeEstimator.savedPercent(original: entry.originalBytes, now: entry.outputBytes))%")
                                .font(SK.Font.number).foregroundStyle(SK.Palette.glacier)
                        }
                        .padding(SK.Space.m)
                        .accessibilityElement(children: .combine)
                        if index < min(5, history.entries.count) - 1 { SKHairline().padding(.leading, SK.Space.m) }
                    }
                }
            }
        }
    }
}
