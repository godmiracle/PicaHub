import SwiftUI

struct CategoryView: View {
    @State private var model: CategoryModel
    @State private var imageRefreshGeneration = 0
    private let imageCache: CategoryImageCache
    private let imageURLBuilder: ImageURLBuilder
    private let comicRepository: any ComicRepository
    private let onLogout: @MainActor () -> Void

    init(
        repository: any CategoryRepository,
        comicRepository: any ComicRepository,
        imageCache: CategoryImageCache,
        imageURLBuilder: ImageURLBuilder,
        onLogout: @escaping @MainActor () -> Void
    ) {
        _model = State(initialValue: CategoryModel(repository: repository))
        self.comicRepository = comicRepository
        self.imageCache = imageCache
        self.imageURLBuilder = imageURLBuilder
        self.onLogout = onLogout
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("发现")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        NavigationLink {
                            ComicSearchView(
                                repository: comicRepository,
                                imageURLBuilder: imageURLBuilder
                            )
                        } label: {
                            Label("搜索", systemImage: "magnifyingglass")
                        }
                        .accessibilityIdentifier("open-comic-search")

                        Button("退出登录", systemImage: "person.crop.circle.badge.xmark") {
                            onLogout()
                        }
                    }
                }
        }
        .task { await model.loadIfNeeded() }
        .alert(
            "刷新失败",
            isPresented: Binding(
                get: { model.refreshErrorMessage != nil },
                set: { if !$0 { model.dismissRefreshError() } }
            )
        ) {
            Button("知道了", role: .cancel) { model.dismissRefreshError() }
        } message: {
            Text(model.refreshErrorMessage ?? "请稍后重试")
        }
        .accessibilityIdentifier("session-authenticated")
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("正在加载分类")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("categories-loading")
        case let .content(categories, isRefreshing):
            categoryGrid(categories, isRefreshing: isRefreshing)
        case .empty:
            ContentUnavailableView {
                Label("暂无分类", systemImage: "square.grid.2x2")
            } description: {
                Text("服务器当前没有返回可浏览的漫画分类。")
            } actions: {
                Button("重新加载") { Task { await model.retry() } }
            }
            .accessibilityIdentifier("categories-empty")
        case let .failed(message):
            ContentUnavailableView {
                Label("分类加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { Task { await model.retry() } }
                    .buttonStyle(.borderedProminent)
            }
            .accessibilityIdentifier("categories-error")
        }
    }

    private func categoryGrid(_ categories: [ComicCategory], isRefreshing: Bool) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 14)],
                spacing: 18
            ) {
                ForEach(categories) { category in
                    NavigationLink {
                        ComicBrowseView(
                            category: category.title,
                            repository: comicRepository,
                            imageURLBuilder: imageURLBuilder
                        )
                    } label: {
                        CategoryCard(
                            category: category,
                            imageCache: imageCache,
                            imageURLBuilder: imageURLBuilder,
                            refreshGeneration: imageRefreshGeneration
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .overlay(alignment: .top) {
            if isRefreshing {
                ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .refreshable {
            if await model.refresh() {
                imageCache.removeAll()
                imageRefreshGeneration += 1
            }
        }
        .accessibilityIdentifier("categories-content")
    }
}

private struct CategoryCard: View {
    let category: ComicCategory
    let imageCache: CategoryImageCache
    let imageURLBuilder: ImageURLBuilder
    let refreshGeneration: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            categoryImage
                .aspectRatio(1.4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(category.title)
                .font(.headline)
                .lineLimit(1)

            if let description = category.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("category-\(category.id)")
    }

    @ViewBuilder
    private var categoryImage: some View {
        if let thumb = category.thumb, let url = imageURLBuilder.url(for: thumb) {
            StableCategoryImage(
                categoryID: category.id,
                url: url,
                cache: imageCache,
                refreshGeneration: refreshGeneration
            )
        } else {
            imagePlaceholder(systemImage: "photo")
        }
    }

    private func imagePlaceholder(systemImage: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.32), .indigo.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

private struct StableCategoryImage: View {
    private enum Phase {
        case loading
        case success(UIImage)
        case failure
    }

    let categoryID: String
    let url: URL
    let cache: CategoryImageCache
    let refreshGeneration: Int
    @State private var phase: Phase

    init(
        categoryID: String,
        url: URL,
        cache: CategoryImageCache,
        refreshGeneration: Int
    ) {
        self.categoryID = categoryID
        self.url = url
        self.cache = cache
        self.refreshGeneration = refreshGeneration
        _phase = State(
            initialValue: cache.image(for: categoryID).map(Phase.success) ?? .loading
        )
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ZStack {
                    placeholder(systemImage: "photo")
                    ProgressView()
                }
            case let .success(image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder(systemImage: "photo.badge.exclamationmark")
            }
        }
        .task(id: refreshGeneration) {
            if let image = cache.image(for: categoryID) {
                phase = .success(image)
                return
            }

            phase = .loading
            do {
                phase = .success(
                    try await cache.load(
                        categoryID: categoryID,
                        from: url,
                        reloadIgnoringURLCache: refreshGeneration > 0
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                phase = .failure
            }
        }
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.32), .indigo.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}
