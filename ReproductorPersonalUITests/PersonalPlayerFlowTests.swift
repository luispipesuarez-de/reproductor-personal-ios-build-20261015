import XCTest

final class PersonalPlayerFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-reset-library", "-AppleLanguages", "(es)", "-AppleLocale", "es_CO"]
    }

    func testSearchToFavoriteAndPlaylist() {
        app.launch()
        search("cancion")
        playFirstResult()
        saveCurrentFavorite()
        app.buttons["closePlayer"].tap()
        XCTAssertTrue(app.otherElements["miniPlayer"].exists)
        app.tabBars.buttons["Biblioteca"].tap()
        app.buttons["Favoritos"].tap()
        XCTAssertTrue(app.buttons["favorite-aaaaaaaaaaa"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["createPlaylist"].tap()
        let name = app.alerts["Nueva lista"].textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertEqual(name.placeholderValue, "Nombre de la lista")
        name.typeText("Mi lista")
        app.alerts.buttons["Crear"].tap()
        XCTAssertTrue(app.staticTexts["Mi lista"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Buscar"].tap()
        app.buttons["actions-aaaaaaaaaaa"].tap()
        let addToPlaylist = app.sheets["Más opciones"].buttons["Añadir a una lista"].firstMatch
        XCTAssertTrue(addToPlaylist.waitForExistence(timeout: 5))
        addToPlaylist.tap()
        XCTAssertTrue(app.navigationBars["Añadir a una lista"].waitForExistence(timeout: 5))
        app.buttons["Mi lista"].tap()
        app.tabBars.buttons["Biblioteca"].tap()
        app.buttons["Mi lista"].tap()
        XCTAssertTrue(app.buttons["playlist-video-0"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Buscar"].tap()
        XCTAssertTrue(app.otherElements["miniPlayer"].exists)
        capture("Biblioteca y reproductor compartido")
    }

    func testSearchEmptyAndFailureStatesRemainOperable() {
        app.launch()
        search("vacio")
        XCTAssertTrue(app.staticTexts["No encontramos resultados"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["searchField"].isEnabled)
        search("error")
        XCTAssertTrue(app.buttons["Reintentar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["searchField"].isEnabled)
        app.buttons["Reintentar"].tap()
        XCTAssertTrue(app.buttons["Reintentar"].waitForExistence(timeout: 5))
        search("cancion")
        XCTAssertTrue(app.buttons["result-aaaaaaaaaaa"].waitForExistence(timeout: 5))
    }

    func testReopeningRestoresLibraryAndQueuePaused() {
        app.launch()
        search("cancion")
        playFirstResult()
        saveCurrentFavorite()
        app.buttons["closePlayer"].tap()
        XCTAssertTrue(app.otherElements["miniPlayer"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-reset-library" }
        app.launch()
        XCTAssertTrue(app.otherElements["miniPlayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pausado"].exists)
        app.tabBars.buttons["Biblioteca"].tap()
        app.buttons["Favoritos"].tap()
        XCTAssertTrue(app.buttons["favorite-aaaaaaaaaaa"].waitForExistence(timeout: 5))
        app.buttons["favorite-aaaaaaaaaaa"].tap()
        XCTAssertTrue(app.buttons["closePlayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
    }

    func testLargeTextAndDarkModeKeepNavigationOperable() {
        app.launchArguments += ["--ui-large-text", "--ui-dark"]
        app.launch()
        search("cancion")
        playFirstResult()
        XCTAssertTrue(app.buttons["closePlayer"].isHittable)
        app.buttons["closePlayer"].tap()
        app.tabBars.buttons["Biblioteca"].tap()
        XCTAssertTrue(app.buttons["Favoritos"].isHittable)
        XCTAssertTrue(app.otherElements["miniPlayer"].exists)
        capture("Texto grande y modo oscuro")
    }

    private func search(_ query: String) {
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let previous = field.value as? String ?? ""
        let count = previous == "Videos, canciones o artistas" ? 0 : previous.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + query)
        let submit = app.buttons["searchSubmit"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.value as? String == query && submit.isEnabled && submit.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        submit.tap()
    }

    private func playFirstResult() {
        let result = app.buttons["result-aaaaaaaaaaa"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.buttons["closePlayer"].waitForExistence(timeout: 5))
    }

    private func saveCurrentFavorite() {
        app.buttons["currentActions"].tap()
        let options = app.sheets["Más opciones"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        let favorite = options.buttons["Guardar en Favoritos"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        favorite.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
