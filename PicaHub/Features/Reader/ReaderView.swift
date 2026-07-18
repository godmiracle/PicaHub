import SwiftUI

struct ReaderView: View {
    @State private var model: ReaderChapterModel
    private let comicTitle: String
    private let imageURLBuilder: ImageURLBuilder
    private let imagePipeline: ImagePipeline
    private let cancellationController: ReaderImageCancellationController

    @MainActor
    init(
        comicID: String,
        comicTitle: String,
        chapters: [Chapter],
        initialChapter: Chapter,
        repository: any ChapterImageRepository,
        imageURLBuilder: ImageURLBuilder,
        imagePipeline: ImagePipeline,
        progressStore: any ReadingProgressStore = UserDefaultsReadingProgressStore()
    ) {
        let cancellationController = ReaderImageCancellationController()
        self.cancellationController = cancellationController
        self.comicTitle = comicTitle
        self.imageURLBuilder = imageURLBuilder
        self.imagePipeline = imagePipeline
        _model = State(
            initialValue: ReaderChapterModel(
                comicID: comicID,
                chapters: chapters,
                initialChapter: initialChapter,
                repository: repository,
                progressStore: progressStore,
                cancelImageWork: { cancellationController.cancelAll() }
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            metadataHeader
            content
            chapterNavigation
        }
        .background(Color.black)
        .foregroundStyle(.white)
        .navigationTitle(comicTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.restoreProgressAndLoad() }
        .onDisappear { model.cancel() }
        .accessibilityIdentifier("reader")
    }

    private var metadataHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.currentChapter.title)
                    .font(.headline)
                Text("第 \(model.currentChapter.order) 话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !model.images.isEmpty {
                Text("\(model.currentImageIndex + 1) / \(model.images.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader-metadata")
    }

    @ViewBuilder
    private var content: some View {
        switch model.contentState {
        case .idle, .loading:
            ProgressView("正在加载章节图片")
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("reader-images-loading")
        case .content:
            VerticalReaderView(
                images: model.images,
                imageURLBuilder: imageURLBuilder,
                imagePipeline: imagePipeline,
                initialVisibleIndex: model.currentImageIndex,
                cancellationController: cancellationController,
                onVisibleIndexChanged: { model.updateVisibleImageIndex($0) }
            )
            .id(model.currentChapter.id)
        case .empty:
            ContentUnavailableView {
                Label("本章暂无图片", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("可以返回详情或切换到其他章节。")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("reader-images-empty")
        case let .failed(message):
            ContentUnavailableView {
                Label("章节图片加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { model.loadCurrentChapter() }
                    .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("reader-images-error")
        }
    }

    private var chapterNavigation: some View {
        HStack(spacing: 12) {
            Button("上一章", systemImage: "chevron.left") {
                model.goToPreviousChapter()
            }
            .disabled(model.previousChapter == nil || model.isLoading)
            Spacer()
            Button("下一章", systemImage: "chevron.right") {
                model.goToNextChapter()
            }
            .labelStyle(.titleAndIcon)
            .disabled(model.nextChapter == nil || model.isLoading)
        }
        .buttonStyle(.bordered)
        .padding(12)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("reader-chapter-navigation")
    }
}
