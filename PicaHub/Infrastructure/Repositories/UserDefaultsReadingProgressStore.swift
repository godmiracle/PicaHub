import Foundation

actor UserDefaultsReadingProgressStore: ReadingProgressStore {
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "PicaHub.reader.progress."
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func loadProgress(for comicID: String) -> ReadingProgress? {
        guard let data = defaults.data(forKey: key(for: comicID)) else { return nil }
        guard let progress = try? JSONDecoder().decode(ReadingProgress.self, from: data) else {
            defaults.removeObject(forKey: key(for: comicID))
            return nil
        }
        return progress
    }

    func saveProgress(_ progress: ReadingProgress, for comicID: String) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: key(for: comicID))
    }

    func removeProgress(for comicID: String) {
        defaults.removeObject(forKey: key(for: comicID))
    }

    private func key(for comicID: String) -> String {
        keyPrefix + comicID
    }
}
