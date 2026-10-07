import XCTest
@testable import CodexBridgerCore

/// Seam: ModelCatalogFiles.list(in:) — the "import from a file already on this machine" list.
///
/// The picker offers the catalogs sitting in <codex home>/model-catalogs. It has to survive a
/// directory holding backups, half-written files and things that are not catalogs at all.
final class ModelCatalogFilesTests: XCTestCase {

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    private func catalogJSON(slugs: [String]) throws -> String {
        let models = slugs.map { ["slug": $0, "display_name": $0] }
        let data = try JSONSerialization.data(withJSONObject: ["models": models])
        return String(decoding: data, as: UTF8.self)
    }

    func testMissingDirectoryReturnsAnEmptyList() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }

        XCTAssertTrue(ModelCatalogFiles.list(in: paths.modelCatalogsDirectory).isEmpty)
    }

    func testListsOnlyJSONFiles() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        try write(try catalogJSON(slugs: ["a"]), to: paths.catalog(for: "alpha"))
        try write("not a catalog", to: paths.modelCatalogsDirectory.appendingPathComponent("notes.txt"))
        try write("{}", to: paths.modelCatalogsDirectory.appendingPathComponent("no-extension"))

        let found = ModelCatalogFiles.list(in: paths.modelCatalogsDirectory)

        XCTAssertEqual(found.map(\.name), ["alpha-model-catalog.json"])
    }

    func testReportsTheModelCountOfEachFile() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        try write(try catalogJSON(slugs: ["a", "b", "c"]), to: paths.catalog(for: "many"))
        try write(try catalogJSON(slugs: ["only"]), to: paths.catalog(for: "one"))

        let found = ModelCatalogFiles.list(in: paths.modelCatalogsDirectory)
        let byName = Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0) })

        XCTAssertEqual(byName["many-model-catalog.json"]?.modelCount, 3)
        XCTAssertEqual(byName["one-model-catalog.json"]?.modelCount, 1)
    }

    func testFileThatIsNotACatalogStillListedWithoutAModelCount() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        try write("{ not json", to: paths.modelCatalogsDirectory.appendingPathComponent("broken.json"))

        let found = ModelCatalogFiles.list(in: paths.modelCatalogsDirectory)

        XCTAssertEqual(found.count, 1, "a broken file is still a file the user may want to try")
        XCTAssertNil(found[0].modelCount, "but its model count is unknown")
    }

    func testReportsByteCountAndModificationDate() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let text = try catalogJSON(slugs: ["a", "b"])
        try write(text, to: paths.catalog(for: "sized"))

        let found = ModelCatalogFiles.list(in: paths.modelCatalogsDirectory)

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].byteCount, Data(text.utf8).count)
        XCTAssertNotNil(found[0].modifiedAt)
    }

    func testListsNewestFirst() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let oldest = paths.catalog(for: "oldest")
        let middle = paths.catalog(for: "middle")
        let newest = paths.catalog(for: "newest")
        for url in [oldest, middle, newest] {
            try write(try catalogJSON(slugs: ["x"]), to: url)
        }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: base], ofItemAtPath: oldest.path)
        try FileManager.default.setAttributes(
            [.modificationDate: base.addingTimeInterval(60)], ofItemAtPath: middle.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: base.addingTimeInterval(120)], ofItemAtPath: newest.path
        )

        let found = ModelCatalogFiles.list(in: paths.modelCatalogsDirectory)

        XCTAssertEqual(
            found.map(\.name),
            ["newest-model-catalog.json", "middle-model-catalog.json", "oldest-model-catalog.json"]
        )
    }

    func testIgnoresSubdirectories() throws {
        let (paths, root) = try TestSupport.makeTemporaryCodexHome()
        defer { TestSupport.remove(root) }
        let directory = paths.modelCatalogsDirectory.appendingPathComponent("nested.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertTrue(ModelCatalogFiles.list(in: paths.modelCatalogsDirectory).isEmpty)
    }
}
