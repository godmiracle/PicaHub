import Foundation

@MainActor
struct ReaderDependencies {
    let chapterImageRepository: any ChapterImageRepository
    let imagePipeline: ImagePipeline
    let progressStore: any ReadingProgressStore
}
