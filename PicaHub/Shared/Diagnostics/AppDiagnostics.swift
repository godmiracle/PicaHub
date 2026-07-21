import OSLog

enum AppDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PicaHub",
        category: "Application"
    )

    static func debug(_ message: @autoclosure () -> String) {
#if DEBUG
        let value = message()
        logger.debug("\(value, privacy: .public)")
#endif
    }

    static func error(_ message: @autoclosure () -> String) {
#if DEBUG
        let value = message()
        logger.error("\(value, privacy: .public)")
#endif
    }

    static func requestCompleted(method: HTTPMethod, path: String, statusCode: Int) {
        debug("API \(method.rawValue) \(path) completed with HTTP \(statusCode)")
    }

    static func imageCacheResult(_ diagnostic: ImageCacheDiagnostic) {
        let width = diagnostic.targetPixelWidth.map(String.init) ?? "original"
        debug(
            "Image cache source=\(diagnostic.source.rawValue) "
                + "resource=\(diagnostic.resourceIdentifier) width=\(width)"
        )
    }
}
