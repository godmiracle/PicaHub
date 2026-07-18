import SwiftUI

struct ProtocolSpikeView: View {
    @State private var model = ProtocolSpikeModel()
    @State private var confirmsFavoriteMutation = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Section("本地账号") {
                    TextField("邮箱", text: $model.email)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码（不会保存）", text: $model.password)
                        .textContentType(.password)
                }

                Section("API 路线") {
                    Picker("Host", selection: $model.host) {
                        ForEach(ProtocolSpikeModel.Host.allCases) { host in
                            Text(host.rawValue).tag(host)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("协议门禁") {
                    LabeledContent("状态", value: model.status.title)
                    LabeledContent("当前步骤", value: model.currentStep)

                    if case let .failed(message) = model.status {
                        Text(message)
                            .foregroundStyle(.red)
                    }

                    if model.isRunning {
                        ProgressView()
                        Button("取消", role: .cancel) {
                            model.cancel()
                        }
                    } else {
                        Button("运行只读 Spike") {
                            model.startReadOnlySpike()
                        }
                    }

                    if model.canRunFavoriteMutation, !model.isRunning {
                        Button("验证收藏写入与恢复") {
                            confirmsFavoriteMutation = true
                        }
                    }
                }

                if !model.logs.isEmpty {
                    Section("验证记录") {
                        ForEach(Array(model.logs.enumerated()), id: \.offset) { _, message in
                            Text(message)
                                .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("PicaHub 协议 Spike")
            .alert("确认收藏写入测试？", isPresented: $confirmsFavoriteMutation) {
                Button("取消", role: .cancel) {}
                Button("继续", role: .destructive) {
                    model.runFavoriteMutation()
                }
            } message: {
                Text("测试会临时切换一个样本漫画的收藏状态，完成后自动恢复；网络中断时会尽力回滚。")
            }
        }
    }
}

#Preview {
    ProtocolSpikeView()
}
