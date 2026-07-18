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

    func start() async {
        let updates = await repository.sessionStateUpdates()
        await restoreSession()
        for await updatedState in updates {
            guard !Task.isCancelled else { return }
            switch updatedState {
            case .authenticating:
                continue
            case let .failed(failure) where failure.email != nil:
                continue
            default:
                state = updatedState
            }
        }
    }

    func synchronizeAfterLogin() async {
        state = await repository.sessionState()
    }

    func logout() async {
        state = await repository.logout()
    }
}
