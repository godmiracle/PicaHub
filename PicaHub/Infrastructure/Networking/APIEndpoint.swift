import Foundation

struct APIEndpoint<Response: Decodable>: Sendable where Response: Sendable {
    let method: HTTPMethod
    let path: String
    let query: [APIQueryItem]
    let body: Data?
    let requiresAuthentication: Bool
    let allowsAutomaticRetry: Bool

    init(
        method: HTTPMethod,
        path: String,
        query: [APIQueryItem] = [],
        body: Data? = nil,
        requiresAuthentication: Bool = true,
        allowsAutomaticRetry: Bool? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuthentication = requiresAuthentication
        self.allowsAutomaticRetry = allowsAutomaticRetry ?? (method == .get)
    }

    var requestTarget: String {
        QueryEncoder.requestTarget(path: path, query: query)
    }
}

extension APIEndpoint {
    static func json<Body: Encodable & Sendable>(
        method: HTTPMethod,
        path: String,
        query: [APIQueryItem] = [],
        body: Body,
        requiresAuthentication: Bool = true,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> APIEndpoint<Response> {
        APIEndpoint(
            method: method,
            path: path,
            query: query,
            body: try encoder.encode(body),
            requiresAuthentication: requiresAuthentication,
            allowsAutomaticRetry: false
        )
    }
}
