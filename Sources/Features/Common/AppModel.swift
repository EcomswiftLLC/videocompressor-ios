import Foundation
import SwiftUI
import UIKit

struct SourceItem: Identifiable, Equatable {
    var info: MediaInfo
    var photoIdentifier: String? = nil
    var thumbnail: UIImage? = nil
    var id: UUID { info.id }
    static func == (l: SourceItem, r: SourceItem) -> Bool { l.info == r.info && l.photoIdentifier == r.photoIdentifier }
}

enum JobState: Equatable {
    case waiting
    case running(fraction: Double, pass: Int)
    case done(CompressionResult)
    case failed(String)
    case cancelled
}

struct Job: Identifiable, Equatable {
    var item: SourceItem
    var state: JobState = .waiting
    var id: UUID { item.id }
}

enum Route: Hashable {
    case setup
    case run
}

@MainActor
final class AppModel: ObservableObject {
    static let maxItems = 20

    @Published var items: [SourceItem] = []
    @Published var settings = CompressionSettings()
    @Published var jobs: [Job] = []
    @Published var path: [Route] = []
    @Published var isLoading = false
    @Published var loadMessage: String?
    @Published var isRunning = false

    private var runTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var results: [CompressionResult] {
        jobs.compactMap { if case .done(let r) = $0.state { return r } else { return nil } }
    }
    var failures: [(Job, String)] {
        jobs.compactMap { if case .failed(let m) = $0.state { return ($0, m) } else { return nil } }
    }
    var totalOriginal: Int64 { results.reduce(0) { $0 + $1.originalBytes } }
    var totalOutput: Int64 { results.reduce(0) { $0 + $1.outputBytes } }

    // MARK: adding files

    func add(urls: [URL], photoIdentifiers: [String?] = []) async {
        guard !urls.isEmpty else { return }
        isLoading = true
        loadMessage = nil
        var problems: [String] = []
        for (index, url) in urls.enumerated() {
            if items.count >= Self.maxItems {
                problems.append("You can add up to \(Self.maxItems) videos at once.")
                break
            }
            do {
                let info = try await MediaProbe.load(url: url)
                var item = SourceItem(info: info, photoIdentifier: index < photoIdentifiers.count ? photoIdentifiers[index] : nil)
                item.thumbnail = await Thumbnailer.image(for: info, at: min(1, info.duration / 2), maxDimension: 480)
                items.append(item)
            } catch {
                let reason = TranscodeError.map(error).errorDescription ?? "Couldn't open it."
                problems.append("\(url.lastPathComponent): \(reason)")
            }
        }
        isLoading = false
        loadMessage = problems.isEmpty ? nil : problems.joined(separator: "\n")
        if !items.isEmpty, path.isEmpty { path = [.setup] }
        syncSettingsToItems()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        if items.isEmpty { path = [] }
        syncSettingsToItems()
    }

    /// New files start from the quality default; a preset stays selected when the person already picked one.
    private func syncSettingsToItems() {
        if items.count != 1 {
            settings.trimStart = nil
            settings.trimEnd = nil
        }
    }

    func applyPreset(_ preset: CompressionPreset) {
        settings = preset.apply(to: settings)
    }

    // MARK: running

    func start() {
        guard !items.isEmpty, !isRunning else { return }
        var s = settings
        if items.count > 1 { s.trimStart = nil; s.trimEnd = nil }
        jobs = items.map { Job(item: $0) }
        isRunning = true
        path.append(.run)
        UIApplication.shared.isIdleTimerDisabled = true
        beginBackground()
        let outDir = Workspace.outputs
        runTask = Task { [weak self] in
            guard let self else { return }
            for index in self.jobs.indices {
                if Task.isCancelled {
                    self.markRemainingCancelled(from: index)
                    break
                }
                let job = self.jobs[index]
                self.jobs[index].state = .running(fraction: 0, pass: 1)
                do {
                    let result = try await CompressionRunner.run(info: job.item.info, settings: s, outputDirectory: outDir) { update in
                        Task { @MainActor [weak self] in
                            guard let self, index < self.jobs.count else { return }
                            if case .running = self.jobs[index].state {
                                self.jobs[index].state = .running(fraction: update.fraction, pass: update.pass)
                            }
                        }
                    }
                    self.jobs[index].state = .done(result)
                    HistoryStore.shared.record(result)
                } catch {
                    let mapped = TranscodeError.map(error)
                    if mapped == .cancelled || Task.isCancelled {
                        self.jobs[index].state = .cancelled
                        self.markRemainingCancelled(from: index + 1)
                        break
                    }
                    self.jobs[index].state = .failed(mapped.errorDescription ?? "Failed.")
                }
            }
            self.isRunning = false
            UIApplication.shared.isIdleTimerDisabled = false
            self.endBackground()
            RewardedGate.shared.preloadIfPossible()
        }
    }

    private func markRemainingCancelled(from start: Int) {
        guard start < jobs.count else { return }
        for i in start..<jobs.count where jobs[i].state == .waiting { jobs[i].state = .cancelled }
    }

    func cancel() {
        runTask?.cancel()
    }

    /// Waits for a running batch (used by tests and debug screens).
    func waitUntilFinished() async {
        await runTask?.value
    }

    /// Back to the start. Temporary files are removed; saved videos in Photos or Files are untouched.
    func finish() {
        runTask?.cancel()
        jobs = []
        items = []
        path = []
        isRunning = false
        Workspace.clearAll()
    }

    func backToSetup() {
        if !isRunning { path = [.setup]; jobs = [] }
    }

    private func beginBackground() {
        endBackground()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Shrinkly compress") { [weak self] in
            Task { @MainActor in self?.endBackground() }
        }
    }

    private func endBackground() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
