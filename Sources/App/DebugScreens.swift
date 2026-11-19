#if DEBUG
import SwiftUI

/// Debug builds can open any screen directly with `-skScreen <name>` (used by CI for screenshots and by the UI tests).
/// Names: home, home-filled, setup, setup-target, setup-presets, setup-advanced, processing, result, compare, batch,
/// formats, settings, licences. Real sample clips are used, and `result`, `compare` and `batch` run the real engine.
enum DebugScreens {
    static var requested: String? {
        let value = UserDefaults.standard.string(forKey: "skScreen")
        return (value?.isEmpty ?? true) ? nil : value
    }

    static var advancedExpanded: Bool { requested == "setup-advanced" }

    @ViewBuilder
    static func view(for name: String) -> some View {
        DebugHost(name: name)
    }
}

private struct DebugHost: View {
    let name: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var history: HistoryStore
    @State private var ready = false
    @State private var compareJob: Job?

    var body: some View {
        Group {
            switch name {
            case "settings": SettingsView()
            case "formats": FormatsView()
            case "licences": NavigationStack { LicencesView() }
            case "compare":
                if let job = compareJob { CompareView(job: job) } else { Color.clear.overlay(ProgressView("Compressing…")) }
            default:
                HomeView()
            }
        }
        .task {
            guard !ready else { return }
            ready = true
            await prepare()
        }
    }

    private func samples(_ count: Int) -> [URL] {
        let all = SampleClips.all()
        guard !all.isEmpty else { return [] }
        var urls: [URL] = []
        for i in 0..<count {
            if let url = try? SampleClips.copy(all[i % all.count]) { urls.append(url) }
        }
        return urls
    }

    private func prepare() async {
        switch name {
        case "home-filled":
            history.debugSeed()
        case "setup", "setup-target", "setup-presets", "setup-advanced":
            await model.add(urls: samples(1))
            if name == "setup-target" || name == "setup-presets" {
                if let p = Presets.preset(id: "whatsapp") { model.applyPreset(p) }
            }
        case "processing":
            await model.add(urls: samples(1))
            if var job = model.items.first.map({ Job(item: $0) }) {
                job.state = .running(fraction: 0.62, pass: 1)
                model.jobs = [job]
                model.isRunning = true
                model.path = [.run]
            }
        case "batch":
            await model.add(urls: samples(4))
            model.applyPreset(Presets.preset(id: "whatsapp")!)
            model.start()
            await model.waitUntilFinished()
        case "result":
            await model.add(urls: samples(1))
            model.applyPreset(Presets.preset(id: "whatsapp")!)
            model.start()
            await model.waitUntilFinished()
        case "compare":
            await model.add(urls: samples(1))
            model.applyPreset(Presets.preset(id: "email")!)
            model.start()
            await model.waitUntilFinished()
            compareJob = model.jobs.first
        default:
            break
        }
    }
}

extension HistoryStore {
    func debugSeed() {
        let now = Date()
        let samples: [(String, Int64, Int64)] = [
            ("Beach day.mov", 412_000_000, 38_000_000),
            ("Birthday dinner.mp4", 238_000_000, 21_500_000),
            ("Hike to the lake.mov", 905_000_000, 96_000_000)
        ]
        for (i, s) in samples.enumerated() {
            let result = CompressionResult(
                id: UUID(), sourceName: s.0, outputURL: URL(fileURLWithPath: "/dev/null"),
                originalBytes: s.1, outputBytes: s.2, width: 1280, height: 720, codec: .h264, passes: 1, targetBytes: nil
            )
            record(result)
            _ = now.addingTimeInterval(Double(-i) * 3600)
        }
    }
}
#endif
