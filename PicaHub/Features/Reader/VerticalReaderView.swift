import SwiftUI

struct VerticalReaderView: View {
    @State private var model: ReaderImageModel
    private let images: [ChapterImage]
    private let initialVisibleIndex: Int
    private let cancellationController: ReaderImageCancellationController?
    private let onVisibleIndexChanged: (Int) -> Void

    init(
        images: [ChapterImage],
        imageURLBuilder: ImageURLBuilder,
        imagePipeline: ImagePipeline,
        lookAheadCount: Int = 2,
        maximumConcurrentLoads: Int = 3,
        initialVisibleIndex: Int = 0,
        cancellationController: ReaderImageCancellationController? = nil,
        onVisibleIndexChanged: @escaping (Int) -> Void = { _ in }
    ) {
        self.images = images
        self.initialVisibleIndex = images.isEmpty
            ? 0
            : min(max(0, initialVisibleIndex), images.count - 1)
        self.cancellationController = cancellationController
        self.onVisibleIndexChanged = onVisibleIndexChanged
        _model = State(
            initialValue: ReaderImageModel(
                urls: images.map { imageURLBuilder.url(for: $0.media) },
                loader: imagePipeline,
                lookAheadCount: lookAheadCount,
                maximumConcurrentLoads: maximumConcurrentLoads
            )
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(images.indices), id: \.self) { index in
                            imageView(at: index)
                                .id(index)
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: ReaderImageFramePreferenceKey.self,
                                            value: [index: geometry.frame(in: .named("reader-scroll"))]
                                        )
                                    }
                                }
                                .accessibilityIdentifier("reader-image-\(index)")
                        }
                    }
                }
                .coordinateSpace(name: "reader-scroll")
                .onPreferenceChange(ReaderImageFramePreferenceKey.self) { frames in
                    updateVisibleIndex(frames: frames, viewportHeight: viewport.size.height)
                }
            }
            .task {
                model.updateVisibleIndex(initialVisibleIndex)
                await Task.yield()
                proxy.scrollTo(initialVisibleIndex, anchor: .top)
            }
        }
        .background(Color.black)
        .onAppear {
            cancellationController?.install { model.cancelAll() }
        }
        .onDisappear {
            model.cancelAll()
            cancellationController?.remove()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            model.handleMemoryPressure()
        }
        .accessibilityIdentifier("vertical-reader")
    }

    @ViewBuilder
    private func imageView(at index: Int) -> some View {
        switch model.state(at: index) {
        case .idle, .loading:
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: 320)
        case let .loaded(image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        case let .failed(message):
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title)
                Text(message)
                    .font(.footnote)
                Button("重试") { model.retry(index) }
                    .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private func updateVisibleIndex(frames: [Int: CGRect], viewportHeight: CGFloat) {
        let viewport = CGRect(x: 0, y: 0, width: 1, height: viewportHeight)
        let visible = frames
            .filter { $0.value.maxY > viewport.minY && $0.value.minY < viewport.maxY }
            .min { lhs, rhs in
                abs(lhs.value.minY) < abs(rhs.value.minY)
            }
        if let index = visible?.key {
            model.updateVisibleIndex(index)
            onVisibleIndexChanged(index)
        }
    }
}

private struct ReaderImageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
