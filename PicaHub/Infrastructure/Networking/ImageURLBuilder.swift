import Foundation

struct ImageURLBuilder: Sendable {
    let environment: APIEnvironment

    func url(for reference: ImageReference) -> URL? {
        let base: String
        if reference.fileServer.contains("static") {
            base = "\(reference.fileServer)/\(reference.path)"
        } else {
            base = "\(reference.fileServer)/static/\(reference.path)"
        }

        let routed: String
        if environment.baseURL.host == APIEnvironment.proxy.baseURL.host {
            routed = base.replacingOccurrences(of: "picacomic", with: "go2778")
        } else {
            routed = base
        }
        return URL(string: normalizeSlashes(in: routed))
    }

    private func normalizeSlashes(in value: String) -> String {
        guard let schemeRange = value.range(of: "://") else { return value }
        let scheme = value[..<schemeRange.upperBound]
        let remainder = value[schemeRange.upperBound...].replacingOccurrences(of: "//", with: "/")
        return String(scheme) + remainder
    }
}
