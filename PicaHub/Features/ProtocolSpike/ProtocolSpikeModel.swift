import Foundation
import Observation

private actor EphemeralTokenVault {
    private var token: String?

    func read() -> String? {
        token
    }

    func write(_ token: String?) {
        self.token = token
    }
}

@MainActor
@Observable
final class ProtocolSpikeModel {
    enum Host: String, CaseIterable, Identifiable {
        case proxy = "go2778"
        case direct = "picacomic"

        var id: Self { self }
        var environment: APIEnvironment { self == .proxy ? .proxy : .direct }
    }

    enum Status: Equatable {
        case idle
        case running
        case passed
        case failed(String)

        var title: String {
            switch self {
            case .idle: "等待验证"
            case .running: "验证中"
            case .passed: "只读协议验证通过"
            case .failed: "验证失败"
            }
        }
    }

    var email = ""
    var password = ""
    var host: Host = .proxy
    private(set) var status: Status = .idle
    private(set) var currentStep = "尚未开始"
    private(set) var logs: [String] = []
    private(set) var canRunFavoriteMutation = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var client: APIClient?
    @ObservationIgnored private var vault: EphemeralTokenVault?
    @ObservationIgnored private var validatedComicID: String?

    var isRunning: Bool {
        status == .running
    }

    func startReadOnlySpike() {
        guard !isRunning else { return }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedPassword = password
        guard !trimmedEmail.isEmpty, !submittedPassword.isEmpty else {
            status = .failed("请输入邮箱和密码")
            return
        }

        password = ""
        logs = []
        canRunFavoriteMutation = false
        validatedComicID = nil
        status = .running
        task = Task { [weak self] in
            await self?.runReadOnlySpike(
                email: trimmedEmail,
                password: submittedPassword,
                environment: self?.host.environment ?? .proxy
            )
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        status = .idle
        currentStep = "已取消"
        logs.append("已取消本次验证")
    }

    func runFavoriteMutation() {
        guard
            !isRunning,
            canRunFavoriteMutation,
            let client,
            let comicID = validatedComicID
        else {
            return
        }
        status = .running
        task = Task { [weak self] in
            await self?.performFavoriteMutation(client: client, comicID: comicID)
        }
    }

    private func runReadOnlySpike(
        email: String,
        password: String,
        environment: APIEnvironment
    ) async {
        let vault = EphemeralTokenVault()
        let client = APIClient(
            environment: environment,
            tokenProvider: { await vault.read() },
            sessionExpiredHandler: { await vault.write(nil) }
        )
        self.vault = vault
        self.client = client

        do {
            update(step: "登录", log: "正在验证登录和 token")
            let login = try await client.send(PicaEndpoints.login(email: email, password: password))
            try Task.checkCancellation()
            guard !login.token.isEmpty else { throw SpikeError.emptyToken }
            await vault.write(login.token)
            logs.append("登录成功，token 已保存在内存中")

            update(step: "分类", log: "正在加载分类")
            let categories = try await client.send(PicaEndpoints.categories)
            try Task.checkCancellation()
            guard !categories.categories.isEmpty else { throw SpikeError.emptyCategories }
            logs.append("分类验证通过：\(categories.categories.count) 项")

            update(step: "漫画列表", log: "正在加载漫画列表第一页")
            let comicPage = try await client.send(PicaEndpoints.comics(page: 1))
            try Task.checkCancellation()
            guard let comic = comicPage.comics.docs.first else { throw SpikeError.emptyComics }
            logs.append("漫画列表验证通过：第 1 页 \(comicPage.comics.docs.count) 项")

            update(step: "漫画详情", log: "正在加载样本漫画详情")
            let details = try await client.send(PicaEndpoints.comicDetails(id: comic.id)).comic
            guard details.id == comic.id else { throw SpikeError.identifierMismatch }
            logs.append("漫画详情验证通过")

            update(step: "章节", log: "正在加载全部章节分页")
            let chapters = try await loadAllChapters(client: client, comicID: comic.id)
            guard let chapter = chapters.first else { throw SpikeError.emptyChapters }
            logs.append("章节验证通过：\(chapters.count) 章")

            update(step: "章节图片", log: "正在加载样本章节全部图片分页")
            let images = try await loadAllImages(
                client: client,
                comicID: comic.id,
                chapterOrder: chapter.order
            )
            guard let firstImage = images.first else { throw SpikeError.emptyImages }
            logs.append("章节图片列表验证通过：\(images.count) 张")

            update(step: "图片下载", log: "正在验证封面和正文图片")
            try await validateImage(reference: comic.thumb, environment: environment)
            try await validateImage(reference: firstImage.media, environment: environment)
            logs.append("封面和正文图片下载验证通过")

            validatedComicID = comic.id
            canRunFavoriteMutation = true
            currentStep = "只读门禁完成"
            status = .passed
            logs.append("只读协议 Spike 全部通过；收藏写入仍需单独确认")
        } catch is CancellationError {
            status = .idle
            currentStep = "已取消"
            logs.append("已取消本次验证")
        } catch let error as APIError {
            fail(message(for: error))
        } catch {
            fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        task = nil
    }

    private func performFavoriteMutation(client: APIClient, comicID: String) async {
        var mutationApplied = false
        do {
            update(step: "收藏写入", log: "正在读取原收藏状态")
            let original = try await client.send(PicaEndpoints.comicDetails(id: comicID)).comic.isFavourite

            _ = try await client.send(PicaEndpoints.toggleFavorite(comicID: comicID))
            mutationApplied = true
            let changed = try await client.send(PicaEndpoints.comicDetails(id: comicID)).comic.isFavourite
            guard changed == !original else { throw SpikeError.favoriteStateDidNotChange }

            update(step: "收藏回读", log: "正在从收藏列表回读状态")
            let favoriteIDs = try await loadFavoriteIDs(client: client)
            guard favoriteIDs.contains(comicID) == !original else {
                throw SpikeError.favoriteReadbackMismatch
            }

            update(step: "恢复收藏", log: "正在恢复原收藏状态")
            _ = try await client.send(PicaEndpoints.toggleFavorite(comicID: comicID))
            mutationApplied = false
            let restored = try await client.send(PicaEndpoints.comicDetails(id: comicID)).comic.isFavourite
            guard restored == original else { throw SpikeError.favoriteRestoreFailed }

            currentStep = "完整协议门禁通过"
            status = .passed
            canRunFavoriteMutation = false
            logs.append("收藏写入、列表回读和原状态恢复全部通过")
        } catch {
            if mutationApplied {
                logs.append("验证中断，正在尽力恢复原收藏状态")
                _ = try? await client.send(PicaEndpoints.toggleFavorite(comicID: comicID))
            }
            if let error = error as? APIError {
                fail(message(for: error))
            } else {
                fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
        task = nil
    }

    private func loadAllChapters(client: APIClient, comicID: String) async throws -> [Chapter] {
        let first = try await client.send(PicaEndpoints.chapters(comicID: comicID, page: 1)).eps
        var results = first.docs
        if first.pages > 1 {
            for page in 2...first.pages {
                try Task.checkCancellation()
                let response = try await client.send(PicaEndpoints.chapters(comicID: comicID, page: page))
                results.append(contentsOf: response.eps.docs)
            }
        }
        return unique(results)
    }

    private func loadAllImages(
        client: APIClient,
        comicID: String,
        chapterOrder: Int
    ) async throws -> [ChapterImage] {
        let first = try await client.send(
            PicaEndpoints.chapterImages(comicID: comicID, order: chapterOrder, page: 1)
        ).pages
        var results = first.docs
        if first.pages > 1 {
            for page in 2...first.pages {
                try Task.checkCancellation()
                let response = try await client.send(
                    PicaEndpoints.chapterImages(comicID: comicID, order: chapterOrder, page: page)
                )
                results.append(contentsOf: response.pages.docs)
            }
        }
        return unique(results)
    }

    private func loadFavoriteIDs(client: APIClient) async throws -> Set<String> {
        let first = try await client.send(PicaEndpoints.favorites(page: 1)).comics
        var identifiers = Set(first.docs.map(\.id))
        if first.pages > 1 {
            for page in 2...first.pages {
                try Task.checkCancellation()
                let response = try await client.send(PicaEndpoints.favorites(page: page))
                identifiers.formUnion(response.comics.docs.map(\.id))
            }
        }
        return identifiers
    }

    private func validateImage(reference: ImageReference, environment: APIEnvironment) async throws {
        guard let url = ImageURLBuilder(environment: environment).url(for: reference) else {
            throw SpikeError.invalidImageURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw SpikeError.imageRequestFailed
        }
        guard !data.isEmpty else { throw SpikeError.emptyImageData }
    }

    private func unique<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID: Hashable {
        var identifiers = Set<Item.ID>()
        return items.filter { identifiers.insert($0.id).inserted }
    }

    private func update(step: String, log: String) {
        currentStep = step
        logs.append(log)
    }

    private func fail(_ message: String) {
        let failedStep = currentStep
        currentStep = "\(failedStep)失败"
        status = .failed(message)
        logs.append("\(failedStep)失败：\(message)")
    }

    private func message(for error: APIError) -> String {
        if case let .decoding(detail) = error {
            return "\(error.userMessage)：\(detail)"
        }
        return error.userMessage
    }
}

private enum SpikeError: LocalizedError {
    case emptyToken
    case emptyCategories
    case emptyComics
    case identifierMismatch
    case emptyChapters
    case emptyImages
    case invalidImageURL
    case imageRequestFailed
    case emptyImageData
    case favoriteStateDidNotChange
    case favoriteReadbackMismatch
    case favoriteRestoreFailed

    var errorDescription: String? {
        switch self {
        case .emptyToken: "登录响应没有 token"
        case .emptyCategories: "分类响应为空"
        case .emptyComics: "漫画列表为空，无法选择验证样本"
        case .identifierMismatch: "漫画详情 ID 与列表不一致"
        case .emptyChapters: "样本漫画没有章节"
        case .emptyImages: "样本章节没有图片"
        case .invalidImageURL: "图片地址无法构造"
        case .imageRequestFailed: "图片服务器返回失败状态"
        case .emptyImageData: "图片响应为空"
        case .favoriteStateDidNotChange: "收藏接口成功后详情状态没有变化"
        case .favoriteReadbackMismatch: "收藏列表回读状态不一致"
        case .favoriteRestoreFailed: "无法确认收藏状态已恢复"
        }
    }
}
