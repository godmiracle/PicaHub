import Foundation
import XCTest
@testable import PicaHub

private struct LiveCredentials {
    let email: String
    let password: String
    let environment: APIEnvironment

    init?(processInfo: ProcessInfo = .processInfo) {
        let variables = processInfo.environment
        guard
            let email = variables["PICACG_EMAIL"],
            let password = variables["PICACG_PASSWORD"],
            !email.isEmpty,
            !password.isEmpty
        else {
            return nil
        }
        self.email = email
        self.password = password
        environment = variables["PICACG_API_HOST"] == "direct" ? .direct : .proxy
    }
}

private actor LiveTokenVault {
    private var token: String?

    func read() -> String? {
        token
    }

    func write(_ token: String) {
        self.token = token
    }
}

private final class LiveURLSessionMetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingMetrics: [URLSessionTaskMetrics] = []
    private var waiters: [CheckedContinuation<URLSessionTaskMetrics, Never>] = []

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        lock.lock()
        if waiters.isEmpty {
            pendingMetrics.append(metrics)
            lock.unlock()
            return
        }
        let waiter = waiters.removeFirst()
        lock.unlock()
        waiter.resume(returning: metrics)
    }

    func nextMetrics() async -> URLSessionTaskMetrics {
        await withCheckedContinuation { continuation in
            lock.lock()
            if pendingMetrics.isEmpty {
                waiters.append(continuation)
                lock.unlock()
                return
            }
            let metrics = pendingMetrics.removeFirst()
            lock.unlock()
            continuation.resume(returning: metrics)
        }
    }
}

private struct LiveImageCacheSample {
    let data: Data
    let response: HTTPURLResponse
    let metrics: URLSessionTaskMetrics

    var transferredBodyBytes: Int64 {
        metrics.transactionMetrics.reduce(0) {
            $0 + $1.countOfResponseBodyBytesReceived
        }
    }
}

final class LiveProtocolSpikeTests: XCTestCase {
    func testReadOnlyProtocolSpike() async throws {
        let credentials = try requireCredentials()
        let (client, vault) = makeClient(environment: credentials.environment)

        let login = try await client.send(
            PicaEndpoints.login(email: credentials.email, password: credentials.password)
        )
        XCTAssertFalse(login.token.isEmpty)
        await vault.write(login.token)

        let categories = try await client.send(PicaEndpoints.categories)
        XCTAssertFalse(categories.categories.isEmpty)

        let firstPage = try await client.send(PicaEndpoints.comics(page: 1))
        let comic = try XCTUnwrap(firstPage.comics.docs.first)
        let details = try await client.send(PicaEndpoints.comicDetails(id: comic.id)).comic
        XCTAssertEqual(details.id, comic.id)

        let chapters = try await loadAllChapters(client: client, comicID: comic.id)
        let chapter = try XCTUnwrap(chapters.first)
        let images = try await loadAllImages(
            client: client,
            comicID: comic.id,
            chapterOrder: chapter.order
        )
        let firstImage = try XCTUnwrap(images.first)
        let imageURL = try XCTUnwrap(
            ImageURLBuilder(environment: credentials.environment).url(for: firstImage.media)
        )
        let (imageData, response) = try await URLSession.shared.data(from: imageURL)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(imageData.isEmpty)
    }

    func testFavoriteMutationAndReadback() async throws {
        guard ProcessInfo.processInfo.environment["PICACG_ENABLE_MUTATION_SPIKE"] == "1" else {
            throw XCTSkip("Set PICACG_ENABLE_MUTATION_SPIKE=1 to run the reversible favorite mutation Spike")
        }
        let credentials = try requireCredentials()
        let (client, vault) = makeClient(environment: credentials.environment)
        let login = try await client.send(
            PicaEndpoints.login(email: credentials.email, password: credentials.password)
        )
        await vault.write(login.token)

        let comicPage = try await client.send(PicaEndpoints.comics(page: 1))
        let comic = try XCTUnwrap(comicPage.comics.docs.first)
        let originalState = try await client.send(
            PicaEndpoints.comicDetails(id: comic.id)
        ).comic.isFavourite

        _ = try await client.send(PicaEndpoints.toggleFavorite(comicID: comic.id))
        do {
            let changedState = try await client.send(
                PicaEndpoints.comicDetails(id: comic.id)
            ).comic.isFavourite
            XCTAssertEqual(changedState, !originalState)

            let favoriteIDs = try await loadFavoriteIDs(client: client)
            XCTAssertEqual(favoriteIDs.contains(comic.id), !originalState)
        } catch {
            _ = try? await client.send(PicaEndpoints.toggleFavorite(comicID: comic.id))
            throw error
        }

        _ = try await client.send(PicaEndpoints.toggleFavorite(comicID: comic.id))
        let restoredState = try await client.send(
            PicaEndpoints.comicDetails(id: comic.id)
        ).comic.isFavourite
        XCTAssertEqual(restoredState, originalState)
    }

    func testRealImageResponseAvoidsRepeatedFullBodyTransfer() async throws {
        let credentials = try requireCredentials()
        let imageURL = try await loadFirstRealImageURL(credentials: credentials)
        let resourceIdentifier = ImageCacheDiagnostic(
            source: .network,
            url: imageURL,
            targetPixelWidth: nil
        ).resourceIdentifier

        let cache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 256 * 1_024 * 1_024,
            diskPath: "PicaHub.LiveImageCacheProbe.\(UUID().uuidString)"
        )
        cache.removeAllCachedResponses()
        let collector = LiveURLSessionMetricsCollector()
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        let session = URLSession(
            configuration: configuration,
            delegate: collector,
            delegateQueue: nil
        )
        defer {
            session.invalidateAndCancel()
            cache.removeAllCachedResponses()
        }

        let first = try await loadImage(
            from: imageURL,
            session: session,
            collector: collector
        )
        let second = try await loadImage(
            from: imageURL,
            session: session,
            collector: collector
        )

        XCTAssertEqual(first.response.statusCode, 200)
        XCTAssertEqual(second.response.statusCode, 200)
        XCTAssertFalse(first.data.isEmpty)
        XCTAssertEqual(second.data, first.data)
        XCTAssertGreaterThan(first.transferredBodyBytes, 0)

        let report = imageCacheReport(
            resourceIdentifier: resourceIdentifier,
            first: first,
            second: second
        )
        let attachment = XCTAttachment(string: report)
        attachment.name = "real-image-cache-evidence"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertLessThan(
            second.transferredBodyBytes,
            first.transferredBodyBytes,
            "The repeated image request transferred the full encoded body again. \(report)"
        )
    }

    private func requireCredentials() throws -> LiveCredentials {
        guard let credentials = LiveCredentials() else {
            throw XCTSkip("Set PICACG_EMAIL and PICACG_PASSWORD in the test process environment")
        }
        return credentials
    }

    private func makeClient(
        environment: APIEnvironment
    ) -> (APIClient, LiveTokenVault) {
        let vault = LiveTokenVault()
        let client = APIClient(
            environment: environment,
            tokenProvider: { await vault.read() },
            sessionExpiredHandler: {}
        )
        return (client, vault)
    }

    private func loadFirstRealImageURL(credentials: LiveCredentials) async throws -> URL {
        let (client, vault) = makeClient(environment: credentials.environment)
        let login = try await client.send(
            PicaEndpoints.login(email: credentials.email, password: credentials.password)
        )
        await vault.write(login.token)
        let comicPage = try await client.send(PicaEndpoints.comics(page: 1))
        let comic = try XCTUnwrap(comicPage.comics.docs.first)
        let chapters = try await loadAllChapters(client: client, comicID: comic.id)
        let chapter = try XCTUnwrap(chapters.first)
        let images = try await loadAllImages(
            client: client,
            comicID: comic.id,
            chapterOrder: chapter.order
        )
        let firstImage = try XCTUnwrap(images.first)
        return try XCTUnwrap(
            ImageURLBuilder(environment: credentials.environment).url(for: firstImage.media)
        )
    }

    private func loadImage(
        from url: URL,
        session: URLSession,
        collector: LiveURLSessionMetricsCollector
    ) async throws -> LiveImageCacheSample {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        let (data, response) = try await session.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        let metrics = await collector.nextMetrics()
        return LiveImageCacheSample(data: data, response: httpResponse, metrics: metrics)
    }

    private func imageCacheReport(
        resourceIdentifier: String,
        first: LiveImageCacheSample,
        second: LiveImageCacheSample
    ) -> String {
        [
            "resource=\(resourceIdentifier)",
            "cache-capacity=memory:33554432,disk:268435456",
            "response-cache-headers=\(cacheHeaderSummary(first.response))",
            "first=\(transactionSummary(first.metrics));body-bytes=\(first.transferredBodyBytes)",
            "second=\(transactionSummary(second.metrics));body-bytes=\(second.transferredBodyBytes)",
        ].joined(separator: "\n")
    }

    private func cacheHeaderSummary(_ response: HTTPURLResponse) -> String {
        let valueHeaders = ["Cache-Control", "Expires", "Age"]
            .compactMap { name -> String? in
                guard let value = headerValue(named: name, in: response) else { return nil }
                return "\(name)=\(value)"
            }
        let presenceHeaders = ["ETag", "Last-Modified"]
            .map { name in
                "\(name)=\(headerValue(named: name, in: response) == nil ? "absent" : "present")"
            }
        return (valueHeaders + presenceHeaders).joined(separator: ",")
    }

    private func headerValue(named name: String, in response: HTTPURLResponse) -> String? {
        response.allHeaderFields.first { key, _ in
            String(describing: key).caseInsensitiveCompare(name) == .orderedSame
        }.map { String(describing: $0.value) }
    }

    private func transactionSummary(_ metrics: URLSessionTaskMetrics) -> String {
        metrics.transactionMetrics.map { transaction in
            let statusCode = (transaction.response as? HTTPURLResponse)?.statusCode ?? 0
            return "status:\(statusCode),source:\(fetchTypeName(transaction.resourceFetchType)),received:\(transaction.countOfResponseBodyBytesReceived)"
        }.joined(separator: "|")
    }

    private func fetchTypeName(_ fetchType: URLSessionTaskMetrics.ResourceFetchType) -> String {
        switch fetchType {
        case .networkLoad:
            "network"
        case .serverPush:
            "server-push"
        case .localCache:
            "local-cache"
        case .unknown:
            "unknown"
        @unknown default:
            "future"
        }
    }

    private func loadAllChapters(client: APIClient, comicID: String) async throws -> [Chapter] {
        let first = try await client.send(PicaEndpoints.chapters(comicID: comicID, page: 1)).eps
        var chapters = first.docs
        guard first.pages > 1 else { return chapters }
        for page in 2...first.pages {
            let response = try await client.send(
                PicaEndpoints.chapters(comicID: comicID, page: page)
            )
            chapters.append(contentsOf: response.eps.docs)
        }
        return chapters
    }

    private func loadAllImages(
        client: APIClient,
        comicID: String,
        chapterOrder: Int
    ) async throws -> [ChapterImage] {
        let first = try await client.send(
            PicaEndpoints.chapterImages(comicID: comicID, order: chapterOrder, page: 1)
        ).pages
        var images = first.docs
        guard first.pages > 1 else { return images }
        for page in 2...first.pages {
            let response = try await client.send(
                PicaEndpoints.chapterImages(comicID: comicID, order: chapterOrder, page: page)
            )
            images.append(contentsOf: response.pages.docs)
        }
        return images
    }

    private func loadFavoriteIDs(client: APIClient) async throws -> Set<String> {
        let first = try await client.send(PicaEndpoints.favorites(page: 1)).comics
        var identifiers = Set(first.docs.map(\.id))
        guard first.pages > 1 else { return identifiers }
        for page in 2...first.pages {
            let response = try await client.send(PicaEndpoints.favorites(page: page))
            identifiers.formUnion(response.comics.docs.map(\.id))
        }
        return identifiers
    }
}
