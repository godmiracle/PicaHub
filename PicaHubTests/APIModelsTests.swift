import Foundation
import Testing
@testable import PicaHub

struct APIModelsTests {
    @Test func categoryWithoutRemoteIDUsesStableFallbackID() throws {
        let data = Data(
            #"{"categories":[{"title":"骑士","description":""}]}"#.utf8
        )

        let response = try JSONDecoder().decode(CategoryResponse.self, from: data)

        #expect(response.categories.first?.remoteID == nil)
        #expect(response.categories.first?.id == "category:骑士")
    }

    @Test func decodesComicPageWithMissingOptionalFields() throws {
        let data = Data(
            #"{"comics":{"docs":[{"_id":"comic-1","title":"Title","thumb":{"fileServer":"https://s2.picacomic.com","path":"folder/image.jpg","originalName":"image.jpg"}}],"limit":20,"page":1,"pages":1,"total":1}}"#.utf8
        )

        let response = try JSONDecoder().decode(ComicPageResponse.self, from: data)

        #expect(response.comics.docs.first?.id == "comic-1")
        #expect(response.comics.docs.first?.author == nil)
    }

    @Test func missingRequiredComicIDFails() {
        let data = Data(
            #"{"comics":{"docs":[{"title":"Title","thumb":{"fileServer":"https://s2.picacomic.com","path":"folder/image.jpg"}}],"limit":20,"page":1,"pages":1,"total":1}}"#.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ComicPageResponse.self, from: data)
        }
    }

    @Test func imageBuilderInsertsStaticPath() {
        let reference = ImageReference(
            fileServer: "https://s2.picacomic.com",
            path: "folder/image.jpg",
            originalName: nil
        )

        let direct = ImageURLBuilder(environment: .direct).url(for: reference)
        let proxy = ImageURLBuilder(environment: .proxy).url(for: reference)

        #expect(direct?.absoluteString == "https://s2.picacomic.com/static/folder/image.jpg")
        #expect(proxy?.absoluteString == "https://s2.go2778.com/static/folder/image.jpg")
    }

    @Test func imageBuilderDoesNotDuplicateStaticPath() {
        let reference = ImageReference(
            fileServer: "https://s2.picacomic.com/static",
            path: "folder/image.jpg",
            originalName: nil
        )

        let url = ImageURLBuilder(environment: .direct).url(for: reference)

        #expect(url?.absoluteString == "https://s2.picacomic.com/static/folder/image.jpg")
    }
}
