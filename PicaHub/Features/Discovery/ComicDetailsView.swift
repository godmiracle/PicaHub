import SwiftUI

struct ComicDetailsView: View {
    @State private var model: ComicDetailsModel
    private let imageURLBuilder: ImageURLBuilder
    private let readerDependencies: ReaderDependencies

    init(
        comicID: String,
        repository: any ComicDetailsRepository,
        favoriteRepository: any FavoriteRepository,
        imageURLBuilder: ImageURLBuilder,
        readerDependencies: ReaderDependencies,
        onConfirmedFavoriteChange: @escaping @MainActor (String, Bool) -> Void = { _, _ in }
    ) {
        _model = State(
            initialValue: ComicDetailsModel(
                comicID: comicID,
                repository: repository,
                favoriteRepository: favoriteRepository,
                onConfirmedFavoriteChange: onConfirmedFavoriteChange
            )
        )
        self.imageURLBuilder = imageURLBuilder
        self.readerDependencies = readerDependencies
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailsSection
                Divider()
                chaptersSection
            }
            .padding(16)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadIfNeeded() }
        .onDisappear { model.cancel() }
        .accessibilityIdentifier("comic-details")
    }

    private var navigationTitle: String {
        if case let .loaded(details) = model.detailsState { return details.title }
        return "漫画详情"
    }

    @ViewBuilder
    private var detailsSection: some View {
        switch model.detailsState {
        case .idle, .loading:
            ProgressView("正在加载详情")
                .frame(maxWidth: .infinity, minHeight: 180)
                .accessibilityIdentifier("comic-details-loading")
        case let .failed(message):
            failureCard(title: "详情加载失败", message: message) {
                Task { await model.retryDetails() }
            }
            .accessibilityIdentifier("comic-details-error")
        case let .loaded(details):
            detailsContent(details)
        }
    }

    private func detailsContent(_ details: ComicDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                ComicCoverView(
                    url: imageURLBuilder.url(for: details.thumb),
                    comicID: details.id
                )
                .frame(width: 120, height: 174)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 9) {
                    Text(details.title)
                        .font(.title2.bold())
                    Label(
                        normalized(details.author, fallback: "作者未知"),
                        systemImage: "person"
                    )
                    favoriteControl
                    Text(metadataLine(details))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Label(count(details.likesCount), systemImage: "heart.fill")
                        Label(count(details.viewsCount), systemImage: "eye.fill")
                        Label(count(details.commentsCount), systemImage: "bubble.left.fill")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            let tags = unique(details.tags ?? [])
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }

            Text(normalized(details.description, fallback: "暂无简介"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("comic-details-content")
    }

    @ViewBuilder
    private var favoriteControl: some View {
        if let isFavorite = model.confirmedFavoriteState {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { await model.toggleFavorite() }
                } label: {
                    HStack(spacing: 7) {
                        if model.favoriteOperation == .updating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Label(
                            isFavorite ? "已收藏" : "收藏",
                            systemImage: isFavorite ? "heart.fill" : "heart"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .tint(isFavorite ? .pink : .secondary)
                .disabled(model.favoriteOperation != .idle)
                .accessibilityIdentifier("favorite-toggle")

                if let message = model.favoriteErrorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Button {
                        Task { await model.refreshFavoriteState() }
                    } label: {
                        if model.favoriteOperation == .refreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("刷新收藏状态")
                        }
                    }
                    .font(.caption)
                    .disabled(model.favoriteOperation != .idle)
                    .accessibilityIdentifier("favorite-refresh")
                }
            }
        }
    }

    @ViewBuilder
    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("章节")
                .font(.title3.bold())

            switch model.chaptersState {
            case .idle, .loading:
                ProgressView("正在加载章节")
                    .frame(maxWidth: .infinity, minHeight: 90)
                    .accessibilityIdentifier("comic-chapters-loading")
            case let .failed(message):
                failureCard(title: "章节加载失败", message: message) {
                    Task { await model.retryChapters() }
                }
                .accessibilityIdentifier("comic-chapters-error")
            case let .loaded(chapters):
                if chapters.isEmpty {
                    Text("暂无章节")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .accessibilityIdentifier("comic-chapters-empty")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(chapters) { chapter in
                            NavigationLink {
                                ReaderView(
                                    comicID: model.comicID,
                                    comicTitle: navigationTitle,
                                    chapters: chapters,
                                    initialChapter: chapter,
                                    repository: readerDependencies.chapterImageRepository,
                                    imageURLBuilder: imageURLBuilder,
                                    imagePipeline: readerDependencies.imagePipeline,
                                    progressStore: readerDependencies.progressStore
                                )
                            } label: {
                                HStack {
                                    Text(chapter.title)
                                    Spacer()
                                    Text("#\(chapter.order)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 11)
                            .accessibilityIdentifier("open-reader-\(chapter.id)")
                            Divider()
                        }
                    }
                    .accessibilityIdentifier("comic-chapters-content")
                }
            }
        }
    }

    private func failureCard(
        title: String,
        message: String,
        retry: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func normalized(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        return value
    }

    private func metadataLine(_ details: ComicDetails) -> String {
        let pages = details.pagesCount.map { "\($0)P" } ?? "页数未知"
        let episodes = details.epsCount.map { "\($0)话" } ?? "章节未知"
        let status = details.finished.map { $0 ? "完结" : "连载" } ?? "状态未知"
        return "\(pages) · \(episodes) · \(status)"
    }

    private func count(_ value: Int?) -> String {
        value.map(String.init) ?? "--"
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
