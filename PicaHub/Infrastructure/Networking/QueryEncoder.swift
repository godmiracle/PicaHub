import Foundation

struct APIQueryItem: Sendable, Equatable {
    let name: String
    let value: String

    init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

enum QueryEncoder {
    private static let unreserved = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "-._~")
    )

    static func encode(_ items: [APIQueryItem]) -> String {
        items.map { item in
            "\(encodeComponent(item.name))=\(encodeComponent(item.value))"
        }
        .joined(separator: "&")
    }

    static func requestTarget(path: String, query: [APIQueryItem]) -> String {
        let encodedQuery = encode(query)
        guard !encodedQuery.isEmpty else { return path }
        return path.contains("?") ? "\(path)&\(encodedQuery)" : "\(path)?\(encodedQuery)"
    }

    private static func encodeComponent(_ value: String) -> String {
        value
            .addingPercentEncoding(withAllowedCharacters: unreserved)?
            .replacingOccurrences(of: "%20", with: "+") ?? value
    }
}
