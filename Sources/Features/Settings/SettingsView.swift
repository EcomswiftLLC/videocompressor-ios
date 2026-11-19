import SwiftUI

enum AppLinks {
    static let site = URL(string: "https://ecomswiftllc.github.io/shrinkly/")!
    static let privacy = URL(string: "https://ecomswiftllc.github.io/shrinkly/privacy/")!
    static let terms = URL(string: "https://ecomswiftllc.github.io/shrinkly/terms/")!
    static let support = URL(string: "https://ecomswiftllc.github.io/shrinkly/support/")!
    static let licences = URL(string: "https://ecomswiftllc.github.io/shrinkly/licenses/")!
    static let ffmpegSource = URL(string: "https://github.com/EcomswiftLLC/ffmpeg-ios-lgpl")!
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var ads: AdsManager
    @EnvironmentObject private var history: HistoryStore
    @State private var confirmReset = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SK.Space.l) {
                    group("Help") {
                        link("Support and FAQ", "questionmark.circle", AppLinks.support)
                        divider
                        link("Privacy policy", "hand.raised", AppLinks.privacy)
                        divider
                        link("Terms of use", "doc.text", AppLinks.terms)
                    }
                    group("Privacy") {
                        if ads.privacyOptionsRequired {
                            row("Ad privacy choices", "slider.horizontal.3") { ads.presentPrivacyOptions() }
                            divider
                        }
                        row("Language", "globe") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        divider
                        row("Clear \"saved\" counter and recent list", "arrow.counterclockwise") { confirmReset = true }
                    }
                    group("Open-source licences") {
                        NavigationLink {
                            LicencesView()
                        } label: {
                            rowLabel("Licences and source code", "chevron.left.forwardslash.chevron.right")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("licencesRow")
                    }
                    Text("Shrinkly \(version)\nMade by Ecom Swift LLC")
                        .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(SK.Space.m)
                .skReadable()
            }
            .skScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .confirmationDialog("Clear the saved counter and recent list?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { history.reset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your videos are not touched.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var divider: some View { SKHairline().padding(.leading, 52) }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SK.Space.s) {
            SKSectionTitle(text: title)
            SKCard(padding: 0) { VStack(spacing: 0) { content() } }
        }
    }

    private func rowLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(SK.Palette.champagne).accessibilityHidden(true)
            Text(title).font(SK.Font.body).foregroundStyle(SK.Palette.ivory)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(SK.Palette.mist).accessibilityHidden(true)
        }
        .padding(SK.Space.m)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    private func row(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, symbol) }.buttonStyle(.plain)
    }

    private func link(_ title: String, _ symbol: String, _ url: URL) -> some View {
        row(title, symbol) { openURL(url) }
    }
}

struct LicencesView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK.Space.m) {
                Text("Shrinkly uses open-source software.")
                    .font(SK.Font.title(22)).foregroundStyle(SK.Palette.ivory)
                Text("""
                FFmpeg (libavformat, libavcodec, libavfilter, libswscale, libswresample, libavutil) is licensed under the GNU Lesser General Public License, version 2.1 or later. Shrinkly includes it as a separate dynamic framework (FFmpegLGPL.framework), built without any GPL or non-free parts, so you can replace it with your own build of the same libraries.

                Bundled with it: libvpx, libopus, libvorbis and libogg, libwebp and dav1d (BSD licences) and LAME (LGPL 2.1 or later).

                The exact versions, the build script and the complete source are published at github.com/EcomswiftLLC/ffmpeg-ios-lgpl. You can also ask for the source by email at support@ecomswiftllc.com for three years after you received this app.

                FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project. Shrinkly is not affiliated with the FFmpeg project.

                Ads are provided by Google AdMob (Google Mobile Ads SDK and User Messaging Platform), used under Google's terms.
                """)
                .font(SK.Font.callout).foregroundStyle(SK.Palette.mist)
                .fixedSize(horizontal: false, vertical: true)
                Button { openURL(AppLinks.ffmpegSource) } label: {
                    Label("Open the source repository", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.skSecondaryWide)
                Button { openURL(AppLinks.licences) } label: {
                    Label("Full licence texts", systemImage: "doc.text").frame(maxWidth: .infinity)
                }
                .buttonStyle(.skSecondaryWide)
            }
            .padding(SK.Space.m)
            .skReadable()
        }
        .skScreen()
        .navigationTitle("Licences")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FormatsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SK.Space.m) {
                    Text("Shrinkly opens almost any video and saves a compact MP4.")
                        .font(SK.Font.title(22)).foregroundStyle(SK.Palette.ivory)
                    SKCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(FormatSupport.promised.enumerated()), id: \.offset) { index, entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.group).font(SK.Font.label).foregroundStyle(SK.Palette.champagne)
                                    Text(entry.formats).font(SK.Font.callout).foregroundStyle(SK.Palette.ivory)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(SK.Space.m)
                                if index < FormatSupport.promised.count - 1 { SKHairline() }
                            }
                        }
                    }
                    SKCard {
                        VStack(alignment: .leading, spacing: SK.Space.s) {
                            Text("What you get").font(SK.Font.label).foregroundStyle(SK.Palette.champagne)
                            Text("MP4 with H.264 (plays everywhere) or HEVC (smaller). Hardware-accelerated, so it is fast and gentle on the battery.")
                                .font(SK.Font.callout).foregroundStyle(SK.Palette.ivory)
                        }
                    }
                    Label("Videos protected by DRM, such as purchased or rented movies, can't be changed by any app. Your own recordings always work.",
                          systemImage: "lock.shield")
                        .font(SK.Font.caption).foregroundStyle(SK.Palette.mist)
                }
                .padding(SK.Space.m)
                .skReadable()
            }
            .skScreen()
            .navigationTitle("Formats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
