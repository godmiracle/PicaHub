import Foundation
import Observation

@MainActor
@Observable
final class AppRootModel {
    private(set) var state: AccountSessionState = .restoring

    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored private var isRestoring = false

    init(repository: any AccountRepository) {
        self.repository = repository
    }

    func restoreSession() async {
        guard !isRestoring else { return }
        isRestoring = true
        state = .restoring
        state = await repository.restoreSession()
        isRestoring = false
    }

    func synchronizeAfterLogin() async {
        state = await repository.sessionState()
    }
}
