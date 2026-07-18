//
//  ContentView.swift
//  PicaHub
//
//  Created by vivian on 2026/7/18.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
#if DEBUG
        ProtocolSpikeView()
#else
        ContentUnavailableView(
            "协议验证版本",
            systemImage: "checkmark.shield",
            description: Text("请使用 Debug 构建完成协议门禁验证")
        )
#endif
    }
}

#Preview {
    ContentView()
}
