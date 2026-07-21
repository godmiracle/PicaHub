import Foundation
import Testing
@testable import PicaHub

@MainActor
struct ReaderSettingsTests {
    @Test func settingsPersistAndInvalidDataFallsBackToDefaults() throws {
        let suiteName = "PicaHubTests.ReaderSettings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsReaderSettingsStore(defaults: defaults)
        let expected = ReaderSettings(
            backgroundMode: .darkGray,
            autoHideToolbar: false,
            keepScreenAwake: false
        )

        store.save(expected)
        #expect(store.load() == expected)

        defaults.set(Data("invalid".utf8), forKey: "PicaHub.reader.settings")
        #expect(store.load() == ReaderSettings())
    }

    @Test func toolbarOnlyHidesWhenEnabledAndTapRestoresVisibility() {
        var state = ReaderToolbarState()

        state.handleScroll(autoHideEnabled: false)
        #expect(state.isVisible)

        state.handleScroll(autoHideEnabled: true)
        #expect(!state.isVisible)

        state.handleSurfaceTap()
        #expect(state.isVisible)
    }

    @Test func idleTimerRestoresTheEntryValueExactlyOnce() {
        var writes: [Bool] = []
        let controller = ReaderIdleTimerController(
            readValue: { true },
            writeValue: { writes.append($0) }
        )

        controller.apply(keepScreenAwake: false)
        controller.apply(keepScreenAwake: true)
        controller.restore()
        controller.restore()

        #expect(writes == [false, true, true])
    }
}
