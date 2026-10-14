import XCTest

final class SettingsWindowUITests: ShichiZipUITestCase {
    func testSwiftUISettingsNavigationAndRPMFileTypeSearch() {
        openSettings()

        let window = app.windows.firstMatch
        let title = window.staticTexts["Options"]
        let languagePicker = window.popUpButtons.matching(identifier: "settings.language").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(languagePicker.isHittable)
        XCTAssertGreaterThanOrEqual(languagePicker.frame.minY, title.frame.maxY)

        let widthBeforeResize = window.frame.width
        let rightEdge = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -1, dy: 0))
        let inwardDragTarget = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: widthBeforeResize * 0.6, dy: 0))
        rightEdge.click(forDuration: 0.2, thenDragTo: inwardDragTarget)

        let initialWindowFrame = window.frame
        XCTAssertLessThan(initialWindowFrame.width, widthBeforeResize - 1,
                          "Dragging the right edge must actually shrink the window.")
        XCTAssertGreaterThanOrEqual(initialWindowFrame.width, 660)

        settingsNavigation("archives").click()
        app.typeKey(.downArrow, modifierFlags: [])
        let preset = window.descendants(matching: .any).matching(
            identifier: "settings.shortcutPreset",
        ).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        XCTAssertTrue(preset.isHittable)
        XCTAssertTrue(window.frame.contains(preset.frame))

        let fileTypesNavigation = settingsNavigation("fileTypes")
        XCTAssertTrue(fileTypesNavigation.waitForExistence(timeout: 10))
        XCTAssertTrue(fileTypesNavigation.isHittable)
        fileTypesNavigation.click()

        let searchField = app.searchFields.matching(
            identifier: "settings.fileTypeSearch",
        ).firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertTrue(searchField.isHittable)
        XCTAssertEqual(window.frame.width, initialWindowFrame.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, initialWindowFrame.height, accuracy: 1)
        XCTAssertTrue(fileTypesNavigation.isHittable)
        searchField.click()
        searchField.typeText("rpm")

        XCTAssertTrue(app.staticTexts["Linux RPM Archive"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[".rpm"].waitForExistence(timeout: 10))

        settingsNavigation("extensions").click()
        XCTAssertTrue(
            app.textFields.matching(
                identifier: "settings.quickLook.expansionDepth",
            ).firstMatch.waitForExistence(timeout: 5),
        )

        app.typeKey("w", modifierFlags: .command)
    }
}

private extension SettingsWindowUITests {
    func openSettings() {
        XCTAssertTrue(fileManagerWindow.waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["Tools"].click()
        app.menuBars.menuBarItems["Tools"].menus.menuItems.firstMatch.click()
        XCTAssertTrue(settingsNavigation("general").waitForExistence(timeout: 10))
    }

    func settingsNavigation(_ destination: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            identifier: "settings.navigation.\(destination)",
        ).firstMatch
    }
}
