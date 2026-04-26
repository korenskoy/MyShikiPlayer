//
//  CachedRemoteImage.swift
//  MyShikiPlayer
//

import AppKit
import Combine
import CryptoKit
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
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }

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

    private func fileURL(for url: URL) -> URL {
        let input = Data(url.absoluteString.utf8)
        let hash = Insecure.MD5.hash(data: input).map { String(format: "%02hhx", $0) }.joined()
        return directoryURL.appendingPathComponent(hash)
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
        if let loaded = await ImageCacheStore.shared.image(for: url) {
            image = loaded
            didFail = false
        } else {
            didFail = true
        }
    }
}
