import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Folders

enum Workspace {
    static var root: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Shrinkly", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var imports: URL { sub("Imports") }
    static var outputs: URL { sub("Outputs") }

    private static func sub(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Leftovers from an earlier session are not needed any more.
    static func clearAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// A fresh folder for one imported file, so the original name survives.
    static func importSlot(fileName: String) -> URL {
        let dir = imports.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(OutputNaming.sanitized((fileName as NSString).deletingPathExtension) + "." + ((fileName as NSString).pathExtension.isEmpty ? "mov" : (fileName as NSString).pathExtension))
    }
}

// MARK: - Photos picker

struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = Workspace.importSlot(fileName: received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

// MARK: - Files importer

enum FileImport {
    /// Types the Files picker allows. `.data` last so every container (MKV, AVI, WebM ...) can be chosen.
    static var allowedTypes: [UTType] {
        var types: [UTType] = [.movie, .video, .audiovisualContent, .mpeg4Movie, .quickTimeMovie]
        for ext in FormatSupport.allExtensions {
            if let t = UTType(filenameExtension: ext), !types.contains(t) { types.append(t) }
        }
        types.append(.data)
        return types
    }

    /// Copies a security-scoped file into the app's temporary folder.
    static func copyIn(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = Workspace.importSlot(fileName: url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }
}

// MARK: - Bundled sample clips

struct SampleClip: Identifiable, Equatable {
    let id: String
    let title: String
    let credit: String
    let url: URL
}

enum SampleClips {
    static func all(bundle: Bundle = .main) -> [SampleClip] {
        let candidates = [
            bundle.url(forResource: "samples", withExtension: "json", subdirectory: "Samples"),
            bundle.url(forResource: "samples", withExtension: "json")
        ]
        for case let url? in candidates {
            guard let data = try? Data(contentsOf: url),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            var clips: [SampleClip] = []
            for item in list {
                guard let file = item["file"] as? String else { continue }
                let name = (file as NSString).deletingPathExtension
                let ext = (file as NSString).pathExtension
                let found = bundle.url(forResource: name, withExtension: ext, subdirectory: "Samples")
                    ?? bundle.url(forResource: name, withExtension: ext)
                guard let found else { continue }
                clips.append(SampleClip(id: file, title: (item["title"] as? String) ?? name, credit: (item["credit"] as? String) ?? "", url: found))
            }
            if !clips.isEmpty { return clips }
        }
        // No manifest: any bundled mp4.
        let urls = (bundle.urls(forResourcesWithExtension: "mp4", subdirectory: "Samples") ?? []) + (bundle.urls(forResourcesWithExtension: "mp4", subdirectory: nil) ?? [])
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map {
            SampleClip(id: $0.lastPathComponent, title: $0.deletingPathExtension().lastPathComponent, credit: "", url: $0)
        }
    }

    /// A private copy, so the bundle file is never touched.
    static func copy(_ clip: SampleClip) throws -> URL {
        let dest = Workspace.importSlot(fileName: clip.url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: clip.url, to: dest)
        return dest
    }
}

// MARK: - Saving and sharing

enum PhotoSaver {
    enum SaveError: LocalizedError {
        case denied
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .denied: return "Shrinkly needs permission to add videos to Photos. Allow it in Settings > Shrinkly > Photos."
            case .failed(let m): return "Saving to Photos failed. \(m)"
            }
        }
    }

    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } catch {
            throw SaveError.failed(error.localizedDescription)
        }
    }

    /// Asks to delete originals chosen from the Photos picker. iOS shows its own confirmation.
    static func deleteOriginals(localIdentifiers: [String]) async -> Bool {
        guard !localIdentifiers.isEmpty else { return false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return false }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard assets.count > 0 else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch {
            return false
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onFinish: (() -> Void)? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onFinish?() }
        return vc
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct FilesExporter: UIViewControllerRepresentable {
    let urls: [URL]
    var onFinish: () -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish() }
    }
}

// MARK: - History and the "saved" counter

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var name: String
    var originalBytes: Int64
    var outputBytes: Int64
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    private let key = "sk.history.v1"
    private let totalKey = "sk.totalSaved.v1"

    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var totalSavedBytes: Int64 = 0

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
        totalSavedBytes = Int64(UserDefaults.standard.double(forKey: totalKey))
    }

    func record(_ result: CompressionResult) {
        let entry = HistoryEntry(date: Date(), name: result.sourceName, originalBytes: result.originalBytes, outputBytes: result.outputBytes)
        entries.insert(entry, at: 0)
        if entries.count > 30 { entries = Array(entries.prefix(30)) }
        totalSavedBytes += result.savedBytes
        persist()
    }

    func reset() {
        entries = []
        totalSavedBytes = 0
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
        UserDefaults.standard.set(Double(totalSavedBytes), forKey: totalKey)
    }
}
