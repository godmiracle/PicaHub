import Foundation
import Observation

@MainActor
@Observable
final class LoginModel {
    enum Phase: Equatable {
        case idle
        case submitting
        case authenticated
        case failed(message: String, isRetryable: Bool)
    }

    var email = ""
    var password = ""
    private(set) var phase: Phase = .idle

    @ObservationIgnored private let repository: any AccountRepository

    init(repository: any AccountRepository) {
        self.repository = repository
    }

    var isSubmitting: Bool {
        phase == .submitting
    }

    func submit() async {
        guard !isSubmitting else { return }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedPassword = password
        email = normalizedEmail

        guard !normalizedEmail.isEmpty, !submittedPassword.isEmpty else {
            phase = .failed(message: "请输入邮箱和密码", isRetryable: false)
            return
        }

        password = ""
        phase = .submitting
        let sessionState = await repository.authenticate(
            email: normalizedEmail,
            password: submittedPassword
        )

        switch sessionState {
        case .authenticated:
            phase = .authenticated
        case let .failed(failure):
            phase = .failed(message: failure.message, isRetryable: failure.isRetryable)
        default:
            phase = .failed(message: "登录状态异常，请重试", isRetryable: true)
        }
    }
}
