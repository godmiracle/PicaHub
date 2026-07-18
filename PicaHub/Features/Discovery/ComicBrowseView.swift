import SwiftUI

struct ComicBrowseView: View {
    @State private var model: ComicBrowseModel
    private let imageURLBuilder: ImageURLBuilder

    init(
        category: String,
        repository: any ComicRepository,
        imageURLBuilder: ImageURLBuilder
    ) {
        _model = State(initialValue: ComicBrowseModel(category: category, repository: repository))
        self.imageURLBuilder = imageURLBuilder
    }

    var body: some View {
        content
            .navigationTitle(model.category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { sortMenu }
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
    }

    @ToolbarContentBuilder
    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(ComicSort.allCases, id: \.self) { sort in
                    Button {
                        Task { await model.changeSort(to: sort) }
                    } label: {
                        if model.sort == sort {
                            Label(sort.displayName, systemImage: "checkmark")
                        } else {
                            Text(sort.displayName)
                        }
                    }
                }
            } label: {
                Label("排序", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("comic-sort-menu")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("正在加载漫画")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("comics-loading")
        case let .content(content):
            comicList(content)
        case .empty:
            ContentUnavailableView {
                Label("暂无漫画", systemImage: "books.vertical")
            } description: {
                Text("这个分类暂时没有可浏览的漫画。")
            } actions: {
                Button("重新加载") { Task { await model.retry() } }
            }
            .accessibilityIdentifier("comics-empty")
        case let .failed(message):
            ContentUnavailableView {
                Label("漫画加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { Task { await model.retry() } }
                    .buttonStyle(.borderedProminent)
            }
            .accessibilityIdentifier("comics-error")
        }
    }

    private func comicList(_ content: ComicBrowseModel.Content) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(content.comics) { comic in
                    ComicBrowseRow(comic: comic, imageURLBuilder: imageURLBuilder)
                        .task {
                            await model.loadNextPageIfNeeded(after: comic.id)
                        }
                    Divider().padding(.leading, 16)
                }
                paginationFooter(content)
            }
        }
        .overlay(alignment: .top) {
            if content.isRefreshing {
                ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .refreshable { await model.refresh() }
        .accessibilityIdentifier("comics-content")
    }

    @ViewBuilder
    private func paginationFooter(_ content: ComicBrowseModel.Content) -> some View {
        if content.isLoadingNextPage {
            ProgressView("加载更多")
                .padding(20)
                .accessibilityIdentifier("comics-next-loading")
        } else if let message = content.nextPageErrorMessage {
            VStack(spacing: 8) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("重试加载更多") { Task { await model.retryNextPage() } }
            }
            .padding(20)
            .accessibilityIdentifier("comics-next-error")
        } else if content.currentPage >= content.totalPages {
            Text("已经到底了")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(20)
        }
    }
}

private struct ComicBrowseRow: View {
    let comic: ComicSummary
    let imageURLBuilder: ImageURLBuilder

    var body: some View {
        let presentation = ComicRowPresentation(comic: comic)
        HStack(alignment: .top, spacing: 12) {
            ComicCoverView(
                url: imageURLBuilder.url(for: comic.thumb),
                comicID: comic.id
            )
            .frame(width: 90, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(2)

                Label(presentation.author, systemImage: "person")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .lineLimit(1)

                if !presentation.categories.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(presentation.categories, id: \.self) { category in
                            Text(category)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 0)

                Text("\(presentation.pages) · \(presentation.episodes) · \(presentation.status)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 14) {
                    Label(presentation.likes, systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                    Label(presentation.views, systemImage: "eye.fill")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 140)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityIdentifier("comic-\(comic.id)")
    }
}

private struct ComicCoverView: View {
    let comicID: String
    @State private var model: ComicCoverModel?

    init(url: URL?, comicID: String) {
        self.comicID = comicID
        _model = State(initialValue: url.map { ComicCoverModel(url: $0) })
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.28), .indigo.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let model {
                switch model.state {
                case .idle, .loading:
                    ProgressView()
                case .loaded:
                    if let image = model.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                case .failed:
                    Button {
                        Task { await model.retry() }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                            Text("重试")
                                .font(.caption2)
                        }
                    }
                    .accessibilityIdentifier("cover-retry-\(comicID)")
                }
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
        }
        .task { await model?.loadIfNeeded() }
        .accessibilityIdentifier("cover-\(comicID)")
    }
}

private extension ComicSort {
    var displayName: String {
        switch self {
        case .newest: "新到旧"
        case .oldest: "旧到新"
        case .mostLiked: "最多喜欢"
        case .mostViewed: "最多观看"
        }
    }
}
