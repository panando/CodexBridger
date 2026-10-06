import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: the backup browser in Settings.
///
/// The listing is real filesystem behaviour, so it is tested against a real directory rather
/// than through the view: what matters is that it finds the right files, ignores directories,
/// and puts the newest first.
final class BackupBrowserTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("backups-" + UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func write(_ name: String, contents: String = "x") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// A directory that has never been written to is the normal first-run state.
    func testNoBackupDirectoryYetIsAnEmptyListNotAnError() throws {
        XCTAssertTrue(try BackupFile.list(in: directory).isEmpty)
    }

    func testTheNewestBackupComesFirst() throws {
        try write("config-cpa-2026-02-01-1015-bak.toml")
        try write("config-cpa-2026-02-03-1015-bak.toml")
        try write("config-cpa-2026-02-02-1015-bak.toml")
        let names = try BackupFile.list(in: directory).map(\.name)
        XCTAssertEqual(names, [
            "config-cpa-2026-02-03-1015-bak.toml",
            "config-cpa-2026-02-02-1015-bak.toml",
            "config-cpa-2026-02-01-1015-bak.toml",
        ])
    }

    /// Nested folders must not be offered as files to open.
    func testDirectoriesAreNotListedAsBackups() throws {
        try write("config-cpa-2026-02-01-1015-bak.toml")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("nested"), withIntermediateDirectories: true
        )
        let names = try BackupFile.list(in: directory).map(\.name)
        XCTAssertEqual(names, ["config-cpa-2026-02-01-1015-bak.toml"])
    }

    /// Each row reports a size and a time, and marks itself by its full path.
    func testEachRowReportsItsSizeAndPath() throws {
        try write("config-cpa-2026-02-01-1015-bak.toml", contents: "0123456789")
        let row = try XCTUnwrap(try BackupFile.list(in: directory).first)
        XCTAssertEqual(row.name, "config-cpa-2026-02-01-1015-bak.toml")
        // Resolved, because the temporary directory is reached through /var -> /private/var and
        // the directory listing comes back with the real path.
        let expected = directory.appendingPathComponent(row.name).resolvingSymlinksInPath()
        XCTAssertEqual(row.url.resolvingSymlinksInPath().path, expected.path)
        XCTAssertFalse(row.size.isEmpty, "a size is shown for every row")
        XCTAssertFalse(row.modified.isEmpty, "a modification time is shown for every row")
        XCTAssertNotEqual(row.modified, "—", "a real file has a real modification time")
    }

    /// The table grows with the rows and stops growing at the cap.
    func testTheTableGrowsWithItsRowsAndThenStops() {
        let one = BackupFile.tableHeight(forRowCount: 1)
        let three = BackupFile.tableHeight(forRowCount: 3)
        XCTAssertLessThan(one, three, "more rows need more height")
        XCTAssertLessThanOrEqual(three, SettingsView.maxTableHeight, "the cap holds")
        XCTAssertGreaterThan(
            BackupFile.tableHeight(forRowCount: 500), SettingsView.maxTableHeight,
            "a long list is capped and scrolls instead of growing without limit"
        )
    }
}