import SwiftUI

struct AppRootView: View {
    private let repository: any AccountRepository
    private let categoryRepository: any CategoryRepository
    private let categoryImageCache: CategoryImageCache
    private let imageURLBuilder: ImageURLBuilder
    @State private var model: AppRootModel
    @State private var confirmsLogout = false

    init(
        repository: any AccountRepository,
        categoryRepository: any CategoryRepository,
        categoryImageCache: CategoryImageCache,
        imageURLBuilder: ImageURLBuilder
    ) {
        self.repository = repository
        self.categoryRepository = categoryRepository
        self.categoryImageCache = categoryImageCache
        self.imageURLBuilder = imageURLBuilder
        _model = State(initialValue: AppRootModel(repository: repository))
    }

    var body: some View {
        Group {
            switch model.state {
            case .restoring:
                restoringView
            case .unauthenticated:
                loginView
            case .authenticating:
                restoringView
            case .authenticated:
                categoryView
            case let .failed(failure):
                restorationFailureView(failure)
            }
        }
        .task {
            await model.start()
        }
    }

    private var loginView: some View {
        LoginView(repository: repository) {
            Task { await model.synchronizeAfterLogin() }
        }
    }

    private var restoringView: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.10)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.purple)
                    .controlSize(.large)
                Text("正在恢复登录状态")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("安全读取本机 Keychain")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .accessibilityIdentifier("session-restoring")
    }

    private var categoryView: some View {
        CategoryView(
            repository: categoryRepository,
            imageCache: categoryImageCache,
            imageURLBuilder: imageURLBuilder,
            onLogout: { confirmsLogout = true }
        )
        .confirmationDialog("确认退出登录？", isPresented: $confirmsLogout) {
            Button("退出登录", role: .destructive) {
                Task { await model.logout() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本机 Keychain 中的登录状态将被清除。")
        }
    }

    private func restorationFailureView(_ failure: AccountSessionFailure) -> some View {
        ContentUnavailableView {
            Label("无法恢复登录状态", systemImage: "key.slash")
        } description: {
            Text(failure.message)
        } actions: {
            Button("重试") {
                Task { await model.restoreSession() }
            }
            .buttonStyle(.borderedProminent)
        }
        .accessibilityIdentifier("session-restoration-error")
    }
}
