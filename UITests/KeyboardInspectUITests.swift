import XCTest
import UIKit

/// Character inspection in the keyboard: properties, Save and menus.
@MainActor
final class KeyboardInspectUITests: UniboardUITestCase {
    func testSystemKeyboardInspectorSaveAcceptsCornerTapsAndPreservesQueryAndHost() throws {
        try requireKeyboardIntegration()
        let context = "Words, symbols, and everything between."
        let input = openSystemKeyboardHost(initialText: context, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        enterKeyboardQuery("u+0021")
        let search = app.descendants(matching: .any)["keyboard.search"].firstMatch
        let key = app.buttons["keyboard.character.U+0021"].firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 10))
        key.press(forDuration: 0.8)
        assertKeyboardProperties(codepoints: "U+0021", nameContaining: "exclamation mark")
        let save = app.buttons["keyboard.properties.favorite"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(save.frame.width, 76)
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        XCTAssertTrue(app.frame.contains(save.frame))
        var saved = save.value as? String == "saved"
        for offset in [CGVector(dx: 4, dy: 4), CGVector(dx: 72, dy: 40), CGVector(dx: 38, dy: 22)] {
            save.coordinate(withNormalizedOffset: .zero).withOffset(offset).tap()
            saved.toggle()
            XCTAssertTrue(save.waitUntilValueEquals(saved ? "saved" : "not saved"),
                          "The entire Save keycap must toggle Favorites, including its corners")
            XCTAssertEqual(input.value as? String, context)
            XCTAssertTrue(search.waitUntilValueEquals("u+0021"))
        }
        if saved { save.tap(); XCTAssertTrue(save.waitUntilValueEquals("not saved")) }
        attachScreenshot("Save has a bounded 76 by 44 point native touch target")
        app.buttons["keyboard.properties.close"].tap()
        app.buttons["keyboard.query.delete"].tap()
        XCTAssertTrue(search.waitUntilValueEquals("u+002"))
        XCTAssertEqual(input.value as? String, context)
    }

    func testSystemKeyboardCompactMenusAndInspectionPreserveContext() throws {
        try requireKeyboardIntegration()
        let context = "Host context stays visible."
        let input = openSystemKeyboardHost(initialText: context, afterSetUpLaunch: true)
        defer { restoreEnglishKeyboard() }
        selectSymbolBoard("migrated-favorites", input: input, context: context)

        // ★ has no text/emoji presentation forms, so search lists one character key.
        enterKeyboardQuery("u+2605")
        let star = app.buttons["keyboard.character.U+2605"].firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 10))
        star.press(forDuration: 1)
        assertKeyboardProperties(codepoints: "U+2605", nameContaining: "black star")
        XCTAssertEqual(input.value as? String, context, "Holding inspects the scalar without inserting it")
        assertCompactKeyboardGeometry("portrait.properties", input: input, searching: false, inspecting: true)
        attachScreenshot("Compact glass Unicode properties keep host context visible without insertion")
        saveInspectedTextToFavorites(input: input, context: context)
        app.buttons["keyboard.properties.close"].tap()
        selectKeyboardSection("blocks")
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent(), "Blocks must exit query mode")
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("u+2605"))
        let basicLatin = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Basic Latin")).firstMatch
        XCTAssertTrue(basicLatin.waitForExistence(timeout: 5), "The actual block list must replace search results")
        XCTAssertTrue(basicLatin.isHittable)
        XCTAssertEqual(input.value as? String, context)
        attachScreenshot("Compact section menu opens Blocks while retaining the local query")
        selectKeyboardSection("symbols")
        reopenKeyboardSearch(expectedQuery: "u+2605")
        selectKeyboardSection("saved")
        XCTAssertTrue(app.buttons["keyboard.query.u"].firstMatch.waitUntilAbsent(), "Saved must exit query mode")
        XCTAssertTrue(app.descendants(matching: .any)["keyboard.search"].firstMatch.waitUntilValueEquals("u+2605"))
        let savedStar = symbolBoardKey("★")
        XCTAssertTrue(savedStar.waitForExistence(timeout: 5), "The saved scalar must appear in actual Saved content")
        savedStar.tap()
        XCTAssertTrue(input.waitUntilValueEquals(context + "★"))
        attachScreenshot("Compact Saved section inserts the original saved scalar")
        inspectSymbolBoardKey(symbolBoardKey("★"), optionCount: 1, input: input, context: context + "★")
        XCTAssertTrue(app.staticTexts["keyboard.properties.name"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibleText(app.staticTexts["keyboard.properties.codepoints"].firstMatch), "U+2605")
        XCTAssertEqual(input.value as? String, context + "★")
        let save = app.buttons["keyboard.properties.favorite"].firstMatch
        XCTAssertTrue(save.waitUntilValueEquals("saved"), "The star saved above is a favorite")
        save.tap()
        XCTAssertTrue(save.waitUntilValueEquals("not saved"), "Save toggles the favorite off again")
        XCTAssertEqual(input.value as? String, context + "★")
        app.buttons["keyboard.properties.close"].tap()
        assertKeyboardHasNoEditionSelector()
        assertKeyboardHasNoSettingsMenu()
        XCTAssertEqual(input.value as? String, context + "★", "Menus must not enter text into the host")
        selectKeyboardSection("symbols")
        assertCompactKeyboardGeometry("portrait.menus.closed", input: input, searching: false)
    }

    func testSystemKeyboardUnsupportedGlyphInspectionDoesNotInsert() throws {
        try requireKeyboardIntegration()
        selectAppEdition("latest")
        let input = openSystemKeyboardHost()
        defer { restoreEnglishKeyboard() }
        enterKeyboardQuery("u+1faeb")
        let crackingFace = app.buttons["keyboard.character.U+1FAEB"].firstMatch
        XCTAssertTrue(crackingFace.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "")
        crackingFace.press(forDuration: 1)
        assertKeyboardProperties(codepoints: "U+1FAEB", nameContaining: "cracking face")
        let age = app.descendants(matching: .any)["keyboard.properties.age"].firstMatch
        XCTAssertEqual(accessibleText(age), "Unicode 18.0")
        XCTAssertEqual(input.value as? String, "", "Inspecting an unsupported glyph must never insert a placeholder or scalar")
        attachScreenshot("Real keyboard inspects unsupported cracking-face glyph without insertion")
        app.buttons["keyboard.properties.close"].tap()
        XCTAssertEqual(input.value as? String, "")
        closeKeyboardSearch()
    }
}
