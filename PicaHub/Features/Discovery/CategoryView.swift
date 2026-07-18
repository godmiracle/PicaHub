import SwiftUI

struct CategoryView: View {
    @State private var model: CategoryModel
    private let imageURLBuilder: ImageURLBuilder
    private let onLogout: @MainActor () -> Void

    init(
        repository: any CategoryRepository,
        imageURLBuilder: ImageURLBuilder,
        onLogout: @escaping @MainActor () -> Void
    ) {
        _model = State(initialValue: CategoryModel(repository: repository))
        self.imageURLBuilder = imageURLBuilder
        self.onLogout = onLogout
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("发现")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
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
                    CategoryCard(category: category, imageURLBuilder: imageURLBuilder)
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
        .refreshable { await model.refresh() }
        .accessibilityIdentifier("categories-content")
    }
}

private struct CategoryCard: View {
    let category: ComicCategory
    let imageURLBuilder: ImageURLBuilder

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
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    imagePlaceholder(systemImage: "photo.badge.exclamationmark")
                default:
                    ZStack {
                        imagePlaceholder(systemImage: "photo")
                        ProgressView()
                    }
                }
            }
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
