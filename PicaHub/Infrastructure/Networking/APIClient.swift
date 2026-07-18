import Foundation

actor APIClient {
    typealias TokenProvider = @Sendable () async -> String?
    typealias SessionExpiredHandler = @Sendable () async -> Void
    typealias TimestampProvider = @Sendable () -> String

    private let environment: APIEnvironment
    private let transport: any APITransport
    private let signer: RequestSigner
    private let tokenProvider: TokenProvider
    private let sessionExpiredHandler: SessionExpiredHandler
    private let timestampProvider: TimestampProvider
    private let decoder: JSONDecoder
    private let maximumReadAttempts: Int
    private let authenticatedRequests: AuthenticatedRequestController

    init(
        environment: APIEnvironment,
        transport: any APITransport = URLSessionTransport(),
        tokenProvider: @escaping TokenProvider = { nil },
        sessionExpiredHandler: @escaping SessionExpiredHandler = {},
        timestampProvider: @escaping TimestampProvider = {
            String(Int(Date().timeIntervalSince1970))
        },
        decoder: JSONDecoder = JSONDecoder(),
        maximumReadAttempts: Int = 3,
        authenticatedRequests: AuthenticatedRequestController = AuthenticatedRequestController()
    ) {
        self.environment = environment
        self.transport = transport
        self.signer = RequestSigner(environment: environment)
        self.tokenProvider = tokenProvider
        self.sessionExpiredHandler = sessionExpiredHandler
        self.timestampProvider = timestampProvider
        self.decoder = decoder
        self.maximumReadAttempts = max(1, maximumReadAttempts)
        self.authenticatedRequests = authenticatedRequests
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: APIEndpoint<Response>
    ) async throws -> Response {
        let request = try await makeRequest(for: endpoint)
        let allowedAttempts = endpoint.allowsAutomaticRetry ? maximumReadAttempts : 1
        var lastError: Error?

        for attempt in 1...allowedAttempts {
            do {
                let (data, response) = try await load(
                    request,
                    requiresAuthentication: endpoint.requiresAuthentication
                )
                AppDiagnostics.requestCompleted(
                    method: endpoint.method,
                    path: endpoint.path,
                    statusCode: response.statusCode
                )
                return try await decode(data: data, response: response)
            } catch is CancellationError {
                throw APIError.cancelled
            } catch let error as APIError {
                if shouldRetry(error: error, attempt: attempt, allowedAttempts: allowedAttempts) {
                    lastError = error
                    continue
                }
                throw error
            } catch let error as URLError {
                let mapped = map(urlError: error)
                if shouldRetry(error: mapped, attempt: attempt, allowedAttempts: allowedAttempts) {
                    lastError = mapped
                    continue
                }
                throw mapped
            } catch {
                let mapped = APIError.connection(String(describing: error))
                if shouldRetry(error: mapped, attempt: attempt, allowedAttempts: allowedAttempts) {
                    lastError = mapped
                    continue
                }
                throw mapped
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    func cancelAuthenticatedRequests() async {
        await authenticatedRequests.cancelAll()
    }

    func makeRequest<Response: Decodable & Sendable>(
        for endpoint: APIEndpoint<Response>
    ) async throws -> URLRequest {
        guard let url = URL(string: endpoint.requestTarget, relativeTo: environment.baseURL)?.absoluteURL else {
            throw APIError.invalidRequest
        }

        let token = await tokenProvider()
        if endpoint.requiresAuthentication, token?.isEmpty != false {
            throw APIError.authenticationRequired
        }

        let timestamp = timestampProvider()
        let signature = signer.signature(
            requestTarget: endpoint.requestTarget,
            timestamp: timestamp,
            method: endpoint.method
        )
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = 10

        var headers = environment.baseHeaders
        headers["time"] = timestamp
        headers["signature"] = signature
        headers["authorization"] = token ?? ""
        headers["image-quality"] = "original"
        request.allHTTPHeaderFields = headers
        return request
    }

    private func decode<Response: Decodable & Sendable>(
        data: Data,
        response: HTTPURLResponse
    ) async throws -> Response {
        if response.statusCode == 401 {
            await sessionExpiredHandler()
            throw APIError.sessionExpired
        }

        guard response.statusCode == 200 else {
            let errorEnvelope = try? decoder.decode(ServiceErrorEnvelope.self, from: data)
            throw APIError.service(
                statusCode: response.statusCode,
                message: errorEnvelope?.message ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            )
        }

        do {
            return try decoder.decode(APIEnvelope<Response>.self, from: data).data
        } catch let error as DecodingError {
            throw APIError.decoding(DecodingFailureDescription.describe(error))
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func load(
        _ request: URLRequest,
        requiresAuthentication: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        guard requiresAuthentication else {
            return try await transport.data(for: request)
        }
        let transport = transport
        return try await authenticatedRequests.perform {
            try await transport.data(for: request)
        }
    }

    private func shouldRetry(error: APIError, attempt: Int, allowedAttempts: Int) -> Bool {
        guard attempt < allowedAttempts else { return false }
        switch error {
        case .timedOut, .connection, .service(statusCode: 500...599, message: _):
            return true
        default:
            return false
        }
    }

    private func map(urlError: URLError) -> APIError {
        switch urlError.code {
        case .cancelled:
            .cancelled
        case .timedOut:
            .timedOut
        default:
            .connection(urlError.localizedDescription)
        }
    }
}
