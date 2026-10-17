import XCTest

final class PersonalPlayerFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-reset-library", "-AppleLanguages", "(es)", "-AppleLocale", "es_CO"]
    }

    func testTypingShowsPlayableResultsWithoutSubmitting() {
        app.launch()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        var entered = ""
        for character in "tu con el" {
            field.typeText(String(character))
            entered.append(character)
            expectValue(entered, in: field)
        }
        XCTAssertTrue(app.buttons["result-aaaaaaaaaaa"].waitForExistence(timeout: 8))
        XCTAssertEqual(field.value as? String, "tu con el")
        app.buttons["result-aaaaaaaaaaa"].tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
    }

    func testSearchToFavoriteAndPlaylist() {
        app.launch()
        search("cancion")
        playFirstResult()
        saveCurrentFavorite()
        closePlayer()
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
        let playlistChoice = app.buttons["Mi lista"]
        let choiceReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            playlistChoice.exists && playlistChoice.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [choiceReady], timeout: 5), .completed)
        playlistChoice.tap()
        let picker = app.navigationBars["Añadir a una lista"]
        let libraryTab = app.tabBars.buttons["Biblioteca"]
        let pickerClosed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !picker.exists && libraryTab.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pickerClosed], timeout: 5), .completed)
        app.tabBars.buttons["Biblioteca"].tap()
        app.buttons["Mi lista"].tap()
        XCTAssertTrue(app.buttons["playlist-video-0"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Buscar"].tap()
        XCTAssertTrue(app.otherElements["miniPlayer"].exists)
        capture("Biblioteca y reproductor compartido")
    }

    func testHistoryIsAccessibleAfterRelaunch() {
        app.launch()
        search("cancion")
        playFirstResult()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        closePlayer()
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-reset-library" }
        app.launch()
        app.tabBars.buttons["Biblioteca"].tap()
        let history = app.buttons["Historial"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        guard history.exists else { return }
        history.tap()
        let played = app.buttons["recent-aaaaaaaaaaa"]
        XCTAssertTrue(played.waitForExistence(timeout: 5))
        played.tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
    }

    func testShuffleMusicActionStartsStoredContent() {
        app.launch()
        search("cancion")
        playFirstResult()
        saveCurrentFavorite()
        closePlayer()
        app.tabBars.buttons["Biblioteca"].tap()
        let shuffle = app.buttons["Mezclar mi música"]
        XCTAssertTrue(shuffle.waitForExistence(timeout: 5))
        guard shuffle.exists else { return }
        shuffle.tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Mezclar cola"].exists)
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
        closePlayer()
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
        closePlayer()
        app.tabBars.buttons["Biblioteca"].tap()
        XCTAssertTrue(app.buttons["Favoritos"].isHittable)
        XCTAssertTrue(app.otherElements["miniPlayer"].exists)
        capture("Texto grande y modo oscuro")
    }

    func testCustomGenreStartsRadio() {
        app.launch()
        let other = app.buttons["Otro género"]
        for _ in 0..<4 where !other.isHittable { app.swipeUp() }
        XCTAssertTrue(other.exists)
        guard other.exists else { return }
        other.tap()
        let alert = app.alerts["Otro género"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("Jazz")
        alert.buttons["Iniciar"].tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Radio Jazz"].exists)
        closePlayer()
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-reset-library" }
        app.launch()
        let savedGenre = app.buttons["genre-Jazz"]
        for _ in 0..<4 where !savedGenre.isHittable { app.swipeUp() }
        XCTAssertTrue(savedGenre.exists, "A custom genre must remain a reusable genre after relaunch")
        savedGenre.tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Radio Jazz"].exists)
    }

    func testBluesGenreStartsItsOwnRadio() {
        app.launch()
        let blues = app.buttons["genre-Blues"]
        for _ in 0..<3 where !blues.isHittable { app.swipeUp() }
        XCTAssertTrue(blues.exists)
        XCTAssertFalse(app.buttons["genre-Merengue"].exists)
        blues.tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Radio Blues"].exists)
        capture("Radio Blues")
    }

    func testPausedMiniPlayerCanCloseInEitherDirectionAndStayClosedAfterRelaunch() {
        app.launch()
        search("cancion")
        playFirstResult()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        saveCurrentFavorite()
        app.buttons["Pausar"].firstMatch.tap()
        closePlayer()
        let mini = app.otherElements["miniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        mini.swipeLeft()
        expectNoMiniPlayer()
        app.tabBars.buttons["Biblioteca"].tap()
        app.buttons["Favoritos"].tap()
        app.buttons["favorite-aaaaaaaaaaa"].tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["Pausar"].firstMatch.tap()
        closePlayer()
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        mini.swipeRight()
        expectNoMiniPlayer()
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-reset-library" }
        app.launch()
        expectNoMiniPlayer()
        app.tabBars.buttons["Biblioteca"].tap()
        app.buttons["Favoritos"].tap()
        XCTAssertTrue(app.buttons["favorite-aaaaaaaaaaa"].waitForExistence(timeout: 5))
        capture("Biblioteca sin cola activa y favorito conservado")
    }

    func testSwipingPlayingMiniPlayerKeepsAudioAndControls() {
        app.launch()
        search("cancion")
        playFirstResult()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        closePlayer()
        let mini = app.otherElements["miniPlayer"]
        mini.swipeLeft()
        XCTAssertTrue(mini.exists)
        XCTAssertTrue(app.buttons["Pausar"].firstMatch.exists)
        mini.swipeRight()
        XCTAssertTrue(mini.exists)
        XCTAssertTrue(app.buttons["Pausar"].firstMatch.exists)
    }

    func testGenresStartRadioAndContinuationCanBeDisabled() {
        app.launch()
        let salsa = app.buttons["genre-Salsa"]
        XCTAssertTrue(salsa.waitForExistence(timeout: 5))
        guard salsa.exists else { return }
        salsa.tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Radio Salsa"].exists)
        capture("Radio Salsa y controles")
        let toggle = app.switches["autoplayToggle"].firstMatch
        for _ in 0..<3 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        closePlayer()
        app.buttons["genre-Rock"].tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Radio Rock"].exists)
    }

    func testSongRadioCanBeStartedFromResultMenu() {
        app.launch()
        search("cancion")
        app.buttons["actions-aaaaaaaaaaa"].tap()
        let radio = app.sheets["Más opciones"].buttons["Iniciar radio"].firstMatch
        XCTAssertTrue(radio.waitForExistence(timeout: 5))
        guard radio.exists else { return }
        radio.tap()
        let open = app.buttons["openPlayer"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Radio desde una canción"].exists)
    }

    func testRecommendationsAppearInsideSearchAfterListening() {
        app.launch()
        search("cancion")
        playFirstResult()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        closePlayer()
        let field = app.textFields["searchField"]
        field.tap()
        var text = field.value as? String ?? ""
        while !text.isEmpty {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            text.removeLast()
            expectValue(text, in: field)
        }
        field.typeText("\n")
        let keyboardClosed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !self.app.keyboards.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardClosed], timeout: 5), .completed)
        let recommended = app.staticTexts["Para ti"]
        for _ in 0..<6 where !recommended.isHittable { app.swipeUp() }
        XCTAssertTrue(recommended.exists)
        let discovered = app.buttons["discover-bbbbbbbbbbb"]
        for _ in 0..<6 where !discovered.isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Por descubrir"].exists)
        XCTAssertTrue(discovered.exists)
        XCTAssertFalse(app.buttons["discover-aaaaaaaaaaa"].exists)
        capture("Buscar con recomendaciones y descubrimiento")
    }

    func testManualSongRemainsBeforeSuggestionsInQueue() {
        app.launch()
        let salsa = app.buttons["genre-Salsa"]
        XCTAssertTrue(salsa.waitForExistence(timeout: 5))
        guard salsa.exists else { return }
        salsa.tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        closePlayer()
        search("cancion")
        app.buttons["actions-bbbbbbbbbbb"].tap()
        app.sheets["Más opciones"].buttons["Añadir a la cola"].firstMatch.tap()
        app.buttons["openPlayer"].firstMatch.tap()
        let queue = app.buttons["openQueue"]
        for _ in 0..<3 where !queue.isHittable { app.swipeUp() }
        queue.tap()
        let manual = app.buttons["queue-bbbbbbbbbbb"].firstMatch
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        XCTAssertEqual(manual.value as? String, "A continuación · Añadida por ti")
        capture("Cola con prioridad manual")
    }

    func testLargeTextAndDarkModeKeepRadioAndQueueOperable() {
        app.launchArguments += ["--ui-large-text", "--ui-dark"]
        app.launch()
        capture("Buscar géneros con texto grande y modo oscuro")
        let salsa = app.buttons["genre-Salsa"]
        XCTAssertTrue(salsa.waitForExistence(timeout: 5))
        guard salsa.exists else { return }
        salsa.tap()
        XCTAssertTrue(app.staticTexts["Reproduciendo"].firstMatch.waitForExistence(timeout: 30))
        let toggle = app.switches["autoplayToggle"].firstMatch
        for _ in 0..<8 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        let playerHeadingHeight = app.staticTexts["Radio Salsa"].firstMatch.frame.height
        capture("Radio con texto grande y modo oscuro")
        let queue = app.buttons["openQueue"]
        for _ in 0..<5 where !queue.isHittable { app.swipeUp() }
        XCTAssertTrue(queue.isHittable)
        queue.tap()
        XCTAssertTrue(app.navigationBars["Cola"].waitForExistence(timeout: 5))
        let queueHeadingHeight = app.staticTexts["Radio Salsa"].firstMatch.frame.height
        capture("Cola con texto grande y modo oscuro")
        XCTAssertGreaterThan(min(playerHeadingHeight, queueHeadingHeight), 30,
                             "Accessibility headings must both scale: player=\(playerHeadingHeight), queue=\(queueHeadingHeight)")
    }


    private func closePlayer() {
        let close = app.buttons["closePlayer"]
        close.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !close.exists && self.app.tabBars.buttons["Biblioteca"].isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    }

    private func expectNoMiniPlayer() {
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !self.app.otherElements["miniPlayer"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    }

    private func search(_ query: String) {
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let previous = field.value as? String ?? ""
        let count = previous == "Videos, canciones o artistas" ? 0 : previous.count
        var entered = previous == "Videos, canciones o artistas" ? "" : previous
        for _ in 0..<count {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            entered.removeLast()
            expectValue(entered, in: field)
        }
        for character in query {
            field.typeText(String(character))
            entered.append(character)
            expectValue(entered, in: field)
        }
        let submit = app.buttons["searchSubmit"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.value as? String == query && submit.isEnabled && submit.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        submit.tap()
    }

    private func expectValue(_ value: String, in field: XCUIElement) {
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let actual = field.value as? String ?? ""
            return actual == value || (value.isEmpty && actual == field.placeholderValue)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [entered], timeout: 5), .completed)
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
