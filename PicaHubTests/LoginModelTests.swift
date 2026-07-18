import Foundation
import Testing
@testable import PicaHub

private actor LoginRepositoryStub: AccountRepository {
    var result: AccountSessionState
    private(set) var authenticateCallCount = 0
    private(set) var receivedEmail: String?
    private(set) var receivedPassword: String?
    private var continuation: CheckedContinuation<AccountSessionState, Never>?
    let suspendsAuthentication: Bool

    init(result: AccountSessionState, suspendsAuthentication: Bool = false) {
        self.result = result
        self.suspendsAuthentication = suspendsAuthentication
    }

    func sessionState() -> AccountSessionState { result }
    func authenticationToken() -> String? { nil }
    func restoreSession() -> AccountSessionState { result }

    func authenticate(email: String, password: String) async -> AccountSessionState {
        authenticateCallCount += 1
        receivedEmail = email
        receivedPassword = password
        guard suspendsAuthentication else { return result }
        return await withCheckedContinuation { continuation = $0 }
    }

    func logout() -> AccountSessionState { .unauthenticated }
    func invalidateSession() -> AccountSessionState { .unauthenticated }

    func completeAuthentication() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
struct LoginModelTests {
    @Test func emptyFieldsFailWithoutCallingRepository() async {
        let repository = LoginRepositoryStub(result: .authenticated)
        let model = LoginModel(repository: repository)

        await model.submit()

        #expect(model.phase == .failed(message: "请输入邮箱和密码", isRetryable: false))
        #expect(await repository.authenticateCallCount == 0)
    }

    @Test func successfulLoginNormalizesEmailAndClearsPassword() async {
        let repository = LoginRepositoryStub(result: .authenticated)
        let model = LoginModel(repository: repository)
        model.email = "  user@example.com  "
        model.password = "secret-password"

        await model.submit()

        #expect(model.phase == .authenticated)
        #expect(model.email == "user@example.com")
        #expect(model.password.isEmpty)
        #expect(await repository.receivedEmail == "user@example.com")
        #expect(await repository.receivedPassword == "secret-password")
    }

    @Test func retryableFailurePreservesOnlyEmail() async {
        let failure = AccountSessionFailure(
            kind: .network,
            message: "网络连接失败，请检查网络后重试",
            email: "user@example.com",
            isRetryable: true
        )
        let repository = LoginRepositoryStub(result: .failed(failure))
        let model = LoginModel(repository: repository)
        model.email = "user@example.com"
        model.password = "secret-password"

        await model.submit()

        #expect(
            model.phase == .failed(
                message: "网络连接失败，请检查网络后重试",
                isRetryable: true
            )
        )
        #expect(model.email == "user@example.com")
        #expect(model.password.isEmpty)
    }

    @Test func duplicateSubmissionIsIgnored() async {
        let repository = LoginRepositoryStub(result: .authenticated, suspendsAuthentication: true)
        let model = LoginModel(repository: repository)
        model.email = "user@example.com"
        model.password = "secret-password"

        let firstSubmission = Task { await model.submit() }
        while model.phase != .submitting {
            await Task.yield()
        }
        await model.submit()

        #expect(await repository.authenticateCallCount == 1)
        await repository.completeAuthentication()
        await firstSubmission.value
        #expect(model.phase == .authenticated)
    }
}
