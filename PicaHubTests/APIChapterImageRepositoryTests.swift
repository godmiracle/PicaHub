import Foundation
import Testing
@testable import PicaHub

private actor ChapterImageRequestRecorder {
    private(set) var requestedPages: [Int] = []
    private(set) var activeRequests = 0
    private(set) var maximumActiveRequests = 0

    func begin(page: Int) {
        requestedPages.append(page)
        activeRequests += 1
        maximumActiveRequests = max(maximumActiveRequests, activeRequests)
    }

    func finish() {
        activeRequests -= 1
    }
}

struct APIChapterImageRepositoryTests {
    @Test func loadsAllPagesWithBoundedConcurrencyAndDeterministicDeduplicatedOrder() async throws {
        let recorder = ChapterImageRequestRecorder()
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                let page = Self.pageNumber(from: request)
                await recorder.begin(page: page)
                do {
                    try await Task.sleep(for: .milliseconds((7 - page) * 5))
                    await recorder.finish()
                } catch {
                    await recorder.finish()
                    throw error
                }
                return Self.response(for: request, page: page)
            },
            tokenProvider: { "token" },
            maximumReadAttempts: 1
        )
        let repository = APIChapterImageRepository(client: client, maximumConcurrentPages: 3)

        let images = try await repository.fetchAllImages(comicID: "comic", chapterOrder: 8)

        #expect(images.map(\.id) == ["one", "shared", "three", "four", "five", "six"])
        #expect(Set(await recorder.requestedPages) == Set(1...6))
        #expect(await recorder.maximumActiveRequests == 3)
    }

    @Test func cancellationStopsOutstandingPageRequests() async {
        let recorder = ChapterImageRequestRecorder()
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                let page = Self.pageNumber(from: request)
                await recorder.begin(page: page)
                if page > 1 {
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        await recorder.finish()
                        throw error
                    }
                }
                await recorder.finish()
                return Self.response(for: request, page: page)
            },
            tokenProvider: { "token" },
            maximumReadAttempts: 1
        )
        let repository = APIChapterImageRepository(client: client, maximumConcurrentPages: 2)

        let loading = Task {
            try await repository.fetchAllImages(comicID: "comic", chapterOrder: 8)
        }
        while await recorder.activeRequests < 2 { await Task.yield() }
        loading.cancel()

        do {
            _ = try await loading.value
            Issue.record("Expected chapter image loading to be cancelled")
        } catch {
            #expect(error as? APIError == .cancelled)
        }
        #expect(await recorder.activeRequests == 0)
    }

    private static func pageNumber(from request: URLRequest) -> Int {
        Int(
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "page" })?.value ?? ""
        ) ?? 0
    }

    private static func response(for request: URLRequest, page: Int) -> (Data, HTTPURLResponse) {
        let identifiers: [String]
        switch page {
        case 1: identifiers = ["one", "shared"]
        case 2: identifiers = ["shared", "three"]
        case 3: identifiers = ["four"]
        case 4: identifiers = ["five"]
        case 5: identifiers = []
        case 6: identifiers = ["six"]
        default: identifiers = []
        }
        let docs = identifiers.map { identifier in
            "{\"_id\":\"\(identifier)\",\"media\":{\"fileServer\":\"https://example.com\",\"path\":\"\(identifier).jpg\"}}"
        }.joined(separator: ",")
        let data = Data(
            "{\"code\":200,\"message\":\"success\",\"data\":{\"pages\":{\"docs\":[\(docs)],\"limit\":2,\"page\":\(page),\"pages\":6,\"total\":7}}}".utf8
        )
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }
}
