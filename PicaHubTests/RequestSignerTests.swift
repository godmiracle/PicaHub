import Foundation
import Testing
@testable import PicaHub

struct RequestSignerTests {
    private let signer = RequestSigner(environment: .proxy)

    @Test func referenceGETSignatureMatches() {
        let target = "comics?page=1&c=%E9%AA%91%E5%A3%AB&s=dd"

        let signature = signer.signature(
            requestTarget: target,
            timestamp: "1700000000",
            method: .get
        )

        #expect(signature == "9d8afda10d15b90a43b3e20ef2c1f156d0437fde7b756278ce76b5acdc0b931b")
    }

    @Test func referencePOSTSignatureMatches() {
        let signature = signer.signature(
            requestTarget: "auth/sign-in",
            timestamp: "1700000000",
            method: .post
        )

        #expect(signature == "4227e8b760083c4f0bfd01e276fbb02e46a465e4650c3324f4495b2daffb8785")
    }

    @Test func queryEncodingIsDeterministic() {
        let query = [
            APIQueryItem("page", "1"),
            APIQueryItem("keyword", "骑士 test"),
            APIQueryItem("empty", ""),
        ]

        #expect(
            QueryEncoder.encode(query)
                == "page=1&keyword=%E9%AA%91%E5%A3%AB+test&empty="
        )
    }

    @Test func requestTargetAppendsToExistingQuery() {
        let target = QueryEncoder.requestTarget(
            path: "comics/advanced-search?source=app",
            query: [APIQueryItem("page", "2")]
        )

        #expect(target == "comics/advanced-search?source=app&page=2")
    }
}
