import XCTest
@testable import CodexBridgerCore

/// Seam: the app on a machine that is not the one it was built on.
///
/// Before shipping, every path has to survive being used by someone else: their home directory,
/// their language, their spaces, their permissions. These tests build those situations rather
/// than trusting that they work, because a path bug is invisible on the developer's machine —
/// it only shows up after install, as "the app does nothing".
final class PortabilityTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("portable-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            // A read-only directory cannot be removed until its mode is restored.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func paths(home: URL) -> CodexPaths {
        CodexPaths(environment: ["CODEX_HOME": home.path])
    }

    private func provider(id: String = "cpa") -> ProviderConfiguration {
        ProviderPreset.builtIn[0].makeProvider(id: id)
    }

    // MARK: - A home directory that does not exist yet

    /// The first launch on a machine that has never had Codex installed.
    func testANonexistentHomeIsCreatedForAFreshInstall() throws {
        let home = root.appendingPathComponent("never/created/.codex", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path), "precondition")

        let store = ConfigurationStore(paths: paths(home: home))
        var configuration = CodexBridgerConfiguration()
        configuration.providers = [provider()]
        try store.save(configuration)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.paths.appConfiguration.path),
                      "the whole chain of folders is created on demand")
        XCTAssertEqual(try store.load().providers.count, 1, "and it reads back")
    }

    /// Activation writes three files into folders that do not exist beforehand.
    func testActivationWorksWithNoPreexistingFolders() throws {
        let home = root.appendingPathComponent("fresh/.codex", isDirectory: true)
        let p = paths(home: home)
        let provider = provider()
        let model = try XCTUnwrap(provider.models.first)
        var configuration = CodexBridgerConfiguration()
        configuration.providers = [provider]

        let writer = CodexConfigWriter(paths: p, templateSource: StaticCatalogTemplate())
        _ = try writer.activate(
            provider: provider, model: model, configuration: configuration, managedProviderIDs: []
        )

        for url in [p.configTOML, p.authJSON, p.catalog(for: provider.id)] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "missing after activation: " + url.lastPathComponent)
        }
    }

    // MARK: - Awkward home paths, which are normal on a real Mac

    func testAHomeDirectoryWithSpacesAndNonASCIIWorks() throws {
        let home = root.appendingPathComponent("我的 Mac/代码 配置/.codex", isDirectory: true)
        let p = paths(home: home)
        XCTAssertEqual(p.codexHome.path, home.path, "the path is not mangled")

        let provider = provider()
        let model = try XCTUnwrap(provider.models.first)
        var configuration = CodexBridgerConfiguration()
        configuration.providers = [provider]

        let writer = CodexConfigWriter(paths: p, templateSource: StaticCatalogTemplate())
        _ = try writer.activate(
            provider: provider, model: model, configuration: configuration, managedProviderIDs: []
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: p.configTOML.path))
        XCTAssertTrue(p.catalog(for: provider.id).path.hasPrefix(root.path),
                      "everything stays under the configured home")
    }

    /// A `~` in CODEX_HOME has to expand, or the app writes to a folder literally named "~".
    func testATildeInTheEnvironmentValueIsExpanded() {
        let p = CodexPaths(environment: ["CODEX_HOME": "~/.codex"])
        XCTAssertFalse(p.codexHome.path.hasPrefix("~"),
                       "an unexpanded tilde would create a directory named ~")
    }

    // MARK: - A home that cannot be written

    func testAnUnwritableHomeReportsAnErrorInsteadOfCrashing() throws {
        let home = root.appendingPathComponent("readonly/.codex", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: home.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: home.path
            )
        }

        let store = ConfigurationStore(paths: paths(home: home))
        XCTAssertThrowsError(try store.save(CodexBridgerConfiguration())) { error in
            XCTAssertFalse(error.localizedDescription.isEmpty,
                           "the failure must be explainable to the user")
        }
    }

    // MARK: - No CLI installed

    /// The CLI is an optional enhancement; asking for it must never trap.
    func testAskingForTheCLINeverTrapsWhenNoneIsInstalled() {
        let cli = CodexCLI.locate(
            environment: ["PATH": "/nonexistent-dir-xyz"],
            fileManager: .default
        )
        if let cli {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: cli.executableURL.path),
                          "only a runnable file may be returned")
        }
    }

    /// An explicit override wins, which is the escape hatch for unusual installs.
    func testAnEnvironmentOverrideIsPreferred() throws {
        let fake = root.appendingPathComponent("fake-codex")
        try "#!/bin/sh\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let found = CodexCLI.candidateURLs(
            environment: ["CODEX_CLI_PATH": fake.path, "PATH": "/usr/bin"],
            fileManager: .default
        )
        XCTAssertEqual(found.first?.path, fake.path, "the override is tried first")
    }

    /// A file without the execute bit must not be selected.
    func testANonExecutableOverrideIsRejected() throws {
        let fake = root.appendingPathComponent("not-executable")
        try "#!/bin/sh\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fake.path)

        let found = CodexCLI.candidateURLs(
            environment: ["CODEX_CLI_PATH": fake.path, "PATH": "/nonexistent-dir-xyz"],
            fileManager: .default
        )
        XCTAssertFalse(found.contains { $0.path == fake.path },
                       "a file without the execute bit cannot be run")
    }

    /// Every path the app writes to stays inside the configured home.
    func testEveryWrittenPathStaysInsideTheConfiguredHome() {
        let home = URL(fileURLWithPath: "/tmp/portability-check/.codex", isDirectory: true)
        let p = paths(home: home)
        let written = [
            p.configTOML, p.authJSON, p.appConfiguration,
            p.catalog(for: "cpa"), p.backupDirectory, p.modelCatalogsDirectory,
        ]
        for url in written {
            XCTAssertTrue(url.path.hasPrefix(home.path),
                          "escaped the home directory: " + url.path)
        }
    }
}