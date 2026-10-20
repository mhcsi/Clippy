import AppKit
import Combine
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ClipboardHistorySortOrder: Equatable {
    case lastCopy
    case firstCopy
}

enum ClipboardContentFilter: String, CaseIterable, Identifiable {
    case all
    case photos
    case texts
    case links

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .photos: "Photos"
        case .texts: "Texts"
        case .links: "Links"
        }
    }
}

struct ClipboardSourceApp: Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String
    var id: String { bundleIdentifier }
}

struct ClipboardEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let copiedAt: Date
    let imageType: String?
    let imageFileName: String?
    let thumbnailFileName: String?
    let imageDigest: String?
    let sourceAppName: String?
    let sourceBundleIdentifier: String?

    init(text: String, copiedAt: Date = .now, id: UUID = UUID(), sourceAppName: String? = nil, sourceBundleIdentifier: String? = nil) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.imageType = nil
        self.imageFileName = nil
        self.thumbnailFileName = nil
        self.imageDigest = nil
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    init(imageType: String, imageFileName: String, thumbnailFileName: String, imageDigest: String, copiedAt: Date = .now, id: UUID = UUID(), sourceAppName: String? = nil, sourceBundleIdentifier: String? = nil) {
        self.id = id
        self.text = ""
        self.copiedAt = copiedAt
        self.imageType = imageType
        self.imageFileName = imageFileName
        self.thumbnailFileName = thumbnailFileName
        self.imageDigest = imageDigest
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    var isImage: Bool { imageFileName != nil && imageType != nil }
}

@MainActor
final class ClipboardHistory: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var isPaused = false
    @Published var searchText = ""
    @Published var hoveredEntryID: UUID?
    @Published var sortOrder: ClipboardHistorySortOrder = .lastCopy
    @Published var selectedSourceAppBundleIdentifier: String?
    @Published var contentFilter: ClipboardContentFilter = .all

    private let pasteboard: NSPasteboard
    private let storageURL: URL
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var lastExternalApplication: (name: String, bundleIdentifier: String)?
    private var lastChangeCount: Int
    private let maximumEntries = 1000

    init(pasteboard: NSPasteboard = .general, storageURL: URL? = nil) {
        self.pasteboard = pasteboard
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        self.lastChangeCount = pasteboard.changeCount
        load()
    }

    var sourceApplications: [ClipboardSourceApp] {
        var namesByBundleIdentifier: [String: String] = [:]
        for entry in entries {
            guard let bundleIdentifier = entry.sourceBundleIdentifier,
                  !bundleIdentifier.isEmpty,
                  let name = entry.sourceAppName else { continue }
            namesByBundleIdentifier[bundleIdentifier] = name
        }
        return namesByBundleIdentifier.map { ClipboardSourceApp(bundleIdentifier: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func startMonitoring() {
        guard timer == nil else { return }
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.rememberExternalApplication(application) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPasteboard() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func pollPasteboard() {
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        guard !isPaused else { return }
        let source = clipboardSourceApplication()
        if let (type, data) = imageRepresentation() {
            recordImage(data, type: type, sourceAppName: source?.name, sourceBundleIdentifier: source?.bundleIdentifier)
            return
        }
        guard let text = pasteboard.string(forType: .string) else { return }
        record(text, sourceAppName: source?.name, sourceBundleIdentifier: source?.bundleIdentifier)
    }

    func record(_ rawText: String, copiedAt: Date = .now, sourceAppName: String? = nil, sourceBundleIdentifier: String? = nil) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let previous = entries.first, !previous.isImage, previous.text == rawText { return }
        entries.insert(ClipboardEntry(text: rawText, copiedAt: copiedAt, sourceAppName: sourceAppName, sourceBundleIdentifier: sourceBundleIdentifier), at: 0)
        trimHistoryIfNeeded()
        save()
    }

    func recordImage(_ data: Data, type: NSPasteboard.PasteboardType, copiedAt: Date = .now, sourceAppName: String? = nil, sourceBundleIdentifier: String? = nil) {
        recordImage(data, typeIdentifier: type.rawValue, copiedAt: copiedAt, sourceAppName: sourceAppName, sourceBundleIdentifier: sourceBundleIdentifier)
    }

    func recordImage(_ data: Data, typeIdentifier: String, copiedAt: Date = .now, sourceAppName: String? = nil, sourceBundleIdentifier: String? = nil) {
        guard !data.isEmpty,
              let thumbnailData = Self.makeThumbnail(from: data),
              let imageDirectory = imageDirectoryURL() else { return }

        let digest = Self.digest(data)
        guard entries.first?.imageDigest != digest else { return }
        do {
            try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
            let id = UUID()
            let imageFileName = "\(id.uuidString).image"
            let thumbnailFileName = "\(id.uuidString).thumbnail.png"
            try data.write(to: imageDirectory.appendingPathComponent(imageFileName), options: .atomic)
            try thumbnailData.write(to: imageDirectory.appendingPathComponent(thumbnailFileName), options: .atomic)
            entries.insert(
                ClipboardEntry(imageType: typeIdentifier, imageFileName: imageFileName, thumbnailFileName: thumbnailFileName, imageDigest: digest, copiedAt: copiedAt, sourceAppName: sourceAppName, sourceBundleIdentifier: sourceBundleIdentifier),
                at: 0
            )
            trimHistoryIfNeeded()
            save()
        } catch {
            NSLog("Could not save clipboard image: %@", error.localizedDescription)
        }
    }

    func recopy(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        if entry.isImage,
           let fileName = entry.imageFileName,
           let type = entry.imageType,
           let directory = imageDirectoryURL(),
           let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
        } else if !entry.isImage {
            pasteboard.setString(entry.text, forType: .string)
        }
        // Treat our own selection as a clipboard write, not a newly copied entry.
        lastChangeCount = pasteboard.changeCount
    }

    func thumbnailData(for entry: ClipboardEntry) -> Data? {
        guard let fileName = entry.thumbnailFileName, let directory = imageDirectoryURL() else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(fileName))
    }

    func clear() {
        entries.forEach(removeImageFiles(for:))
        entries = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.copiedAt > $1.copiedAt }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("Could not save clipboard history: %@", error.localizedDescription)
        }
    }

    private func imageRepresentation() -> (NSPasteboard.PasteboardType, Data)? {
        let types = pasteboard.types ?? []
        let imageTypes = types.filter { type in
            UTType(type.rawValue)?.conforms(to: .image) == true
        }
        let sortedTypes = imageTypes.sorted { lhs, rhs in
            func priority(_ type: NSPasteboard.PasteboardType) -> Int {
                if type == .png { return 0 }
                if type == .tiff { return 1 }
                return 2
            }
            return priority(lhs) < priority(rhs)
        }
        for type in sortedTypes {
            if let data = pasteboard.data(forType: type), NSImage(data: data) != nil { return (type, data) }
        }

        if let image = NSImage(pasteboard: pasteboard),
           let data = image.tiffRepresentation {
            return (.tiff, data)
        }
        return nil
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.bundleIdentifier != Bundle.main.bundleIdentifier,
              let name = application.localizedName else { return }
        lastExternalApplication = (name, application.bundleIdentifier ?? "")
    }

    private func clipboardSourceApplication() -> (name: String, bundleIdentifier: String)? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let frontmost, frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            rememberExternalApplication(frontmost)
        }
        return lastExternalApplication
    }

    private func trimHistoryIfNeeded() {
        guard entries.count > maximumEntries else { return }
        let removed = Array(entries.suffix(entries.count - maximumEntries))
        removed.forEach(removeImageFiles(for:))
        entries.removeLast(removed.count)
    }

    private func removeImageFiles(for entry: ClipboardEntry) {
        guard let directory = imageDirectoryURL() else { return }
        for fileName in [entry.imageFileName, entry.thumbnailFileName].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
        }
    }

    private func imageDirectoryURL() -> URL? {
        storageURL.deletingLastPathComponent().appendingPathComponent("Images", isDirectory: true)
    }

    private static func makeThumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640
              ] as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultStorageURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipHistory", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}
