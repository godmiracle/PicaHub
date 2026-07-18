//
//  PicaHubApp.swift
//  PicaHub
//
//  Created by vivian on 2026/7/18.
//

import SwiftUI

@main
struct PicaHubApp: App {
    private let dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            ContentView(
                accountRepository: dependencies.accountRepository,
                categoryRepository: dependencies.categoryRepository,
                comicRepository: dependencies.comicRepository,
                categoryImageCache: dependencies.categoryImageCache,
                imageURLBuilder: dependencies.imageURLBuilder
            )
        }
    }
}
