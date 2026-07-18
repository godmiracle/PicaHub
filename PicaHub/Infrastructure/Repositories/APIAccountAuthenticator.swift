import Foundation

struct APIAccountAuthenticator: AccountAuthenticating {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func login(email: String, password: String) async throws -> String {
        try await client.send(PicaEndpoints.login(email: email, password: password)).token
    }
}
