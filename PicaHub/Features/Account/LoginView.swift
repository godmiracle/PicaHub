import SwiftUI

struct LoginView: View {
    @State private var model: LoginModel
    @FocusState private var focusedField: Field?
    private let onAuthenticated: @MainActor () -> Void

    private enum Field {
        case email
        case password
    }

    init(
        repository: any AccountRepository,
        onAuthenticated: @escaping @MainActor () -> Void = {}
    ) {
        _model = State(initialValue: LoginModel(repository: repository))
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 48)
                    brand
                    loginCard(model: model)
                    privacyNote
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.045, blue: 0.10),
                    Color(red: 0.08, green: 0.055, blue: 0.16),
                    Color(red: 0.025, green: 0.035, blue: 0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.purple.opacity(0.28))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: 150, y: -280)

            Circle()
                .fill(Color.indigo.opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: -150, y: 300)
        }
        .ignoresSafeArea()
    }

    private var brand: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .shadow(color: .purple.opacity(0.45), radius: 22, y: 10)

            Text("PicaHub")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(red: 0.72, green: 0.38, blue: 1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("登录后继续你的漫画旅程")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func loginCard(model: LoginModel) -> some View {
        @Bindable var model = model

        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("邮箱")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                TextField("你的登录邮箱", text: $model.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .inputStyle()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("密码")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                SecureField("仅用于本次登录", text: $model.password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit(model) }
                    .inputStyle()
            }

            if case let .failed(message, isRetryable) = model.phase {
                Label(message, systemImage: isRetryable ? "wifi.exclamationmark" : "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Color(red: 1, green: 0.63, blue: 0.68))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("login-error")
            }

            Button {
                submit(model)
            } label: {
                Group {
                    if model.isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("登录")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [.purple, .indigo],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: .purple.opacity(0.32), radius: 16, y: 8)
            .disabled(model.isSubmitting)
            .accessibilityIdentifier("login-submit")
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var privacyNote: some View {
        Label("密码不会保存，登录状态仅存于本机 Keychain", systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
    }

    private func submit(_ model: LoginModel) {
        focusedField = nil
        Task {
            await model.submit()
            if model.phase == .authenticated {
                onAuthenticated()
            }
        }
    }
}

private extension View {
    func inputStyle() -> some View {
        padding(.horizontal, 14)
            .frame(height: 50)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
    }
}
