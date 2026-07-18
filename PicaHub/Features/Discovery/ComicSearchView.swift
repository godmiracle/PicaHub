import SwiftUI

struct ComicSearchView: View {
    @State private var query = ""
    @State private var model: ComicSearchModel
    private let imageURLBuilder: ImageURLBuilder
    private let detailsRepository: any ComicDetailsRepository
    private let favoriteRepository: any FavoriteRepository
    private let readerDependencies: ReaderDependencies

    init(
        repository: any ComicRepository,
        detailsRepository: any ComicDetailsRepository,
        favoriteRepository: any FavoriteRepository,
        imageURLBuilder: ImageURLBuilder,
        readerDependencies: ReaderDependencies
    ) {
        _model = State(initialValue: ComicSearchModel(repository: repository))
        self.detailsRepository = detailsRepository
        self.favoriteRepository = favoriteRepository
        self.imageURLBuilder = imageURLBuilder
        self.readerDependencies = readerDependencies
    }

    var body: some View {
        content
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索漫画"
            )
            .onSubmit(of: .search) { Task { await model.search(query) } }
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

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            ContentUnavailableView {
                Label("搜索漫画", systemImage: "magnifyingglass")
            } description: {
                Text(model.validationMessage ?? "输入关键词后点击键盘上的搜索。")
            }
            .accessibilityIdentifier("search-idle")
        case let .loading(keyword):
            ProgressView("正在搜索“\(keyword)”")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("search-loading")
        case let .content(content):
            resultList(content)
        case let .noResults(keyword):
            ContentUnavailableView.search(text: keyword)
                .accessibilityIdentifier("search-no-results")
        case let .failed(_, message):
            ContentUnavailableView {
                Label("搜索失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { Task { await model.retry() } }
                    .buttonStyle(.borderedProminent)
            }
            .accessibilityIdentifier("search-error")
        }
    }

    private func resultList(_ content: ComicSearchModel.Content) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(content.comics) { comic in
                    NavigationLink {
                        ComicDetailsView(
                            comicID: comic.id,
                            repository: detailsRepository,
                            favoriteRepository: favoriteRepository,
                            imageURLBuilder: imageURLBuilder,
                            readerDependencies: readerDependencies
                        )
                    } label: {
                        ComicBrowseRow(comic: comic, imageURLBuilder: imageURLBuilder)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("open-comic-\(comic.id)")
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
        .accessibilityIdentifier("search-content")
    }

    @ViewBuilder
    private func paginationFooter(_ content: ComicSearchModel.Content) -> some View {
        if content.isLoadingNextPage {
            ProgressView("加载更多").padding(20)
        } else if let message = content.nextPageErrorMessage {
            VStack(spacing: 8) {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("重试加载更多") { Task { await model.retryNextPage() } }
            }
            .padding(20)
        } else if content.currentPage >= content.totalPages {
            Text("已经到底了")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(20)
        }
    }
}
