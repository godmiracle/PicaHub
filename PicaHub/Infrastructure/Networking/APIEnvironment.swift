import Foundation

struct APIEnvironment: Sendable, Equatable {
    let baseURL: URL
    let apiKey: String
    let secretKey: String
    let nonce: String
    let appBuildVersion: String
    let appVersion: String
    let appPlatform: String
    let appUUID: String
    let appChannel: String

    static let proxy = APIEnvironment(
        baseURL: URL(string: "https://picaapi.go2778.com/")!,
        apiKey: "C69BAF41DA5ABD1FFEDC6D2FEA56B",
        secretKey: "~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn",
        nonce: "4ce7a7aa759b40f794d189a88b84aba8",
        appBuildVersion: "45",
        appVersion: "2.2.1.3.3.4",
        appPlatform: "android",
        appUUID: "defaultUuid",
        appChannel: "1"
    )

    static let direct = APIEnvironment(
        baseURL: URL(string: "https://picaapi.picacomic.com/")!,
        apiKey: proxy.apiKey,
        secretKey: proxy.secretKey,
        nonce: proxy.nonce,
        appBuildVersion: proxy.appBuildVersion,
        appVersion: proxy.appVersion,
        appPlatform: proxy.appPlatform,
        appUUID: proxy.appUUID,
        appChannel: proxy.appChannel
    )

    var baseHeaders: [String: String] {
        [
            "accept": "application/vnd.picacomic.com.v1+json",
            "User-Agent": "okhttp/3.8.1",
            "Content-Type": "application/json; charset=UTF-8",
            "api-key": apiKey,
            "app-build-version": appBuildVersion,
            "app-platform": appPlatform,
            "app-uuid": appUUID,
            "app-version": appVersion,
            "nonce": nonce,
            "app-channel": appChannel,
        ]
    }
}
