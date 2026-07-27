//
//  BoundedDataLoaderTests.swift
//  MyShikiPlayerTests
//

import Foundation
import Testing
@testable import MyShikiPlayer

@Suite("BoundedDataLoader", .serialized)
struct BoundedDataLoaderTests {
    private static let limit = 1024 * 1024

    private func makeURL() throws -> URL {
        try #require(URL(string: "https://example.invalid/payload"))
    }

    /// `advertiseLength: false` mimics a chunked response, where
    /// `expectedContentLength` is -1 and only the running byte count can catch
    /// an oversized body.
    private func makeSession(url: URL, bodySize: Int, advertiseLength: Bool) -> URLSession {
        MockURLSession.make { _ in
            let headers = advertiseLength ? ["Content-Length": "\(bodySize)"] : [:]
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
            guard let response else { throw URLError(.badServerResponse) }
            return (response, Data(count: bodySize))
        }
    }

    @Test func bodyWithinLimitIsReturned() async throws {
        let url = try makeURL()
        let session = makeSession(url: url, bodySize: 4096, advertiseLength: true)

        let (data, response) = try await session.boundedData(
            for: URLRequest(url: url),
            limit: Self.limit
        )
        #expect(data.count == 4096)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test func advertisedOversizeBodyIsRejected() async throws {
        let url = try makeURL()
        let session = makeSession(url: url, bodySize: 2 * Self.limit, advertiseLength: true)

        await #expect(throws: BoundedResponseError.self) {
            _ = try await session.boundedData(for: URLRequest(url: url), limit: Self.limit)
        }
    }

    @Test func oversizeBodyWithoutContentLengthIsRejected() async throws {
        let url = try makeURL()
        let session = makeSession(url: url, bodySize: 2 * Self.limit, advertiseLength: false)

        do {
            _ = try await session.boundedData(for: URLRequest(url: url), limit: Self.limit)
            Issue.record("Expected the oversized body to be rejected")
        } catch BoundedResponseError.tooLarge(let limit) {
            #expect(limit == Self.limit)
        }
    }

    @Test func transportErrorIsPropagated() async throws {
        let url = try makeURL()
        let session = MockURLSession.make { _ in throw URLError(.notConnectedToInternet) }

        await #expect(throws: URLError.self) {
            _ = try await session.boundedData(for: URLRequest(url: url), limit: Self.limit)
        }
    }

    @Test func limitsAreOrdered() {
        // Scraped pages and subtitle tracks are the smallest payloads, the
        // catalog JSON the largest. A zero ceiling anywhere would silently
        // reject every response on that path.
        #expect(ResponseSizeLimit.subtitle > 0)
        #expect(ResponseSizeLimit.scrapedPage < ResponseSizeLimit.image)
        #expect(ResponseSizeLimit.image < ResponseSizeLimit.catalogJSON)
    }
}
