import Foundation

enum APIError: Error, Sendable, Equatable {
    case invalidRequest
    case authenticationRequired
    case sessionExpired
    case cancelled
    case timedOut
    case connection(String)
    case service(statusCode: Int, message: String)
    case invalidResponse
    case decoding(String)

    var userMessage: String {
        switch self {
        case .invalidRequest:
            "请求地址无效"
        case .authenticationRequired, .sessionExpired:
            "登录已失效，请重新登录"
        case .cancelled:
            "请求已取消"
        case .timedOut:
            "连接超时，请稍后重试"
        case .connection:
            "网络连接失败，请检查网络后重试"
        case let .service(_, message):
            message.isEmpty ? "服务暂时不可用" : message
        case .invalidResponse, .decoding:
            "服务器返回了无法识别的数据"
        }
    }
}

enum DecodingFailureDescription {
    static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            "缺少字段 \(path(context.codingPath, appending: key))"
        case let .typeMismatch(type, context):
            "字段 \(path(context.codingPath)) 类型不匹配，期望 \(type)"
        case let .valueNotFound(type, context):
            "字段 \(path(context.codingPath)) 缺少值，期望 \(type)"
        case let .dataCorrupted(context):
            "字段 \(path(context.codingPath)) 数据格式错误"
        @unknown default:
            "JSON 结构与模型不匹配"
        }
    }

    private static func path(_ codingPath: [any CodingKey], appending key: (any CodingKey)? = nil) -> String {
        let keys = codingPath + (key.map { [$0] } ?? [])
        guard !keys.isEmpty else { return "<root>" }
        return keys.map { codingKey in
            if let index = codingKey.intValue {
                return "[\(index)]"
            }
            return codingKey.stringValue
        }.joined(separator: ".").replacingOccurrences(of: ".[", with: "[")
    }
}
