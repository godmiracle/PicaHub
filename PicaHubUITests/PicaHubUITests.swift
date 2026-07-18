import XCTest

final class PicaHubUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSuccessfulLoginAndLogout() throws {
        let app = makeApp()
        app.launch()

        app.textFields["你的登录邮箱"].tap()
        app.textFields["你的登录邮箱"].typeText("success@example.com")
        app.secureTextFields["仅用于本次登录"].tap()
        app.secureTextFields["仅用于本次登录"].typeText("password")
        app.buttons["login-submit"].tap()

        XCTAssertTrue(authenticatedElement(in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["categories-content"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["category-ui-test-category"].firstMatch.exists)

        app.buttons["退出登录"].tap()
        let confirmation = app.sheets.buttons["退出登录"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.tap()
        XCTAssertTrue(app.textFields["你的登录邮箱"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRejectedLoginShowsErrorAndClearsPassword() throws {
        let app = makeApp()
        app.launch()

        app.textFields["你的登录邮箱"].tap()
        app.textFields["你的登录邮箱"].typeText("user@example.com")
        app.secureTextFields["仅用于本次登录"].tap()
        app.secureTextFields["仅用于本次登录"].typeText("wrong-password")
        app.buttons["login-submit"].tap()

        XCTAssertTrue(app.staticTexts["login-error"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["仅用于本次登录"].exists)
        XCTAssertEqual(app.textFields["你的登录邮箱"].value as? String, "user@example.com")
    }

    @MainActor
    func testAuthenticatedSessionRestoresAcrossRelaunch() throws {
        let app = makeApp(authenticated: true)
        app.launch()
        XCTAssertTrue(authenticatedElement(in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["categories-content"].firstMatch.exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(authenticatedElement(in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["categories-content"].firstMatch.exists)
    }

    @MainActor
    func testCategoryOpensPaginatedComicBrowse() throws {
        let app = makeApp(authenticated: true)
        app.launch()

        let category = app.descendants(matching: .any)["category-ui-test-category"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 3))
        category.tap()

        XCTAssertTrue(app.descendants(matching: .any)["comics-content"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["comic-ui-test-comic"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["测试作者"].exists)
        XCTAssertTrue(app.buttons["comic-sort-menu"].exists)
    }

    @MainActor
    func testComicSearchPresentsResults() throws {
        let app = makeApp(authenticated: true)
        app.launch()

        let openSearch = app.descendants(matching: .any)["open-comic-search"].firstMatch
        XCTAssertTrue(openSearch.waitForExistence(timeout: 3))
        openSearch.tap()

        let search = app.searchFields["搜索漫画"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("测试\n")

        XCTAssertTrue(app.descendants(matching: .any)["search-content"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["comic-ui-test-comic"].firstMatch.exists)
    }

    @MainActor
    func testComicOpensDetailsAndChapters() throws {
        let app = makeApp(authenticated: true)
        app.launch()

        let category = app.descendants(matching: .any)["category-ui-test-category"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 3))
        category.tap()

        let comic = app.descendants(matching: .any)["open-comic-ui-test-comic"].firstMatch
        XCTAssertTrue(comic.waitForExistence(timeout: 3))
        comic.tap()

        XCTAssertTrue(app.navigationBars["UI 测试漫画"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["用于验证详情与章节独立加载。"].exists)
        XCTAssertTrue(app.staticTexts["第一话"].exists)
    }

    @MainActor
    func testChapterOpensReaderAndShowsEmptyChapterState() throws {
        let app = makeApp(authenticated: true)
        app.launch()

        let category = app.descendants(matching: .any)["category-ui-test-category"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 3))
        category.tap()
        let comic = app.descendants(matching: .any)["open-comic-ui-test-comic"].firstMatch
        XCTAssertTrue(comic.waitForExistence(timeout: 3))
        comic.tap()

        let chapter = app.descendants(matching: .any)["open-reader-ui-test-chapter"].firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 3))
        chapter.tap()

        XCTAssertTrue(app.descendants(matching: .any)["reader"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["第一话"].exists)
        XCTAssertTrue(app.staticTexts["本章暂无图片"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func makeApp(authenticated: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        if authenticated {
            app.launchArguments.append("--uitest-authenticated")
        }
        return app
    }

    @MainActor
    private func authenticatedElement(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["session-authenticated"].firstMatch
    }
}
