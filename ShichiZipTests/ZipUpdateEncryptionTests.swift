import XCTest

#if SHICHIZIP_ZS_VARIANT
    @testable import ShichiZip_ZS
#else
    @testable import ShichiZip
#endif

final class ZipUpdateEncryptionTests: XCTestCase {
    private struct Member {
        let path: String
        let contents: String
        let encryption: SZEncryptionMethod
        let password: String?
        var aesKeySize = 256
    }

    private struct Fixture {
        let archive: SZArchive
        let root: URL
        let archiveURL: URL
    }

    /// Creation can append independently encrypted records without reading the
    /// preceding members, giving each fixture distinct read passwords.
    private func makeArchive(_ members: [Member]) throws -> Fixture {
        let root = try makeTemporaryDirectory(named: "zip-update-encryption")
        let archiveURL = root.appendingPathComponent("archive.zip")
        for member in members {
            let source: URL
            if member.path.hasSuffix("/") {
                source = root.appendingPathComponent(member.path, isDirectory: true)
                try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            } else {
                source = try write(member.contents, named: member.path, under: root)
            }
            let settings = SZCompressionSettings()
            settings.format = .formatZip
            settings.pathMode = .relativePaths
            settings.method = .deflate
            settings.methodName = "Deflate"
            settings.encryption = member.encryption
            settings.password = member.password
            if member.encryption == .AES256, member.aesKeySize != 256 {
                settings.parameters = "em=AES\(member.aesKeySize)"
            }
            try SZArchive.create(atPath: archiveURL.path, fromPaths: [source.path],
                                 settings: settings, session: SZOperationSession())
        }
        let archive = SZArchive()
        try archive.open(atPath: archiveURL.path, session: SZOperationSession())
        return Fixture(archive: archive, root: root, archiveURL: archiveURL)
    }

    private func rewriteFixture(_ fixture: Fixture,
                                edit: (inout Data, [ZipFixtureRecord]) throws -> Void) throws
    {
        fixture.archive.close()
        var data = try Data(contentsOf: fixture.archiveURL)
        let records = try zipFixtureRecords(in: data)
        try edit(&data, records)
        try data.write(to: fixture.archiveURL, options: .atomic)
        try fixture.archive.open(atPath: fixture.archiveURL.path, session: SZOperationSession())
    }

    private func write(_ contents: String, named name: String, under root: URL) throws -> URL {
        let url = root.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func assertMember(_ member: Member, entry: SZArchiveEntry,
                              in archive: SZArchive, destination: URL,
                              file: StaticString = #filePath, line: UInt = #line) throws
    {
        XCTAssertEqual(entry.path, member.path, file: file, line: line)
        XCTAssertEqual(entry.isEncrypted, member.encryption != .none, file: file, line: line)
        switch member.encryption {
        case .AES256:
            XCTAssertTrue(entry.method?.contains("AES-\(member.aesKeySize)") == true, file: file, line: line)
        case .zipCrypto:
            XCTAssertTrue(entry.method?.contains("ZipCrypto") == true, file: file, line: line)
        default:
            XCTAssertFalse(entry.method?.contains("AES-") == true, file: file, line: line)
            XCTAssertFalse(entry.method?.contains("ZipCrypto") == true, file: file, line: line)
        }
        let settings = SZExtractionSettings()
        settings.password = member.password
        let session = SZOperationSession()
        session.passwordRequestHandler = { _, _, _, _ in
            XCTFail("The expected password must decrypt \(member.path) without prompting", file: file, line: line)
            return false
        }
        try archive.extractEntries([NSNumber(value: entry.index)], toPath: destination.path,
                                   settings: settings, session: session)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent(member.path), encoding: .utf8),
                       member.contents, file: file, line: line)
    }

    private func verify(_ members: [Member], in fixture: Fixture,
                        file: StaticString = #filePath, line: UInt = #line) throws
    {
        XCTAssertEqual(Set(fixture.archive.entries().map(\.path)), Set(members.map(\.path)), file: file, line: line)
        XCTAssertEqual(fixture.archive.entries().count, members.count, file: file, line: line)
        for (index, member) in members.enumerated() {
            // Reopen for every member so a cached read password cannot conceal
            // a write using another member's password.
            let reopened = SZArchive()
            try reopened.open(atPath: fixture.archiveURL.path, session: SZOperationSession())
            defer { reopened.close() }
            let entry = try XCTUnwrap(reopened.entries().first { $0.path == member.path }, file: file, line: line)
            try assertMember(member, entry: entry, in: reopened,
                             destination: fixture.root.appendingPathComponent("verify-\(index)"), file: file, line: line)
        }
    }

    func testDefaultUsesFirstEncryptedFileInCoreOrderSkippingDirectoriesAndPlainFiles() throws {
        for encryption in [SZEncryptionMethod.zipCrypto, .AES256] {
            let otherEncryption: SZEncryptionMethod = encryption == .zipCrypto ? .AES256 : .zipCrypto
            let fixture = try makeArchive([
                Member(path: "0-directory/", contents: "", encryption: .none, password: nil),
                Member(path: "1-plain.txt", contents: "public", encryption: .none, password: nil),
                Member(path: "a-first.txt", contents: "first secret", encryption: encryption, password: "first"),
                Member(path: "z-later.txt", contents: "later secret", encryption: otherEncryption, password: "later"),
            ])
            defer { fixture.archive.close() }
            try rewriteFixture(fixture) { data, records in
                let directory = try XCTUnwrap(records.first { $0.path == "0-directory/" })
                // An encrypted directory must not determine the file default.
                data[directory.localNameRange.lowerBound - 30 + 6] |= 1
                data[directory.centralNameRange.lowerBound - 46 + 8] |= 1
                // Keep the physical/core order while reversing the name order.
                // The writer normally sorts names when producing update pairs.
                for (oldName, newName) in [("a-first.txt", "z-later.txt"), ("z-later.txt", "a-first.txt")] {
                    let record = try XCTUnwrap(records.first { $0.path == oldName })
                    let name = Data(newName.utf8)
                    XCTAssertEqual(record.localNameRange.count, name.count)
                    XCTAssertEqual(record.centralNameRange.count, name.count)
                    data.replaceSubrange(record.localNameRange, with: name)
                    data.replaceSubrange(record.centralNameRange, with: name)
                }
            }
            let entries = fixture.archive.entries().sorted { $0.index < $1.index }
            XCTAssertEqual(entries.map(\.path), ["0-directory", "1-plain.txt", "z-later.txt", "a-first.txt"])
            let directory = try XCTUnwrap(entries.first)
            let plain = try XCTUnwrap(entries.first { $0.path == "1-plain.txt" })
            XCTAssertTrue(directory.isDirectory)
            XCTAssertTrue(directory.isEncrypted)
            XCTAssertFalse(plain.isEncrypted)
            let originalData = try Data(contentsOf: fixture.archiveURL)
            let source = try write("new contents", named: "added.txt", under: fixture.root)
            var choices = 0
            let session = SZOperationSession()
            session.updateEncryptionRequestHandler = { path, defaultEncryption in
                XCTAssertEqual(path, fixture.archiveURL.path)
                XCTAssertEqual(defaultEncryption, encryption)
                XCTAssertTrue(Thread.isMainThread)
                choices += 1
                return nil
            }

            XCTAssertThrowsError(try fixture.archive.addPaths([source.path], toArchiveSubdir: "", moveMode: false, session: session)) {
                XCTAssertTrue(szIsUserCancellation($0))
            }
            XCTAssertEqual(choices, 1)
            XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), originalData)
        }
    }

    func testAllSupportedAesKeySizesDefaultToAes256ForNewData() throws {
        for keySize in [128, 192, 256] {
            let original = Member(path: "first.txt", contents: "first secret", encryption: .AES256,
                                  password: "old-password", aesKeySize: keySize)
            let later = Member(path: "later.txt", contents: "later secret", encryption: .zipCrypto, password: "other")
            let fixture = try makeArchive([original, later])
            defer { fixture.archive.close() }
            let first = try XCTUnwrap(fixture.archive.entries().min { $0.index < $1.index })
            try assertMember(original, entry: first, in: fixture.archive,
                             destination: fixture.root.appendingPathComponent("read-original"))
            let added = Member(path: "added.txt", contents: "new secret", encryption: .AES256, password: "new-password")
            let source = try write(added.contents, named: added.path, under: fixture.root)
            var choices = 0
            let session = SZOperationSession()
            session.passwordRequestHandler = { _, _, _, _ in
                XCTFail("The existing AES-\(keySize) record must be copied without requesting its password")
                return false
            }
            session.updateEncryptionRequestHandler = { _, defaultEncryption in
                XCTAssertEqual(defaultEncryption, .AES256)
                choices += 1
                return SZArchiveUpdateEncryption(encryption: defaultEncryption, password: added.password)
            }

            try fixture.archive.addPaths([source.path], toArchiveSubdir: "", moveMode: false, session: session)

            XCTAssertEqual(choices, 1)
            try verify([original, later, added], in: fixture)
        }
    }

    func testUnknownFirstEncryptionDefaultsToNoneWithoutUsingLaterKnownEncryption() throws {
        let fixture = try makeArchive([
            Member(path: "a-unknown.txt", contents: "unknown secret", encryption: .zipCrypto, password: "first"),
            Member(path: "z-known.txt", contents: "known secret", encryption: .AES256, password: "later"),
        ])
        defer { fixture.archive.close() }
        try rewriteFixture(fixture) { data, records in
            let first = try XCTUnwrap(records.first { $0.path == "a-unknown.txt" })
            // The core reports StrongCrypto for this unsupported metadata.
            // Cancel before writing; its payload is intentionally not decrypted.
            data[first.localNameRange.lowerBound - 30 + 6] |= 0x40
            data[first.centralNameRange.lowerBound - 46 + 8] |= 0x40
        }
        let entries = fixture.archive.entries().sorted { $0.index < $1.index }
        XCTAssertEqual(entries.map(\.path), ["a-unknown.txt", "z-known.txt"])
        let first = try XCTUnwrap(entries.first)
        let last = try XCTUnwrap(entries.last)
        XCTAssertTrue(first.isEncrypted)
        XCTAssertTrue(first.method?.hasPrefix("StrongCrypto ") == true)
        XCTAssertTrue(last.method?.hasPrefix("AES-256 ") == true)
        let originalData = try Data(contentsOf: fixture.archiveURL)
        let source = try write("new contents", named: "added.txt", under: fixture.root)
        var choices = 0
        let session = SZOperationSession()
        session.updateEncryptionRequestHandler = { _, defaultEncryption in
            XCTAssertEqual(defaultEncryption, .none)
            choices += 1
            return nil
        }

        XCTAssertThrowsError(try fixture.archive.addPaths([source.path], toArchiveSubdir: "", moveMode: true, session: session)) {
            XCTAssertTrue(szIsUserCancellation($0))
            XCTAssertFalse(szArchiveMutationWasCommitted($0))
        }
        XCTAssertEqual(choices, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), originalData)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new contents")
    }

    func testBatchUpdateUsesOneSelectionForNewAndOverwrittenEntriesWithoutReadingOldPasswords() throws {
        for encryption in [SZEncryptionMethod.AES256, .zipCrypto] {
            let untouched = [
                Member(path: "keep-plain.txt", contents: "keep public", encryption: .none, password: nil),
                Member(path: "keep-legacy.txt", contents: "keep legacy", encryption: .zipCrypto, password: "keep-one"),
                Member(path: "keep-secret.txt", contents: "keep secret", encryption: .AES256, password: "keep-two"),
            ]
            let overwritten = [
                Member(path: "plain.txt", contents: "old public", encryption: .none, password: nil),
                Member(path: "legacy.txt", contents: "old legacy", encryption: .zipCrypto, password: "one"),
                Member(path: "secret.txt", contents: "old secret", encryption: .AES256, password: "two"),
            ]
            let fixture = try makeArchive(untouched + overwritten)
            defer { fixture.archive.close() }
            let originalData = try Data(contentsOf: fixture.archiveURL)
            let originalRecords = try zipFixtureRecords(in: originalData)
            let updated = (overwritten.map(\.path) + ["added.txt"]).map {
                Member(path: $0, contents: "updated \($0)", encryption: encryption, password: "new-password")
            }
            let sources = try updated.map { try write($0.contents, named: $0.path, under: fixture.root) }
            var choices = 0
            let session = SZOperationSession()
            session.passwordRequestHandler = { _, _, _, _ in
                XCTFail("Copying old ZIP records must not request their read passwords")
                return false
            }
            session.updateEncryptionRequestHandler = { path, defaultEncryption in
                XCTAssertEqual(path, fixture.archiveURL.path)
                XCTAssertEqual(defaultEncryption, .zipCrypto)
                choices += 1
                return SZArchiveUpdateEncryption(encryption: encryption, password: "new-password")
            }
            try fixture.archive.addPaths(sources.map(\.path), toArchiveSubdir: "", moveMode: false, session: session)

            XCTAssertEqual(choices, 1, "One update must make one choice for all new data")
            try verify(untouched + updated, in: fixture)
            let updatedData = try Data(contentsOf: fixture.archiveURL)
            let updatedRecords = try zipFixtureRecords(in: updatedData)
            for member in untouched {
                let original = try XCTUnwrap(originalRecords.first { $0.path == member.path })
                let updated = try XCTUnwrap(updatedRecords.first { $0.path == member.path })
                XCTAssertEqual(originalData[original.packedDataRange], updatedData[updated.packedDataRange],
                               "Untouched \(member.path) must retain its original compressed/encrypted bytes")
            }
        }
    }

    func testChoosingNoEncryptionOnlyRemovesProtectionFromNewAndOverwrittenData() throws {
        let untouched = Member(path: "keep.txt", contents: "still secret", encryption: .AES256, password: "keep-password")
        let fixture = try makeArchive([
            untouched,
            Member(path: "replace.txt", contents: "old secret", encryption: .zipCrypto, password: "old-password"),
        ])
        defer { fixture.archive.close() }
        let readSession = SZOperationSession()
        readSession.passwordRequestHandler = { _, message, _, password in
            password?.pointee = (message?.contains("keep.txt") == true ? "keep-password" : "old-password") as NSString
            return true
        }
        try fixture.archive.test(with: readSession)
        let originalData = try Data(contentsOf: fixture.archiveURL)
        let originalRecords = try zipFixtureRecords(in: originalData)
        let replacement = try write("public replacement", named: "replace.txt", under: fixture.root)
        let added = try write("public addition", named: "added.txt", under: fixture.root)
        let selection = SZArchiveUpdateEncryption(encryption: .none, password: "ignored-hidden-password")
        XCTAssertNil(selection.password)
        XCTAssertNoThrow(try selection.validate())
        var choices = 0
        let session = SZOperationSession()
        session.updateEncryptionRequestHandler = { _, _ in
            choices += 1
            return selection
        }
        try fixture.archive.addPaths([replacement.path, added.path], toArchiveSubdir: "", moveMode: false, session: session)

        XCTAssertEqual(choices, 1)
        try verify([
            untouched,
            Member(path: "replace.txt", contents: "public replacement", encryption: .none, password: nil),
            Member(path: "added.txt", contents: "public addition", encryption: .none, password: nil),
        ], in: fixture)
        let updatedData = try Data(contentsOf: fixture.archiveURL)
        let updatedRecords = try zipFixtureRecords(in: updatedData)
        let original = try XCTUnwrap(originalRecords.first { $0.path == untouched.path })
        let updated = try XCTUnwrap(updatedRecords.first { $0.path == untouched.path })
        XCTAssertEqual(originalData[original.packedDataRange], updatedData[updated.packedDataRange])
    }

    func testCancelledOrMissingSelectionPreservesArchiveAndMoveSource() throws {
        for encryption in [SZEncryptionMethod.none, .AES256] {
            for installCancellingHandler in [false, true] {
                let original = Member(path: "existing.txt", contents: "original", encryption: encryption,
                                      password: encryption == .none ? nil : "old")
                let fixture = try makeArchive([original])
                defer { fixture.archive.close() }
                let originalData = try Data(contentsOf: fixture.archiveURL)
                let source = try write("replacement", named: original.path, under: fixture.root)
                var choices = 0
                let session = SZOperationSession()
                if installCancellingHandler {
                    session.updateEncryptionRequestHandler = { _, defaultEncryption in
                        XCTAssertEqual(defaultEncryption, encryption)
                        choices += 1
                        return nil
                    }
                }
                XCTAssertThrowsError(try fixture.archive.addPaths([source.path], toArchiveSubdir: "", moveMode: true, session: session)) { error in
                    XCTAssertTrue(szIsUserCancellation(error), "Expected cancellation, got \(error)")
                    XCTAssertFalse(szArchiveMutationWasCommitted(error))
                }
                XCTAssertEqual(choices, installCancellingHandler ? 1 : 0)
                XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), originalData)
                XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "replacement")
                try verify([original], in: fixture)
            }
        }
    }

    func testInvalidSelectionPreservesArchiveAndMoveSource() throws {
        let invalidEncryption = try XCTUnwrap(SZEncryptionMethod(rawValue: 999))
        let choices = [
            SZArchiveUpdateEncryption(encryption: .AES256, password: nil),
            SZArchiveUpdateEncryption(encryption: .zipCrypto, password: ""),
            SZArchiveUpdateEncryption(encryption: invalidEncryption, password: "password"),
            SZArchiveUpdateEncryption(encryption: .AES256, password: "密码"),
            SZArchiveUpdateEncryption(encryption: .zipCrypto, password: "密码"),
            SZArchiveUpdateEncryption(encryption: .AES256, password: "before\0after"),
            SZArchiveUpdateEncryption(encryption: .zipCrypto, password: "before\nafter"),
            SZArchiveUpdateEncryption(encryption: .AES256, password: String(repeating: "a", count: 100)),
        ]
        for selection in choices {
            let fixture = try makeArchive([
                Member(path: "existing.txt", contents: "original", encryption: .AES256, password: "old"),
            ])
            defer { fixture.archive.close() }
            let originalData = try Data(contentsOf: fixture.archiveURL)
            let source = try write("replacement", named: "existing.txt", under: fixture.root)
            var requests = 0
            let session = SZOperationSession()
            session.updateEncryptionRequestHandler = { _, _ in
                requests += 1
                return selection
            }
            XCTAssertThrowsError(try fixture.archive.addPaths([source.path], toArchiveSubdir: "", moveMode: true, session: session)) { error in
                XCTAssertFalse(szArchiveMutationWasCommitted(error))
            }
            XCTAssertEqual(requests, 1)
            XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), originalData)
            XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "replacement")
        }
    }

    func testCancelledReplacementPreservesArchiveAndSelectedEntry() throws {
        for encryption in [SZEncryptionMethod.none, .AES256] {
            let original = Member(path: "existing.txt", contents: "original", encryption: encryption,
                                  password: encryption == .none ? nil : "old")
            let fixture = try makeArchive([original])
            defer { fixture.archive.close() }
            let originalData = try Data(contentsOf: fixture.archiveURL)
            let source = try write("replacement", named: "replacement.txt", under: fixture.root)
            let reference = try XCTUnwrap(fixture.archive.entries().first?.reference)
            var choices = 0
            let session = SZOperationSession()
            session.updateEncryptionRequestHandler = { _, defaultEncryption in
                XCTAssertEqual(defaultEncryption, encryption)
                choices += 1
                return nil
            }
            XCTAssertThrowsError(try fixture.archive.replaceItem(at: reference, inArchiveSubdir: "",
                                                                 withFileAtPath: source.path, session: session))
            { error in
                XCTAssertTrue(szIsUserCancellation(error))
                XCTAssertFalse(szArchiveMutationWasCommitted(error))
            }
            XCTAssertEqual(choices, 1)
            XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), originalData)
            XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "replacement")
            try verify([original], in: fixture)
        }
    }

    func testReplacementChangesOnlyTheSelectedDuplicateRecord() throws {
        let fixture = try makeArchive([
            Member(path: "legacy.txt", contents: "keep legacy", encryption: .zipCrypto, password: "one"),
            Member(path: "secret.txt", contents: "replace secret", encryption: .AES256, password: "two"),
        ])
        defer { fixture.archive.close() }
        try rewriteFixture(fixture) { data, records in
            let secret = try XCTUnwrap(records.first { $0.path == "secret.txt" })
            let duplicateName = Data("legacy.txt".utf8)
            XCTAssertEqual(secret.localNameRange.count, duplicateName.count)
            XCTAssertEqual(secret.centralNameRange.count, duplicateName.count)
            data.replaceSubrange(secret.localNameRange, with: duplicateName)
            data.replaceSubrange(secret.centralNameRange, with: duplicateName)
        }
        let entries = fixture.archive.entries()
        let selected = try XCTUnwrap(entries.first { $0.method?.contains("AES-256") == true })
        let source = try write("replacement", named: "source.txt", under: fixture.root)
        var choices = 0
        let session = SZOperationSession()
        session.updateEncryptionRequestHandler = { _, defaultEncryption in
            XCTAssertEqual(defaultEncryption, .zipCrypto, "The first record determines the default, even when replacing the later AES record")
            choices += 1
            return SZArchiveUpdateEncryption(encryption: .zipCrypto, password: "new-password")
        }
        try fixture.archive.replaceItem(at: selected.reference, inArchiveSubdir: "", withFileAtPath: source.path, session: session)

        XCTAssertEqual(choices, 1)
        XCTAssertEqual(fixture.archive.entries().count, 2)
        XCTAssertEqual(Set(fixture.archive.entries().map(\.path)), ["legacy.txt"])
        for original in entries {
            let replaced = original.index == selected.index
            let expected = Member(path: "legacy.txt", contents: replaced ? "replacement" : "keep legacy",
                                  encryption: .zipCrypto, password: replaced ? "new-password" : "one")
            let reopened = SZArchive()
            try reopened.open(atPath: fixture.archiveURL.path, session: SZOperationSession())
            defer { reopened.close() }
            let entry = try XCTUnwrap(reopened.entries().first { $0.index == original.index })
            try assertMember(expected, entry: entry, in: reopened,
                             destination: fixture.root.appendingPathComponent("duplicate-\(entry.index)"))
        }
    }

    func testMetadataOnlyChangesDoNotRequestWriteEncryption() throws {
        let fixture = try makeArchive([
            Member(path: "existing.txt", contents: "keep secret", encryption: .AES256, password: "old"),
            Member(path: "delete.txt", contents: "delete secret", encryption: .zipCrypto, password: "other"),
        ])
        defer { fixture.archive.close() }
        let session = SZOperationSession()
        session.updateEncryptionRequestHandler = { _, _ in
            XCTFail("Metadata-only ZIP mutations must preserve encryption without a write choice")
            return nil
        }
        session.passwordRequestHandler = { _, _, _, _ in
            XCTFail("Metadata-only ZIP mutations must not need the data passwords")
            return false
        }
        try fixture.archive.createFolderNamed("empty", inArchiveSubdir: "", session: session)
        let existing = try XCTUnwrap(fixture.archive.entries().first { $0.path == "existing.txt" })
        try fixture.archive.renameItem(at: existing.reference, inArchiveSubdir: "", newName: "renamed.txt", session: session)
        let deleted = try XCTUnwrap(fixture.archive.entries().first { $0.path == "delete.txt" })
        try fixture.archive.deleteItems(at: [deleted.reference], inArchiveSubdir: "", session: session)

        XCTAssertTrue(fixture.archive.entries().contains { $0.path == "empty" && $0.isDirectory })
        XCTAssertFalse(fixture.archive.entries().contains { $0.path == "delete.txt" })
        let reopened = SZArchive()
        try reopened.open(atPath: fixture.archiveURL.path, session: SZOperationSession())
        defer { reopened.close() }
        let renamed = try XCTUnwrap(reopened.entries().first { $0.path == "renamed.txt" })
        try assertMember(Member(path: "renamed.txt", contents: "keep secret", encryption: .AES256, password: "old"),
                         entry: renamed, in: reopened, destination: fixture.root.appendingPathComponent("metadata"))
    }

    func testPlainZipBatchUpdateDefaultsToNoneAndAllowsEveryEncryptionChoice() throws {
        for encryption in [SZEncryptionMethod.none, .AES256, .zipCrypto] {
            let untouched = Member(path: "keep.txt", contents: "still public", encryption: .none, password: nil)
            let fixture = try makeArchive([
                untouched,
                Member(path: "existing.txt", contents: "original", encryption: .none, password: nil),
            ])
            defer { fixture.archive.close() }
            fixture.archive.close()
            try fixture.archive.open(atPath: fixture.archiveURL.path, password: "unverified-open-password", session: SZOperationSession())
            let password = encryption == .none ? nil : "new-password"
            let updated = [
                Member(path: "existing.txt", contents: "replacement", encryption: encryption, password: password),
                Member(path: "added.txt", contents: "added", encryption: encryption, password: password),
            ]
            let sources = try updated.map { try write($0.contents, named: $0.path, under: fixture.root) }
            var choices = 0
            let session = SZOperationSession()
            session.updateEncryptionRequestHandler = { path, defaultEncryption in
                XCTAssertEqual(path, fixture.archiveURL.path)
                XCTAssertEqual(defaultEncryption, .none)
                choices += 1
                return SZArchiveUpdateEncryption(encryption: encryption, password: password)
            }

            try fixture.archive.addPaths(sources.map(\.path), toArchiveSubdir: "", moveMode: false, session: session)

            XCTAssertEqual(choices, 1)
            try verify([untouched] + updated, in: fixture)
        }
    }

    func testPlainZipExactReplacementDefaultsToNoneAndAllowsEveryEncryptionChoice() throws {
        for encryption in [SZEncryptionMethod.none, .AES256, .zipCrypto] {
            let untouched = Member(path: "keep.txt", contents: "still public", encryption: .none, password: nil)
            let fixture = try makeArchive([
                untouched,
                Member(path: "existing.txt", contents: "original", encryption: .none, password: nil),
            ])
            defer { fixture.archive.close() }
            fixture.archive.close()
            try fixture.archive.open(atPath: fixture.archiveURL.path, password: "unverified-open-password", session: SZOperationSession())
            let password = encryption == .none ? nil : "new-password"
            let source = try write("replacement", named: "source.txt", under: fixture.root)
            let existing = try XCTUnwrap(fixture.archive.entries().first { $0.path == "existing.txt" })
            var choices = 0
            let session = SZOperationSession()
            session.updateEncryptionRequestHandler = { path, defaultEncryption in
                XCTAssertEqual(path, fixture.archiveURL.path)
                XCTAssertEqual(defaultEncryption, .none)
                choices += 1
                return SZArchiveUpdateEncryption(encryption: encryption, password: password)
            }

            try fixture.archive.replaceItem(at: existing.reference, inArchiveSubdir: "", withFileAtPath: source.path, session: session)

            XCTAssertEqual(choices, 1)
            try verify([
                untouched,
                Member(path: "existing.txt", contents: "replacement", encryption: encryption, password: password),
            ], in: fixture)
        }
    }

    func testEmptyZipDefaultsToNoneAndCanEncryptNewData() throws {
        let fixture = try makeArchive([
            Member(path: "seed.txt", contents: "seed", encryption: .none, password: nil),
        ])
        defer { fixture.archive.close() }
        let seed = try XCTUnwrap(fixture.archive.entries().first?.reference)
        try fixture.archive.deleteItems(at: [seed], inArchiveSubdir: "", session: SZOperationSession())
        XCTAssertTrue(fixture.archive.entries().isEmpty)
        let added = Member(path: "added.txt", contents: "first secret", encryption: .AES256, password: "new-password")
        let source = try write(added.contents, named: added.path, under: fixture.root)
        var choices = 0
        let session = SZOperationSession()
        session.updateEncryptionRequestHandler = { _, defaultEncryption in
            XCTAssertEqual(defaultEncryption, .none)
            choices += 1
            return SZArchiveUpdateEncryption(encryption: added.encryption, password: added.password)
        }

        try fixture.archive.addPaths([source.path], toArchiveSubdir: "", moveMode: false, session: session)

        XCTAssertEqual(choices, 1)
        try verify([added], in: fixture)
    }

    func testCancellationDuringSelectionIgnoresReturnedEncryptionAndPreservesMoveSource() throws {
        let original = Member(path: "existing.txt", contents: "original", encryption: .none, password: nil)
        let fixture = try makeArchive([original])
        defer { fixture.archive.close() }
        let originalData = try Data(contentsOf: fixture.archiveURL)
        let source = try write("replacement", named: original.path, under: fixture.root)
        var choices = 0
        let session = SZOperationSession()
        session.updateEncryptionRequestHandler = { [weak session] _, defaultEncryption in
            XCTAssertEqual(defaultEncryption, .none)
            choices += 1
            session?.requestCancel()
            return SZArchiveUpdateEncryption(encryption: .AES256, password: "new-password")
        }

        XCTAssertThrowsError(try fixture.archive.addPaths([source.path], toArchiveSubdir: "", moveMode: true, session: session)) {
            XCTAssertTrue(szIsUserCancellation($0))
            XCTAssertFalse(szArchiveMutationWasCommitted($0))
        }
        XCTAssertEqual(choices, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), originalData)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "replacement")
        try verify([original], in: fixture)
    }
}
