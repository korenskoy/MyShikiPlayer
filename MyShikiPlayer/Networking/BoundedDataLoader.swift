//
//  BoundedDataLoader.swift
//  MyShikiPlayer
//
//  Shared networking primitive — used by the image cache, the Kodik scrapers
//  and the subtitle loaders alike. Lives outside any provider module on
//  purpose: every path that downloads from a host we do not control needs it.
//

import Foundation

/// Ceilings for response bodies fetched from hosts we do not control.
/// `URLSession.data(for:)` buffers the whole body in memory, so a hostile or
/// compromised host can otherwise stream an unbounded response straight into
/// RAM until the app is killed.
enum ResponseSizeLimit {
    /// Shikimori posters and screenshots are a few hundred KB; 32 MB leaves
    /// room for oversized originals while still bounding a runaway download.
    static let image = 32 * 1024 * 1024
    /// Kodik player pages, their JS bundles and the video-info JSON all sit in
    /// the low hundreds of KB.
    static let scrapedPage = 8 * 1024 * 1024
    /// ASS/VTT subtitle tracks. A feature-length ASS file with heavy styling
    /// stays under a megabyte; 8 MB is well past any legitimate track. The ASS
    /// body is handed straight to libass — a C parser — so this is the tightest
    /// bound the app has on a memory-unsafe surface, not just a memory ceiling.
    static let subtitle = 8 * 1024 * 1024
    /// Kodik search / catalog JSON. `with_episodes_data` responses for a long
    /// running series are the largest legitimate payload the app pulls, so the
    /// ceiling is deliberately generous — it exists to stop an unbounded
    /// stream, not to police the schema.
    static let catalogJSON = 64 * 1024 * 1024
}

enum BoundedResponseError: Error, LocalizedError {
    /// The advertised `Content-Length`, or the number of bytes actually
    /// received, exceeded the caller's limit. The transfer was cancelled.
    case tooLarge(limit: Int)

    /// Callers that surface this to the user interpolate it into their own
    /// message (see `ASSLoaderError.downloadFailed`), so it has to read as a
    /// sentence fragment rather than the default `Error` description.
    var errorDescription: String? {
        switch self {
        case .tooLarge(let limit):
            return "ответ превысил допустимый размер (\(limit / (1024 * 1024)) МБ)"
        }
    }
}

extension URLSession {
    /// `data(for:)` with a hard ceiling on the response body. The transfer is
    /// cancelled at header time when `Content-Length` already exceeds `limit`,
    /// and mid-stream once the received bytes do — an oversized body is never
    /// fully buffered.
    ///
    /// Implemented with a per-task delegate rather than `bytes(for:)`: the
    /// byte-by-byte `AsyncBytes` loop costs ~15 MB/s in a debug build and
    /// would run on the caller's actor, serialising the image cache.
    func boundedData(for request: URLRequest, limit: Int) async throws -> (Data, URLResponse) {
        let collector = BoundedDataCollector(limit: limit)
        let task = dataTask(with: request)
        task.delegate = collector
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Attached before `resume()`, so no delegate callback can
                // arrive before the continuation is in place.
                collector.attach(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

/// Accumulates a response body on the session's delegate queue, aborting as
/// soon as it grows past `limit`.
private final class BoundedDataCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var buffer = Data()
    private var response: URLResponse?
    private var overflowed = false
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?

    init(limit: Int) {
        self.limit = limit
    }

    func attach(_ continuation: CheckedContinuation<(Data, URLResponse), Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let expected = response.expectedContentLength
        lock.withLock { self.response = response }
        // `expectedContentLength` is -1 when the host advertises no length
        // (chunked transfer); the running check in `didReceive data` covers it.
        guard expected <= Int64(limit) else {
            lock.withLock { overflowed = true }
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let shouldCancel: Bool = lock.withLock {
            guard !overflowed else { return false }
            guard buffer.count + data.count <= limit else {
                overflowed = true
                buffer = Data()
                return true
            }
            buffer.append(data)
            return false
        }
        if shouldCancel {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let pending: CheckedContinuation<(Data, URLResponse), Error>?
        let outcome: Result<(Data, URLResponse), Error>
        lock.lock()
        pending = continuation
        continuation = nil
        if overflowed {
            // Reported ahead of `error`, which is just the cancellation we
            // triggered ourselves.
            outcome = .failure(BoundedResponseError.tooLarge(limit: limit))
        } else if let error {
            outcome = .failure(error)
        } else if let response {
            outcome = .success((buffer, response))
        } else {
            outcome = .failure(URLError(.badServerResponse))
        }
        lock.unlock()
        pending?.resume(with: outcome)
    }
}
