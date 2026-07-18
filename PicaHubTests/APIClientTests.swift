import Foundation
import Testing
@testable import PicaHub

struct StubTransport: APITransport {
    let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}

actor AttemptCounter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

actor ExpirationRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

struct APIClientTests {
    @Test func requestContainsIndependentSignedHeaders() async throws {
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { _ in throw URLError(.cancelled) },
            tokenProvider: { "token-value" },
            timestampProvider: { "1700000000" }
        )
        let endpoint = PicaEndpoints.comics(page: 1, category: "骑士")

        let request = try await client.makeRequest(for: endpoint)

        #expect(request.url?.absoluteString == "https://picaapi.go2778.com/comics?page=1&c=%E9%AA%91%E5%A3%AB&s=dd")
        #expect(request.value(forHTTPHeaderField: "authorization") == "token-value")
        #expect(request.value(forHTTPHeaderField: "time") == "1700000000")
        #expect(request.value(forHTTPHeaderField: "signature") == "9d8afda10d15b90a43b3e20ef2c1f156d0437fde7b756278ce76b5acdc0b931b")
    }

    @Test func successfulEnvelopeDecodes() async throws {
        let responseData = Data(#"{"code":200,"message":"success","data":{"token":"abc"}}"#.utf8)
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                (responseData, Self.response(url: request.url!, statusCode: 200))
            },
            timestampProvider: { "1700000000" }
        )

        let response = try await client.send(PicaEndpoints.login(email: "a@example.com", password: "password"))

        #expect(response.token == "abc")
    }

    @Test func serviceErrorPreservesMessage() async throws {
        let responseData = Data(#"{"code":400,"message":"invalid credentials"}"#.utf8)
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                (responseData, Self.response(url: request.url!, statusCode: 400))
            },
            maximumReadAttempts: 1
        )

        await #expect(throws: APIError.service(statusCode: 400, message: "invalid credentials")) {
            try await client.send(PicaEndpoints.login(email: "a@example.com", password: "bad"))
        }
    }

    @Test func unauthorizedResponseInvalidatesSession() async throws {
        let recorder = ExpirationRecorder()
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                (Data(), Self.response(url: request.url!, statusCode: 401))
            },
            tokenProvider: { "expired" },
            sessionExpiredHandler: { await recorder.record() },
            maximumReadAttempts: 1
        )

        await #expect(throws: APIError.sessionExpired) {
            try await client.send(PicaEndpoints.categories)
        }
        #expect(await recorder.count == 1)
    }

    @Test func offlineFailureMapsToConnectionError() async throws {
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { _ in throw URLError(.notConnectedToInternet) },
            maximumReadAttempts: 1
        )

        do {
            _ = try await client.send(PicaEndpoints.login(email: "a@example.com", password: "password"))
            Issue.record("Expected a connection error")
        } catch let error as APIError {
            guard case .connection = error else {
                Issue.record("Expected connection error, received \(error)")
                return
            }
        }
    }

    @Test func cancelledTransportMapsToCancellationError() async throws {
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { _ in throw URLError(.cancelled) },
            maximumReadAttempts: 1
        )

        await #expect(throws: APIError.cancelled) {
            try await client.send(PicaEndpoints.login(email: "a@example.com", password: "password"))
        }
    }

    @Test func malformedSuccessIsDecodingError() async throws {
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                (Data(#"{"code":200,"message":"success","data":{}}"#.utf8), Self.response(url: request.url!, statusCode: 200))
            },
            timestampProvider: { "1700000000" },
            maximumReadAttempts: 1
        )

        do {
            _ = try await client.send(PicaEndpoints.login(email: "a@example.com", password: "password"))
            Issue.record("Expected a decoding error")
        } catch let error as APIError {
            guard case let .decoding(detail) = error else {
                Issue.record("Expected decoding error, received \(error)")
                return
            }
            #expect(detail == "缺少字段 data.token")
        }
    }

    @Test func idempotentReadRetriesTimeout() async throws {
        let attempts = AttemptCounter()
        let responseData = Data(#"{"code":200,"message":"success","data":{"categories":[]}}"#.utf8)
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { request in
                if await attempts.increment() == 1 {
                    throw URLError(.timedOut)
                }
                return (responseData, Self.response(url: request.url!, statusCode: 200))
            },
            tokenProvider: { "token" },
            maximumReadAttempts: 2
        )

        let result = try await client.send(PicaEndpoints.categories)

        #expect(result.categories.isEmpty)
        #expect(await attempts.value == 2)
    }

    @Test func writeDoesNotRetryAmbiguousFailure() async throws {
        let attempts = AttemptCounter()
        let client = APIClient(
            environment: .proxy,
            transport: StubTransport { _ in
                _ = await attempts.increment()
                throw URLError(.timedOut)
            },
            tokenProvider: { "token" },
            maximumReadAttempts: 3
        )

        await #expect(throws: APIError.timedOut) {
            try await client.send(PicaEndpoints.toggleFavorite(comicID: "comic"))
        }
        #expect(await attempts.value == 1)
    }

    private static func response(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}
