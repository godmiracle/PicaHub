import Foundation
import UIKit

enum ReaderBackgroundMode: String, Codable, CaseIterable, Sendable {
    case black
    case darkGray
    case system
}

struct ReaderSettings: Codable, Equatable, Sendable {
    var backgroundMode: ReaderBackgroundMode = .black
    var autoHideToolbar = true
    var keepScreenAwake = true
}

@MainActor
protocol ReaderSettingsStore {
    func load() -> ReaderSettings
    func save(_ settings: ReaderSettings)
}

@MainActor
final class UserDefaultsReaderSettingsStore: ReaderSettingsStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "PicaHub.reader.settings") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> ReaderSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ReaderSettings.self, from: data)
        else { return ReaderSettings() }
        return settings
    }

    func save(_ settings: ReaderSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

struct ReaderToolbarState: Equatable {
    private(set) var isVisible = true

    mutating func handleScroll(autoHideEnabled: Bool) {
        guard autoHideEnabled else { return }
        isVisible = false
    }

    mutating func handleSurfaceTap() {
        isVisible.toggle()
    }
}

@MainActor
final class ReaderIdleTimerController {
    typealias ReadValue = @MainActor () -> Bool
    typealias WriteValue = @MainActor (Bool) -> Void

    private let previousValue: Bool
    private let writeValue: WriteValue
    private var isRestored = false

    init(
        readValue: ReadValue = { UIApplication.shared.isIdleTimerDisabled },
        writeValue: @escaping WriteValue = { UIApplication.shared.isIdleTimerDisabled = $0 }
    ) {
        previousValue = readValue()
        self.writeValue = writeValue
    }

    func apply(keepScreenAwake: Bool) {
        guard !isRestored else { return }
        writeValue(keepScreenAwake)
    }

    func restore() {
        guard !isRestored else { return }
        isRestored = true
        writeValue(previousValue)
    }
}
