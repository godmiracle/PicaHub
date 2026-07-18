import Foundation

actor AuthenticatedRequestController {
    private var cancellationHandlers: [UUID: @Sendable () -> Void] = [:]

    func perform<Output: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Output
    ) async throws -> Output {
        let identifier = UUID()
        let task = Task { try await operation() }
        cancellationHandlers[identifier] = { task.cancel() }
        defer { cancellationHandlers[identifier] = nil }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancelAll() {
        let handlers = cancellationHandlers.values
        cancellationHandlers.removeAll()
        handlers.forEach { $0() }
    }

    var activeRequestCount: Int {
        cancellationHandlers.count
    }
}
