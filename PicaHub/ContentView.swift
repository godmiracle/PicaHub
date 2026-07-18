//
//  ContentView.swift
//  PicaHub
//
//  Created by vivian on 2026/7/18.
//

import SwiftUI

struct ContentView: View {
    private let accountRepository: any AccountRepository
    private let categoryRepository: any CategoryRepository
    private let comicRepository: any ComicRepository
    private let comicDetailsRepository: any ComicDetailsRepository
    private let categoryImageCache: CategoryImageCache
    private let imageURLBuilder: ImageURLBuilder

    init(
        accountRepository: any AccountRepository,
        categoryRepository: any CategoryRepository,
        comicRepository: any ComicRepository,
        comicDetailsRepository: any ComicDetailsRepository,
        categoryImageCache: CategoryImageCache,
        imageURLBuilder: ImageURLBuilder
    ) {
        self.accountRepository = accountRepository
        self.categoryRepository = categoryRepository
        self.comicRepository = comicRepository
        self.comicDetailsRepository = comicDetailsRepository
        self.categoryImageCache = categoryImageCache
        self.imageURLBuilder = imageURLBuilder
    }

    var body: some View {
        AppRootView(
            repository: accountRepository,
            categoryRepository: categoryRepository,
            comicRepository: comicRepository,
            comicDetailsRepository: comicDetailsRepository,
            categoryImageCache: categoryImageCache,
            imageURLBuilder: imageURLBuilder
        )
    }
}
