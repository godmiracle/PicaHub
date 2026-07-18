import SwiftUI

struct FavoritesView: View {
    @State private var model: FavoritesModel
    private let repository: any FavoriteRepository
    private let detailsRepository: any ComicDetailsRepository
    private let imageURLBuilder: ImageURLBuilder
    private let readerDependencies: ReaderDependencies

    init(
        repository: any FavoriteRepository,
        detailsRepository: any ComicDetailsRepository,
        imageURLBuilder: ImageURLBuilder,
        readerDependencies: ReaderDependencies
    ) {
        _model = State(initialValue: FavoritesModel(repository: repository))
        self.repository = repository
        self.detailsRepository = detailsRepository
        self.imageURLBuilder = imageURLBuilder
        self.readerDependencies = readerDependencies
    }

    var body: some View {
        content
            .navigationTitle("我的收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { sortMenu }
            .task { await model.loadIfNeeded() }
            .onDisappear { model.cancel() }
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
                            Label(sort.favoriteDisplayName, systemImage: "checkmark")
                        } else {
                            Text(sort.favoriteDisplayName)
                        }
                    }
                }
            } label: {
                Label("排序", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("favorite-sort-menu")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("正在加载收藏")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("favorites-loading")
        case let .content(content):
            favoriteList(content)
        case .empty:
            ContentUnavailableView {
                Label("暂无收藏", systemImage: "heart.slash")
            } description: {
                Text("收藏漫画后，它们会出现在这里。")
            } actions: {
                Button("重新加载") { Task { await model.retry() } }
            }
            .accessibilityIdentifier("favorites-empty")
        case let .failed(message):
            ContentUnavailableView {
                Label("收藏加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { Task { await model.retry() } }
                    .buttonStyle(.borderedProminent)
            }
            .accessibilityIdentifier("favorites-error")
        }
    }

    private func favoriteList(_ content: FavoritesModel.Content) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(content.comics) { comic in
                    NavigationLink {
                        ComicDetailsView(
                            comicID: comic.id,
                            repository: detailsRepository,
                            favoriteRepository: repository,
                            imageURLBuilder: imageURLBuilder,
                            readerDependencies: readerDependencies,
                            onConfirmedFavoriteChange: { comicID, isFavorite in
                                Task {
                                    await model.applyConfirmedFavoriteChange(
                                        comicID: comicID,
                                        isFavorite: isFavorite
                                    )
                                }
                            }
                        )
                    } label: {
                        ComicBrowseRow(comic: comic, imageURLBuilder: imageURLBuilder)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("open-favorite-\(comic.id)")
                    .task { await model.loadNextPageIfNeeded(after: comic.id) }
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
        .accessibilityIdentifier("favorites-content")
    }

    @ViewBuilder
    private func paginationFooter(_ content: FavoritesModel.Content) -> some View {
        if content.isLoadingNextPage {
            ProgressView("加载更多")
                .padding(20)
                .accessibilityIdentifier("favorites-next-loading")
        } else if let message = content.nextPageErrorMessage {
            VStack(spacing: 8) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("重试加载更多") { Task { await model.retryNextPage() } }
            }
            .padding(20)
            .accessibilityIdentifier("favorites-next-error")
        } else if content.currentPage >= content.totalPages {
            Text("已经到底了")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(20)
        }
    }
}

private extension ComicSort {
    var favoriteDisplayName: String {
        switch self {
        case .newest: "新到旧"
        case .oldest: "旧到新"
        case .mostLiked: "最多喜欢"
        case .mostViewed: "最多观看"
        }
    }
}
