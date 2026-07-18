import Foundation
import XCTest
@testable import PicaHub

private struct LiveCredentials {
    let email: String
    let password: String
    let environment: APIEnvironment

    init?(processInfo: ProcessInfo = .processInfo) {
        let variables = processInfo.environment
        guard
            let email = variables["PICACG_EMAIL"],
            let password = variables["PICACG_PASSWORD"],
            !email.isEmpty,
            !password.isEmpty
        else {
            return nil
        }
        self.email = email
        self.password = password
        environment = variables["PICACG_API_HOST"] == "direct" ? .direct : .proxy
    }
}

private actor LiveTokenVault {
    private var token: String?

    func read() -> String? {
        token
    }

    func write(_ token: String) {
        self.token = token
    }
}

final class LiveProtocolSpikeTests: XCTestCase {
    func testReadOnlyProtocolSpike() async throws {
        let credentials = try requireCredentials()
        let (client, vault) = makeClient(environment: credentials.environment)

        let login = try await client.send(
            PicaEndpoints.login(email: credentials.email, password: credentials.password)
        )
        XCTAssertFalse(login.token.isEmpty)
        await vault.write(login.token)

        let categories = try await client.send(PicaEndpoints.categories)
        XCTAssertFalse(categories.categories.isEmpty)

        let firstPage = try await client.send(PicaEndpoints.comics(page: 1))
        let comic = try XCTUnwrap(firstPage.comics.docs.first)
        let details = try await client.send(PicaEndpoints.comicDetails(id: comic.id)).comic
        XCTAssertEqual(details.id, comic.id)

        let chapters = try await loadAllChapters(client: client, comicID: comic.id)
        let chapter = try XCTUnwrap(chapters.first)
        let images = try await loadAllImages(
            client: client,
            comicID: comic.id,
            chapterOrder: chapter.order
        )
        let firstImage = try XCTUnwrap(images.first)
        let imageURL = try XCTUnwrap(
            ImageURLBuilder(environment: credentials.environment).url(for: firstImage.media)
        )
        let (imageData, response) = try await URLSession.shared.data(from: imageURL)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(imageData.isEmpty)
    }

    func testFavoriteMutationAndReadback() async throws {
        guard ProcessInfo.processInfo.environment["PICACG_ENABLE_MUTATION_SPIKE"] == "1" else {
            throw XCTSkip("Set PICACG_ENABLE_MUTATION_SPIKE=1 to run the reversible favorite mutation Spike")
        }
        let credentials = try requireCredentials()
        let (client, vault) = makeClient(environment: credentials.environment)
        let login = try await client.send(
            PicaEndpoints.login(email: credentials.email, password: credentials.password)
        )
        await vault.write(login.token)

        let comicPage = try await client.send(PicaEndpoints.comics(page: 1))
        let comic = try XCTUnwrap(comicPage.comics.docs.first)
        let originalState = try await client.send(
            PicaEndpoints.comicDetails(id: comic.id)
        ).comic.isFavourite

        _ = try await client.send(PicaEndpoints.toggleFavorite(comicID: comic.id))
        do {
            let changedState = try await client.send(
                PicaEndpoints.comicDetails(id: comic.id)
            ).comic.isFavourite
            XCTAssertEqual(changedState, !originalState)

            let favoriteIDs = try await loadFavoriteIDs(client: client)
            XCTAssertEqual(favoriteIDs.contains(comic.id), !originalState)
        } catch {
            _ = try? await client.send(PicaEndpoints.toggleFavorite(comicID: comic.id))
            throw error
        }

        _ = try await client.send(PicaEndpoints.toggleFavorite(comicID: comic.id))
        let restoredState = try await client.send(
            PicaEndpoints.comicDetails(id: comic.id)
        ).comic.isFavourite
        XCTAssertEqual(restoredState, originalState)
    }

    private func requireCredentials() throws -> LiveCredentials {
        guard let credentials = LiveCredentials() else {
            throw XCTSkip("Set PICACG_EMAIL and PICACG_PASSWORD in the test process environment")
        }
        return credentials
    }

    private func makeClient(
        environment: APIEnvironment
    ) -> (APIClient, LiveTokenVault) {
        let vault = LiveTokenVault()
        let client = APIClient(
            environment: environment,
            tokenProvider: { await vault.read() },
            sessionExpiredHandler: {}
        )
        return (client, vault)
    }

    private func loadAllChapters(client: APIClient, comicID: String) async throws -> [Chapter] {
        let first = try await client.send(PicaEndpoints.chapters(comicID: comicID, page: 1)).eps
        var chapters = first.docs
        guard first.pages > 1 else { return chapters }
        for page in 2...first.pages {
            let response = try await client.send(
                PicaEndpoints.chapters(comicID: comicID, page: page)
            )
            chapters.append(contentsOf: response.eps.docs)
        }
        return chapters
    }

    private func loadAllImages(
        client: APIClient,
        comicID: String,
        chapterOrder: Int
    ) async throws -> [ChapterImage] {
        let first = try await client.send(
            PicaEndpoints.chapterImages(comicID: comicID, order: chapterOrder, page: 1)
        ).pages
        var images = first.docs
        guard first.pages > 1 else { return images }
        for page in 2...first.pages {
            let response = try await client.send(
                PicaEndpoints.chapterImages(comicID: comicID, order: chapterOrder, page: page)
            )
            images.append(contentsOf: response.pages.docs)
        }
        return images
    }

    private func loadFavoriteIDs(client: APIClient) async throws -> Set<String> {
        let first = try await client.send(PicaEndpoints.favorites(page: 1)).comics
        var identifiers = Set(first.docs.map(\.id))
        guard first.pages > 1 else { return identifiers }
        for page in 2...first.pages {
            let response = try await client.send(PicaEndpoints.favorites(page: page))
            identifiers.formUnion(response.comics.docs.map(\.id))
        }
        return identifiers
    }
}
