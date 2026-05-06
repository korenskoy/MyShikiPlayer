//
//  CachedRemoteImage.swift
//  MyShikiPlayer
//

import AppKit
import Combine
import CoreGraphics
import CryptoKit
import ImageIO
import SwiftUI

// MARK: - Aspect-fill (crop without distortion; does not stretch layout to NSImage's natural size)

private final class AspectFillImageNSView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }
        let bounds = bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        let srcSize = image.size
        guard srcSize.width > 0, srcSize.height > 0 else { return }

        let scale = max(bounds.width / srcSize.width, bounds.height / srcSize.height)
        let drawW = srcSize.width * scale
        let drawH = srcSize.height * scale
        let x = (bounds.width - drawW) / 2
        let y = (bounds.height - drawH) / 2
        let dest = NSRect(x: x, y: y, width: drawW, height: drawH)
        let src = NSRect(origin: .zero, size: srcSize)
        image.draw(
            in: dest,
            from: src,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}

private struct AspectFillNSImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> AspectFillImageNSView {
        let view = AspectFillImageNSView()
        view.image = image
        return view
    }

    func updateNSView(_ nsView: AspectFillImageNSView, context: Context) {
        nsView.image = image
    }
}

actor ImageCacheStore {
    static let shared = ImageCacheStore()

    private let memoryCache = NSCache<NSURL, NSImage>()
    private let directoryURL: URL
    /// In-flight fetches keyed by URL — concurrent callers (e.g. two
    /// `CachedRemoteImage` views asking for the same poster while the user
    /// scrolls) join the same task instead of issuing parallel network
    /// requests. The entry is released on completion.
    private var pending: [URL: Task<NSImage?, Never>] = [:]

    /// Disk eviction policy — kept conservative on both axes. The catalog
    /// app pulls posters constantly and the inline-image cache (comment
    /// thumbnails) grows unbounded without these limits.
    private static let diskTTL: TimeInterval = 30 * 24 * 60 * 60   // 30 days
    private static let diskSizeLimit: Int64 = 256 * 1024 * 1024    // 256 MB

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("MyShikiPlayerImageCache", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        directoryURL = dir
        memoryCache.countLimit = 300
        // Best-effort sweep on launch — cheap and bounded by directory size.
        Task { [weak self] in
            await self?.evictStale()
        }
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }
        if let existing = pending[url] {
            return await existing.value
        }
        // The task itself clears the pending entry on completion — doing it
        // from the caller after `await task.value` would race with a new
        // caller arriving for the same URL between the await's resume and
        // the cleanup write.
        let task = Task<NSImage?, Never> { [weak self] in
            guard let self else { return nil }
            let result = await self.fetch(url: url)
            await self.releasePending(url: url)
            return result
        }
        pending[url] = task
        return await task.value
    }

    private func releasePending(url: URL) {
        pending[url] = nil
    }

    /// Decode-from-bytes and downsample the cached file to ~720p so the
    /// renderer doesn't keep a 4K NSImage in memory just because the source
    /// poster was high-res. Caller `image(for:)` already paid the disk-read
    /// once; we discard the original Data after decoding.
    func thumbnail(for url: URL, maxPixelSize: Int) async -> NSImage? {
        if let cached = memoryCache.object(forKey: thumbnailKey(url: url, max: maxPixelSize)) {
            return cached
        }
        // Reuse the regular fetch path so the file ends up on disk for the
        // next thumbnail request and the network round-trip is shared with
        // any concurrent full-size loaders.
        guard let _ = await image(for: url) else { return nil }
        let fileURL = fileURL(for: url)
        guard
            let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
            let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary)
        else { return nil }
        let nsImage = NSImage(cgImage: cg, size: .zero)
        memoryCache.setObject(nsImage, forKey: thumbnailKey(url: url, max: maxPixelSize))
        return nsImage
    }

    private func fetch(url: URL) async -> NSImage? {
        let fileURL = fileURL(for: url)
        if let data = try? Data(contentsOf: fileURL),
           let image = NSImage(data: data) {
            memoryCache.setObject(image, forKey: url as NSURL)
            return image
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let image = NSImage(data: data) else {
                return nil
            }
            try? data.write(to: fileURL, options: [.atomic])
            memoryCache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }

    func clear() async {
        memoryCache.removeAllObjects()
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? fm.removeItem(at: file)
        }
    }

    func sizeInBytes() async -> Int64 {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var total: Int64 = 0
        for file in files {
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Drops files older than `diskTTL`, then trims the cache down to
    /// `diskSizeLimit` by deleting the oldest entries first. Both passes
    /// run lazily on a background actor hop (caller is the actor itself);
    /// failure to read attributes for a file degrades to "leave it alone".
    private func evictStale() {
        let fm = FileManager.default
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        struct Entry {
            let url: URL
            let size: Int64
            let timestamp: Date
        }
        var entries: [Entry] = []
        entries.reserveCapacity(files.count)

        for file in files {
            guard let values = try? file.resourceValues(forKeys: Set(resourceKeys)) else { continue }
            let timestamp = values.contentAccessDate ?? values.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(timestamp) > Self.diskTTL {
                try? fm.removeItem(at: file)
                continue
            }
            entries.append(Entry(
                url: file,
                size: Int64(values.fileSize ?? 0),
                timestamp: timestamp
            ))
        }

        var total = entries.reduce(0) { $0 + $1.size }
        guard total > Self.diskSizeLimit else { return }
        // Oldest-first eviction until back under the soft limit.
        entries.sort { $0.timestamp < $1.timestamp }
        for entry in entries {
            if total <= Self.diskSizeLimit { break }
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    private func fileURL(for url: URL) -> URL {
        let input = Data(url.absoluteString.utf8)
        let hash = Insecure.MD5.hash(data: input).map { String(format: "%02hhx", $0) }.joined()
        return directoryURL.appendingPathComponent(hash)
    }

    /// NSCache key for a downsampled thumbnail keyed by (url, maxPixelSize)
    /// so different-sized thumbnails of the same source coexist.
    private func thumbnailKey(url: URL, max: Int) -> NSURL {
        // NSCache uses pointer equality by default for class keys; we wrap
        // the composite key into an NSURL so its `isEqual:` falls back to
        // string comparison.
        // swiftlint:disable:next force_unwrapping
        return NSURL(string: "thumb://\(max)/\(url.absoluteString)")!
    }
}

@MainActor
final class ImageCacheSettingsModel: ObservableObject {
    @Published private(set) var formattedSize: String = "—"
    @Published private(set) var isClearing = false

    func refreshSize() async {
        let size = await ImageCacheStore.shared.sizeInBytes()
        formattedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    func clearCache() async {
        isClearing = true
        await ImageCacheStore.shared.clear()
        await refreshSize()
        isClearing = false
    }
}

struct CachedRemoteImage<Placeholder: View, Failure: View>: View {
    let url: URL?
    let contentMode: ContentMode
    @ViewBuilder let placeholder: Placeholder
    @ViewBuilder let failure: Failure

    @State private var image: NSImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if contentMode == .fill {
                if let image {
                    AspectFillNSImageView(image: image)
                        .frame(minWidth: 0, minHeight: 0)
                } else if didFail {
                    failure
                } else {
                    placeholder
                }
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if didFail {
                failure
            } else {
                placeholder
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            didFail = true
            return
        }
        let loaded = await ImageCacheStore.shared.image(for: url)
        // `.task(id: url)` cancels the previous load when the URL changes
        // (rapid scroll). A cancelled fetch must NOT flip the placeholder
        // state — the new task is already in flight and will set it itself
        // (feedback_ui_stability — no flicker on scroll).
        if Task.isCancelled { return }
        if let loaded {
            image = loaded
            didFail = false
        } else {
            didFail = true
        }
    }
}
