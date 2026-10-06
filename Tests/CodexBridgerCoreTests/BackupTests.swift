import XCTest
@testable import CodexBridgerCore

/// Seam: BackupManager public API.
final class BackupTests: XCTestCase {

    func testBackupFileNameMatchesRequiredFormat() {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 5
        components.hour = 19; components.minute = 30
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components)!
        // The provider segment names whoever the backed-up file belongs to.
        XCTAssertEqual(
            BackupManager.backupFileName(kind: .config, provider: "deepseek", date: date),
            "config-deepseek-2026-10-05-1930-bak.toml"
        )
        XCTAssertEqual(
            BackupManager.backupFileName(kind: .auth, provider: "deepseek", date: date),
            "auth-deepseek-2026-10-05-1930-bak.json"
        )
    }

    /// A config that names no provider must still produce a well-formed filename.
    func testBackupFileNameFallsBackWhenNoProviderIsKnown() {
        let date = Date()
        XCTAssertEqual(
            BackupManager.backupFileName(kind: .config, provider: "  ", date: date),
            "config-unknown-" + BackupManager.backupFileName(kind: .config, provider: "x", date: date)
                .dropFirst("config-x-".count)
        )
    }

    /// A provider name must not be able to escape the backup directory.
    func testBackupFileNameCannotBeUsedAsAPath() {
        let name = BackupManager.backupFileName(
            kind: .config, provider: "../../etc/passwd", date: Date())
        XCTAssertFalse(name.contains("/"), "a path separator must not survive: " + name)
        XCTAssertFalse(name.contains(".."), "parent traversal must not survive: " + name)
    }

    func testSecondBackupInSameMinuteIsNotOverwritten() {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 5
        components.hour = 19; components.minute = 30
        let date = Calendar(identifier: .gregorian).date(from: components)!
        XCTAssertEqual(
            BackupManager.backupFileName(kind: .config, provider: "deepseek", date: date, sequence: 2),
            "config-deepseek-2026-10-05-1930-bak-2.toml"
        )
    }

    func testBackupCopiesIntoConfigBackupFolderAndPreservesEarlierCopy() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let manager = BackupManager(paths: paths)
        let date = Date()

        try AtomicFile.write("first", to: paths.configTOML)
        let first = try manager.backup(paths.configTOML, kind: .config, now: date)
        XCTAssertNotNil(first)

        try AtomicFile.write("second", to: paths.configTOML)
        let second = try manager.backup(paths.configTOML, kind: .config, now: date)
        XCTAssertNotNil(second)

        XCTAssertEqual(first?.deletingLastPathComponent().path, paths.backupDirectory.path)
        XCTAssertEqual(second?.deletingLastPathComponent().path, paths.backupDirectory.path)
        XCTAssertNotEqual(first?.path, second?.path, "same-minute backups must not collide")
        XCTAssertEqual(try String(contentsOf: first!), "first")
        XCTAssertEqual(try String(contentsOf: second!), "second")
    }

    func testBackupReturnsNilWhenSourceMissing() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        XCTAssertNil(try BackupManager(paths: paths).backup(paths.configTOML, kind: .config))
    }
}
