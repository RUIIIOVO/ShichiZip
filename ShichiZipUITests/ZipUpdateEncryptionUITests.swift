import XCTest

/// Updates existing ZIPs through the real Copy To / Move To workflow.
final class ZipUpdateEncryptionUITests: ShichiZipUITestCase {
    override var additionalLaunchArguments: [String] {
        ["-FileManager.IsDualPane", "NO",
         "-LanguageOverride", "en",
         "-RevealAfterTransfer", "NO",
         "-SZShowPasswordInPrompts", "NO"]
    }

    func testAESUpdateValidatesPasswordAndEncryptsAddedAndReplacedFiles() throws {
        let fixture = try makeFixture()
        let originalData = try Data(contentsOf: fixture.archive)
        beginUpdate(fixture)

        confirmUpdate()
        assertValidationKeepsArchiveUnchanged(fixture.archive, originalData: originalData, message: "Enter password")

        selectEncryption("AES-256")
        let password = "new-aes-password"
        enterUpdatePassword(password)
        let showPassword = app.checkBoxes.matching(identifier: "archiveUpdateEncryption.showPassword").firstMatch
        XCTAssertTrue(showPassword.exists)
        showPassword.click()
        let plainField = app.textFields.matching(identifier: "archiveUpdateEncryption.passwordPlain").firstMatch
        XCTAssertTrue(plainField.waitForExistence(timeout: 5))
        XCTAssertEqual(plainField.value as? String, password)
        showPassword.click()
        XCTAssertTrue(app.secureTextFields.matching(identifier: "archiveUpdateEncryption.password").firstMatch.isHittable)

        confirmUpdate()
        waitForOperationToFinish()

        let entries = try assertUntouchedEntryPreserved(fixture, originalData: originalData)
        for name in fixture.updatedPayloads.keys {
            let entry = try XCTUnwrap(entries[name])
            XCTAssertTrue(entry.isEncrypted)
            XCTAssertEqual(entry.method, 99, "\(name) should use ZIP AES")
            XCTAssertEqual(entry.aesStrength, 3, "\(name) should use AES-256")
        }
        // System unzip cannot read AES, so use the app to verify the selected
        // password and both updated files' contents.
        try extractUpdatedEntriesThroughUI(fixture, password: password)
    }

    func testZipCryptoUpdateUsesTheNewPasswordAndPreservesUntouchedEntries() throws {
        let fixture = try makeFixture()
        let originalData = try Data(contentsOf: fixture.archive)
        beginUpdate(fixture)

        selectEncryption("ZipCrypto")
        let password = "new-zipcrypto-password"
        enterUpdatePassword(password)
        confirmUpdate()
        waitForOperationToFinish()

        let entries = try assertUntouchedEntryPreserved(fixture, originalData: originalData)
        for (name, contents) in fixture.updatedPayloads {
            let entry = try XCTUnwrap(entries[name])
            XCTAssertTrue(entry.isEncrypted)
            XCTAssertNotEqual(entry.method, 99, "\(name) must not silently become AES")
            XCTAssertNil(entry.aesStrength)
            XCTAssertEqual(try unzipEntry(name, from: fixture.archive, password: password), contents)
            XCTAssertEqual(try String(contentsOf: fixture.source.appendingPathComponent(name), encoding: .utf8), contents,
                           "Copy To must retain the source files")
        }
    }

    func testChoosingNoneDisablesPasswordAndWritesOnlyUpdatedFilesUnencrypted() throws {
        let fixture = try makeFixture()
        let originalData = try Data(contentsOf: fixture.archive)
        beginUpdate(fixture)

        enterUpdatePassword("must-not-be-used")
        selectEncryption("None")
        let passwordField = app.secureTextFields.matching(identifier: "archiveUpdateEncryption.password").firstMatch
        XCTAssertTrue(passwordField.exists)
        XCTAssertFalse(passwordField.isEnabled)
        XCTAssertFalse(app.checkBoxes.matching(identifier: "archiveUpdateEncryption.showPassword").firstMatch.isEnabled)
        confirmUpdate()
        waitForOperationToFinish()

        let entries = try assertUntouchedEntryPreserved(fixture, originalData: originalData)
        for (name, contents) in fixture.updatedPayloads {
            let entry = try XCTUnwrap(entries[name])
            XCTAssertFalse(entry.isEncrypted)
            XCTAssertNotEqual(entry.method, 99)
            XCTAssertNil(entry.aesStrength)
            XCTAssertEqual(try unzipEntry(name, from: fixture.archive), contents)
        }
    }

    func testPlainZipDefaultsToNoneAndCanEncryptAddedAndReplacedFiles() throws {
        let fixture = try makeFixture(password: nil)
        let originalData = try Data(contentsOf: fixture.archive)
        beginUpdate(fixture, expectedEncryption: "None")

        let passwordField = app.secureTextFields.matching(identifier: "archiveUpdateEncryption.password").firstMatch
        let showPassword = app.checkBoxes.matching(identifier: "archiveUpdateEncryption.showPassword").firstMatch
        XCTAssertTrue(passwordField.exists)
        XCTAssertFalse(passwordField.isEnabled)
        XCTAssertFalse(showPassword.isEnabled)

        selectEncryption("AES-256")
        XCTAssertTrue(passwordField.isEnabled)
        XCTAssertTrue(showPassword.isEnabled)
        let password = "encrypt-plain-zip-password"
        enterUpdatePassword(password)
        confirmUpdate()
        waitForOperationToFinish()

        let entries = try assertUntouchedEntryPreserved(fixture, originalData: originalData)
        XCTAssertFalse(try XCTUnwrap(entries["keep.txt"]).isEncrypted,
                       "The untouched plaintext entry must remain unencrypted")
        for name in fixture.updatedPayloads.keys {
            let entry = try XCTUnwrap(entries[name])
            XCTAssertTrue(entry.isEncrypted)
            XCTAssertEqual(entry.method, 99, "\(name) should use ZIP AES")
            XCTAssertEqual(entry.aesStrength, 3, "\(name) should use AES-256")
        }
        try extractUpdatedEntriesThroughUI(fixture, password: password)
    }

    func testCancellingMoveLeavesTheArchiveAndSourcesUnchanged() throws {
        let fixture = try makeFixture()
        let originalData = try Data(contentsOf: fixture.archive)
        beginUpdate(fixture, move: true)

        selectEncryption("AES-256")
        enterUpdatePassword("cancelled-password")
        app.buttons.matching(identifier: "modal.button.0").firstMatch.click()
        waitForOperationToFinish()

        XCTAssertEqual(try Data(contentsOf: fixture.archive), originalData,
                       "Cancelling the encryption choice must not change the archive")
        for (name, contents) in fixture.updatedPayloads {
            let sourceURL = fixture.source.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path),
                          "Cancelling Move To must preserve \(name)")
            XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), contents)
        }
        XCTAssertFalse(app.buttons.matching(identifier: "modal.button.0").firstMatch.exists,
                       "Cancelling must return to the file manager without an error dialog")
    }

    // MARK: - File manager operations

    private var encryptionPopup: XCUIElement {
        app.popUpButtons.matching(identifier: "archiveUpdateEncryption.encryption").firstMatch
    }

    private var continueButton: XCUIElement {
        app.buttons.matching(identifier: "modal.button.1").firstMatch
    }

    private func confirmUpdate() {
        let dialog = app.dialogs.containing(.popUpButton, identifier: "archiveUpdateEncryption.encryption").firstMatch
        let button = dialog.buttons.matching(identifier: "modal.button.1").firstMatch
        XCTAssertTrue(button.isHittable)
        button.click()
    }

    private func beginUpdate(_ fixture: Fixture, move: Bool = false, expectedEncryption: String = "ZipCrypto") {
        navigateLeftPane(to: fixture.source.path)
        selectFiles(fixture.updatedPayloads.keys.sorted())
        runDestinationDialog(menuItem: move ? "Move To..." : "Copy To...", destination: fixture.archive)
        XCTAssertTrue(encryptionPopup.waitForExistence(timeout: 10),
                      "Updating a ZIP should request this operation's encryption")
        XCTAssertEqual(encryptionPopup.value as? String, expectedEncryption,
                       "The default encryption should reflect the ZIP's existing entries")
    }

    private func selectFiles(_ names: [String]) {
        for (index, name) in names.enumerated() {
            let cell = leftPaneTable.cells.staticTexts[name]
            XCTAssertTrue(cell.waitForExistence(timeout: 5))
            if index == 0 {
                cell.click()
            } else {
                XCUIElement.perform(withKeyModifiers: .command) {
                    cell.click()
                }
            }
        }
    }

    private func runDestinationDialog(menuItem: String, destination: URL) {
        app.menuBars.menuBarItems["File"].click()
        let item = app.menuBars.menuBarItems["File"].menus.menuItems[menuItem]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()

        let destinationField = app.comboBoxes.matching(identifier: "fileOperation.destinationPath").firstMatch
        XCTAssertTrue(destinationField.waitForExistence(timeout: 5))
        destinationField.click()
        destinationField.selectAll()
        destinationField.pasteText(destination.path)
        continueButton.click()
    }

    private func selectEncryption(_ title: String) {
        encryptionPopup.click()
        let item = encryptionPopup.menuItems[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        let selectionFinished = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            encryptionPopup.value as? String == title && !item.exists
        }, object: nil)
        wait(for: [selectionFinished], timeout: 5)
    }

    private func enterUpdatePassword(_ password: String) {
        let field = passwordField(prefix: "archiveUpdateEncryption")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.selectAll()
        field.pasteText(password)
    }

    private func passwordField(prefix: String) -> XCUIElement {
        let secure = app.secureTextFields.matching(identifier: "\(prefix).password").firstMatch
        if secure.exists, secure.isHittable {
            return secure
        }
        return app.textFields.matching(identifier: "\(prefix).passwordPlain").firstMatch
    }

    private func assertValidationKeepsArchiveUnchanged(_ archive: URL, originalData: Data, message: String,
                                                       file: StaticString = #filePath, line: UInt = #line)
    {
        let errorTitle = app.staticTexts[message].firstMatch
        XCTAssertTrue(errorTitle.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(encryptionPopup.exists, file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: archive), originalData, file: file, line: line)
        let errorSheet = app.sheets.containing(.staticText, identifier: message).firstMatch
        XCTAssertTrue(errorSheet.exists, file: file, line: line)
        errorSheet.buttons.matching(identifier: "modal.button.0").firstMatch.click()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: errorTitle)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, file: file, line: line)
    }

    private func waitForOperationToFinish() {
        let promptGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                   object: encryptionPopup)
        let progressGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                     object: app.buttons.matching(identifier: "operationProgress.cancel").firstMatch)
        wait(for: [promptGone, progressGone], timeout: 15)
        XCTAssertTrue(leftPaneTable.isHittable)
    }

    private func extractUpdatedEntriesThroughUI(_ fixture: Fixture, password: String) throws {
        navigateLeftPane(to: fixture.archive.deletingLastPathComponent().path)
        let archiveCell = leftPaneTable.cells.staticTexts[fixture.archive.lastPathComponent]
        XCTAssertTrue(archiveCell.waitForExistence(timeout: 5))
        archiveCell.doubleClick()
        let archiveOpened = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", fixture.archive.lastPathComponent),
            object: leftPanePathField,
        )
        wait(for: [archiveOpened], timeout: 10)
        selectFiles(fixture.updatedPayloads.keys.sorted())

        let output = fixture.root.appendingPathComponent("extracted", isDirectory: true)
        runDestinationDialog(menuItem: "Copy To...", destination: output)
        let secure = app.secureTextFields.matching(identifier: "passwordPrompt.password").firstMatch
        let plain = app.textFields.matching(identifier: "passwordPrompt.passwordPlain").firstMatch
        let promptAppeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            secure.exists || plain.exists
        }, object: nil)
        wait(for: [promptAppeared], timeout: 10)
        let field = passwordField(prefix: "passwordPrompt")
        field.click()
        field.selectAll()
        field.pasteText(password)
        continueButton.click()

        for (name, contents) in fixture.updatedPayloads {
            let extracted = output.appendingPathComponent(name)
            XCTAssertTrue(waitForFile(at: extracted))
            XCTAssertEqual(try String(contentsOf: extracted, encoding: .utf8), contents)
        }
        waitForOperationToFinish()
    }

    // MARK: - Fixtures and independent archive verification

    private struct Fixture {
        let root: URL
        let archive: URL
        let source: URL
        let oldPassword: String?
        let keptPayload: String
        let updatedPayloads: [String: String]
    }

    private func makeFixture(password: String? = "original-password") throws -> Fixture {
        let root = try makeTemporaryDirectory(named: "zip-update-encryption")
        let originals = root.appendingPathComponent("originals", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let keptPayload = "This entry must remain unchanged."
        try createTextFile(at: originals.appendingPathComponent("keep.txt"), content: keptPayload)
        try createTextFile(at: originals.appendingPathComponent("replace.txt"), content: "Original contents.")
        let archive = try createTestArchive(named: "update", sourceFileNames: ["keep.txt", "replace.txt"],
                                            in: originals, password: password)
        let updatedPayloads = ["added.txt": "Added through the encryption dialog.",
                               "replace.txt": "Replaced through the same encryption choice."]
        for (name, contents) in updatedPayloads {
            try createTextFile(at: source.appendingPathComponent(name), content: contents)
        }
        return Fixture(root: root, archive: archive, source: source, oldPassword: password,
                       keptPayload: keptPayload, updatedPayloads: updatedPayloads)
    }

    private func assertUntouchedEntryPreserved(_ fixture: Fixture, originalData: Data) throws -> [String: ZipEntry] {
        let entries = try zipEntries(in: Data(contentsOf: fixture.archive))
        let originals = try zipEntries(in: originalData)
        XCTAssertEqual(Set(entries.keys), Set(["keep.txt", "replace.txt", "added.txt"]))
        XCTAssertEqual(entries["keep.txt"]?.packedData, originals["keep.txt"]?.packedData,
                       "The untouched entry must retain its original stored payload")
        XCTAssertEqual(try unzipEntry("keep.txt", from: fixture.archive, password: fixture.oldPassword),
                       fixture.keptPayload)
        return entries
    }

    private func unzipEntry(_ name: String, from archive: URL, password: String? = nil) throws -> String {
        // An explicit empty password prevents interactive prompts if a file
        // expected to be plaintext is accidentally encrypted.
        try runUITestCLITool("/usr/bin/unzip", arguments: ["-p", "-P", password ?? "", archive.path, name],
                             captureStandardOutput: true)
    }

    private struct ZipEntry {
        let isEncrypted: Bool
        let method: Int
        let aesStrength: Int?
        let packedData: Data
    }

    /// Reads ordinary ZIP records from these small fixtures without a 7z binary.
    private func zipEntries(in data: Data) throws -> [String: ZipEntry] {
        func integer(at offset: Int, width: Int) throws -> Int {
            guard offset >= 0, offset + width <= data.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return (0 ..< width).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
        }

        let end = try XCTUnwrap(data.range(of: Data([0x50, 0x4B, 0x05, 0x06]), options: .backwards)?.lowerBound)
        let count = try integer(at: end + 10, width: 2)
        var centralOffset = try integer(at: end + 16, width: 4)
        var entries: [String: ZipEntry] = [:]
        for _ in 0 ..< count {
            guard try integer(at: centralOffset, width: 4) == 0x0201_4B50 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let flags = try integer(at: centralOffset + 8, width: 2)
            let method = try integer(at: centralOffset + 10, width: 2)
            let packedSize = try integer(at: centralOffset + 20, width: 4)
            let nameLength = try integer(at: centralOffset + 28, width: 2)
            let extraLength = try integer(at: centralOffset + 30, width: 2)
            let commentLength = try integer(at: centralOffset + 32, width: 2)
            let localOffset = try integer(at: centralOffset + 42, width: 4)
            let nameStart = centralOffset + 46
            let nameEnd = nameStart + nameLength
            let extraEnd = nameEnd + extraLength
            guard extraEnd + commentLength <= data.count,
                  try integer(at: localOffset, width: 4) == 0x0403_4B50
            else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let path = try XCTUnwrap(String(data: data[nameStart ..< nameEnd], encoding: .utf8))
            var aesStrength: Int?
            var extraOffset = nameEnd
            while extraOffset < extraEnd {
                guard extraOffset + 4 <= extraEnd else { throw CocoaError(.fileReadCorruptFile) }
                let identifier = try integer(at: extraOffset, width: 2)
                let size = try integer(at: extraOffset + 2, width: 2)
                guard extraOffset + 4 + size <= extraEnd else { throw CocoaError(.fileReadCorruptFile) }
                if identifier == 0x9901 {
                    guard size >= 7 else { throw CocoaError(.fileReadCorruptFile) }
                    aesStrength = try integer(at: extraOffset + 8, width: 1)
                }
                extraOffset += 4 + size
            }

            let localNameLength = try integer(at: localOffset + 26, width: 2)
            let localExtraLength = try integer(at: localOffset + 28, width: 2)
            let packedStart = localOffset + 30 + localNameLength + localExtraLength
            let packedEnd = packedStart + packedSize
            guard packedEnd <= data.count, entries[path] == nil else { throw CocoaError(.fileReadCorruptFile) }
            entries[path] = ZipEntry(isEncrypted: flags & 1 != 0, method: method, aesStrength: aesStrength,
                                     packedData: Data(data[packedStart ..< packedEnd]))
            centralOffset = extraEnd + commentLength
        }
        return entries
    }
}
