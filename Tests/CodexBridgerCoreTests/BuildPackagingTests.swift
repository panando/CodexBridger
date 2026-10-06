import XCTest
@testable import CodexBridgerCore

/// Seam: what ships, and the scripts that produce it.
///
/// These guard packaging facts that no amount of Swift testing would otherwise notice, and
/// each one is here because it actually went wrong:
///
/// - The version lives in VERSION, but `plutil -replace` fails on a missing key, so the
///   Info.plist template has to keep carrying both version keys.
/// - `./scripts/build-app.sh` — the command the README tells people to run — was broken by
///   macOS's bash 3.2, where an empty array under `set -u` reports "unbound variable".
/// - The archive check piped into `grep -q`, whose early exit sent SIGPIPE into `unzip` and
///   made `pipefail` call a good archive broken.
final class BuildPackagingTests: XCTestCase {

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(at relativePath: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    // MARK: - The version

    func testTheVersionFileExistsAndAppleWouldAcceptIt() throws {
        let raw = try text(at: "VERSION")
        let version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // CFBundleShortVersionString allows one to three period-separated integers.
        let pattern = "^[0-9]+(\\.[0-9]+){0,2}$"
        XCTAssertNotNil(
            version.range(of: pattern, options: .regularExpression),
            "VERSION holds \"\(version)\", which Apple would reject for a bundle"
        )
        XCTAssertEqual(version, "1.0.0", "the version this release ships as")
    }

    /// Stamping replaces these keys, so removing them from the template breaks the build.
    func testThePlistTemplateKeepsTheKeysTheBuildStamps() throws {
        let plist = try text(at: "support/Info.plist")
        XCTAssertTrue(plist.contains("CFBundleShortVersionString"),
                      "the build stamps this key, and plutil -replace needs it to exist")
        XCTAssertTrue(plist.contains("CFBundleVersion"),
                      "the build stamps the build number into this key")
    }

    /// The About screen has no hard-coded version; it reads the running bundle.
    func testTheAboutScreenReadsTheBundleRatherThanAConstant() throws {
        let view = try text(at: "Sources/CodexBridgerUI/SettingsView.swift")
        XCTAssertTrue(view.contains("CFBundleShortVersionString"),
                      "the displayed version must come from the bundle that was built")
        XCTAssertTrue(view.contains("Bundle.main.infoDictionary"))
    }

    // MARK: - The build scripts

    private func buildScriptNames() -> [String] {
        ["scripts/build-app.sh", "scripts/build-dmg.sh", "scripts/build-zip.sh"]
    }

    /// macOS bash 3.2 fails on an empty array under `set -u`. The array must be expanded
    /// with the `${VAR[@]+...}` guard everywhere it is used.
    func testTheBuildScriptsGuardTheirEmptyArrayExpansion() throws {
        for name in buildScriptNames() {
            let script = try text(at: name)
            XCTAssertTrue(script.contains("set -euo pipefail"),
                          "\(name) should fail fast")
            for (index, line) in script.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("#") == false else { continue }
                guard trimmed.contains("ARCH_ARGS[@]") else { continue }
                XCTAssertTrue(
                    trimmed.contains("ARCH_ARGS[@]+"),
                    "\(name):\(index + 1) expands ARCH_ARGS without the bash 3.2 guard: \(trimmed)"
                )
            }
        }
    }

    /// A pipeline into `grep -q` under `pipefail` reports SIGPIPE as failure.
    func testNoScriptPipesIntoGrepQuiet() throws {
        for name in buildScriptNames() {
            for (index, line) in try text(at: name)
                .split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#") else { continue }
                guard trimmed.contains("| grep -q") else { continue }
                XCTFail("\(name):\(index + 1) pipes into grep -q, which trips pipefail: \(trimmed)")
            }
        }
    }

    /// Every packaging script must refuse to produce an artefact whose name disagrees with
    /// the version inside it.
    func testThePackagingScriptsCheckTheBundleVersion() throws {
        for name in ["scripts/build-dmg.sh", "scripts/build-zip.sh"] {
            let script = try text(at: name)
            XCTAssertTrue(script.contains("plutil -extract CFBundleShortVersionString"),
                          "\(name) should read the version back out of the built app")
            XCTAssertTrue(script.contains("BUNDLE_VERSION") && script.contains("VERSION"),
                          "\(name) should compare the two rather than trusting its argument")
        }
    }

    /// Both packaging paths exist, and the app builder can reach them.
    func testTheAppBuilderCanProduceEachPackagingMode() throws {
        let script = try text(at: "scripts/build-app.sh")
        for mode in ["dmg", "zip"] {
            XCTAssertTrue(script.contains("\(mode))"),
                          "build-app.sh should handle the \(mode) packaging mode")
        }
        for packaging in ["scripts/build-dmg.sh", "scripts/build-zip.sh"] {
            XCTAssertNoThrow(try text(at: packaging), "\(packaging) is missing")
        }
    }
}