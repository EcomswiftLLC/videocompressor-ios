import SwiftUI

@main
struct ShrinklyApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var ads = AdsManager.shared
    @StateObject private var history = HistoryStore.shared

    init() {
        SKAppearance.configure()
        // Imports and outputs left over from an earlier session are no longer needed.
        Workspace.clearAll()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(ads)
                .environmentObject(history)
                .preferredColorScheme(.dark)
                .tint(SK.Palette.champagne)
        }
    }
}

/// Starts ads only after the first frame, so launch is never blocked by consent or network.
struct RootView: View {
    @EnvironmentObject private var ads: AdsManager
    @State private var adsStarted = false

    var body: some View {
        ZStack {
            #if DEBUG
            if let screen = DebugScreens.requested {
                DebugScreens.view(for: screen)
            } else {
                HomeView()
            }
            #else
            HomeView()
            #endif
        }
        .skScreen()
        .task { await startAdsWhenReady() }
        .onChange(of: ads.adsReady) { _, ready in
            if ready { RewardedGate.shared.preloadIfPossible() }
        }
    }

    private func startAdsWhenReady() async {
        #if DEBUG
        if DebugScreens.requested != nil { return }
        // UI tests pass `-skNoAds YES` so Google's consent form (shown by region) cannot cover the controls under test.
        if UserDefaults.standard.bool(forKey: "skNoAds") { return }
        #endif
        guard !adsStarted else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled, !adsStarted else { return }
        adsStarted = true
        await ads.start()
    }
}
