import Foundation

@MainActor
final class ReaderImageCancellationController {
    private var cancelAction: (() -> Void)?

    func install(_ cancelAction: @escaping () -> Void) {
        self.cancelAction = cancelAction
    }

    func cancelAll() {
        cancelAction?()
    }

    func remove() {
        cancelAction = nil
    }
}
