import SwiftUI
import UIKit

struct ReaderView: View {
    @State private var model: ReaderChapterModel
    @State private var settings = ReaderSettings()
    @State private var toolbarState = ReaderToolbarState()
    private let comicTitle: String
    private let imageURLBuilder: ImageURLBuilder
    private let imagePipeline: ImagePipeline
    private let cancellationController: ReaderImageCancellationController
    private let restoresLastProgress: Bool
    private let settingsStore: any ReaderSettingsStore
    private let idleTimerController: ReaderIdleTimerController
    @Environment(\.colorScheme) private var colorScheme

    @MainActor
    init(
        comicID: String,
        comicTitle: String,
        chapters: [Chapter],
        initialChapter: Chapter,
        repository: any ChapterImageRepository,
        imageURLBuilder: ImageURLBuilder,
        imagePipeline: ImagePipeline,
        progressStore: any ReadingProgressStore = UserDefaultsReadingProgressStore(),
        restoresLastProgress: Bool = false,
        settingsStore: (any ReaderSettingsStore)? = nil
    ) {
        let cancellationController = ReaderImageCancellationController()
        self.cancellationController = cancellationController
        self.comicTitle = comicTitle
        self.imageURLBuilder = imageURLBuilder
        self.imagePipeline = imagePipeline
        self.restoresLastProgress = restoresLastProgress
        self.settingsStore = settingsStore ?? UserDefaultsReaderSettingsStore()
        idleTimerController = ReaderIdleTimerController()
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
        ZStack {
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toolbarState.handleSurfaceTap()
                    }
                }
            if toolbarState.isVisible {
                VStack(spacing: 0) {
                    metadataHeader
                    Spacer()
                    chapterNavigation
                }
                .transition(.opacity)
            }
        }
        .background(readerBackground)
        .foregroundStyle(readerForeground)
        .navigationTitle(comicTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            settings = settingsStore.load()
            idleTimerController.apply(keepScreenAwake: settings.keepScreenAwake)
            if restoresLastProgress {
                await model.restoreProgressAndLoad()
            } else {
                await model.loadSelectedChapter()
            }
        }
        .onChange(of: settings) { _, value in
            settingsStore.save(value)
            idleTimerController.apply(keepScreenAwake: value.keepScreenAwake)
        }
        .onDisappear {
            model.cancel()
            idleTimerController.restore()
        }
        .accessibilityIdentifier("reader")
    }

    private var readerBackground: Color {
        switch settings.backgroundMode {
        case .black:
            return .black
        case .darkGray:
            return Color(red: 0.12, green: 0.12, blue: 0.13)
        case .system:
            return colorScheme == .dark ? .black : Color(uiColor: .systemBackground)
        }
    }

    private var readerForeground: Color {
        switch settings.backgroundMode {
        case .system:
            return colorScheme == .dark ? .white : .primary
        case .black, .darkGray:
            return .white
        }
    }

    private var metadataHeader: some View {
        HStack(spacing: 10) {
            ChapterMetadataView(chapter: model.currentChapter)
            Spacer()
            if !model.images.isEmpty {
                Text("\(model.currentImageIndex + 1) / \(model.images.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            settingsMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader-metadata")
    }

    private var settingsMenu: some View {
        Menu {
            Picker("背景", selection: $settings.backgroundMode) {
                Text("纯黑").tag(ReaderBackgroundMode.black)
                Text("深灰").tag(ReaderBackgroundMode.darkGray)
                Text("跟随系统").tag(ReaderBackgroundMode.system)
            }
            Toggle("自动隐藏工具栏", isOn: $settings.autoHideToolbar)
            Toggle("保持屏幕常亮", isOn: $settings.keepScreenAwake)
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("阅读器设置")
    }

    @ViewBuilder
    private var content: some View {
        switch model.contentState {
        case .idle, .loading:
            ProgressView("正在加载章节图片")
                .tint(readerForeground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("reader-images-loading")
        case .content:
            VerticalReaderView(
                images: model.images,
                imageURLBuilder: imageURLBuilder,
                imagePipeline: imagePipeline,
                initialVisibleIndex: model.currentImageIndex,
                cancellationController: cancellationController,
                onVisibleIndexChanged: { model.updateVisibleImageIndex($0) },
                onScrollActivity: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        toolbarState.handleScroll(autoHideEnabled: settings.autoHideToolbar)
                    }
                },
                backgroundColor: readerBackground,
                foregroundColor: readerForeground
            )
            .id(model.currentChapter.id)
        case .empty:
            ContentUnavailableView {
                Label("本章暂无图片", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("可以返回详情或切换到其他章节。")
            }
            .foregroundStyle(readerForeground)
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
            .foregroundStyle(readerForeground)
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
