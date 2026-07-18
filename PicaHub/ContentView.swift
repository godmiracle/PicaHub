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
    private let favoriteRepository: any FavoriteRepository
    private let categoryImageCache: CategoryImageCache
    private let imageURLBuilder: ImageURLBuilder
    private let readerDependencies: ReaderDependencies

    init(
        accountRepository: any AccountRepository,
        categoryRepository: any CategoryRepository,
        comicRepository: any ComicRepository,
        comicDetailsRepository: any ComicDetailsRepository,
        favoriteRepository: any FavoriteRepository,
        categoryImageCache: CategoryImageCache,
        imageURLBuilder: ImageURLBuilder,
        readerDependencies: ReaderDependencies
    ) {
        self.accountRepository = accountRepository
        self.categoryRepository = categoryRepository
        self.comicRepository = comicRepository
        self.comicDetailsRepository = comicDetailsRepository
        self.favoriteRepository = favoriteRepository
        self.categoryImageCache = categoryImageCache
        self.imageURLBuilder = imageURLBuilder
        self.readerDependencies = readerDependencies
    }

    var body: some View {
        AppRootView(
            repository: accountRepository,
            categoryRepository: categoryRepository,
            comicRepository: comicRepository,
            comicDetailsRepository: comicDetailsRepository,
            favoriteRepository: favoriteRepository,
            categoryImageCache: categoryImageCache,
            imageURLBuilder: imageURLBuilder,
            readerDependencies: readerDependencies
        )
    }
}
