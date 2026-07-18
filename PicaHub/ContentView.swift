//
//  ContentView.swift
//  PicaHub
//
//  Created by vivian on 2026/7/18.
//

import SwiftUI

struct ContentView: View {
    private let repository: any AccountRepository

    init(repository: any AccountRepository) {
        self.repository = repository
    }

    var body: some View {
        AppRootView(repository: repository)
    }
}
