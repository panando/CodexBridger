import XCTest
@testable import CodexBridgerCore

/// Seam: the product the interface talks about.
///
/// The Codex application was renamed ChatGPT, so every reference to it in the interface has to
/// say ChatGPT. The distinction that makes this worth a test is that "Codex" also appears as
/// things that must NOT change: the app's own name CodexBridger, the `CODEX_HOME` variable, the
/// `~/.codex` directory, and type names like `CodexPaths`. A careless find-and-replace over the
/// sources would break the app, so the rule is pinned by scanning the sources for the cases that
/// matter and asserting the allowed ones are still intact.
final class ProductNamingTests: XCTestCase {

    private func uiSources() throws -> [(name: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var result: [(String, String)] = []
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        for case let url as URL in walker ?? FileManager.DirectoryEnumerator() where url.pathExtension == "swift" {
            result.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        XCTAssertFalse(result.isEmpty, "the sources must be found, not silently skipped")
        return result
    }

    /// Literal text that reaches the screen, from the quoted literals only.
    ///
    /// Scanning whole lines was too blunt the first time: it flagged `refreshCodexState()` and the
    /// path of the CLI binary, neither of which is text a user reads. Only the contents of a
    /// quoted literal can be displayed, so only those are judged.
    private func displayLiterals(in text: String) -> [String] {
        var found: [String] = []
        var current = ""
        var inLiteral = false
        var escaped = false
        for character in text {
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\" && inLiteral { escaped = true; current.append(character); continue }
            if character == "\"" {
                if inLiteral { found.append(current); current = "" }
                inLiteral.toggle()
                continue
            }
            if inLiteral { current.append(character) }
        }
        return found
    }

    /// A literal is a reference to the product if it mentions Codex as a word, rather than as part
    /// of a path, an environment variable, the application name, or the model's own instructions.
    private func isProductReference(_ literal: String) -> Bool {
        guard literal.contains("Codex") else { return false }
        if literal.contains("CodexBridger") { return false }
        if literal.contains("CODEX") { return false }
        if literal.contains("/") { return false }
        // The base instruction is configuration payload written for the model, not interface text.
        if literal.hasPrefix("You are Codex") { return false }
        return true
    }

    /// The rule itself: a user-facing string must not call the product Codex.
    func testNoUserFacingStringStillSaysCodex() throws {
        var offenders: [String] = []
        for (name, text) in try uiSources() {
            for literal in displayLiterals(in: text) where isProductReference(literal) {
                offenders.append(name + ": " + literal)
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "these display strings still say Codex:\n" + offenders.joined(separator: "\n"))
    }

    /// The renames that must survive, so a test can never "fix" them by accident.
    func testTheProductIsCalledChatGPTInGeneratedWarnings() {
        let message = ActivationGuard.baseURLWarnings("http://127.0.0.1:8317/v1").joined()
        XCTAssertTrue(message.contains("ChatGPT"), "the loopback warning names the product: \(message)")
        XCTAssertFalse(message.contains(" Codex "), "and it no longer says Codex: \(message)")
    }

    /// The app name is deliberately not renamed by this change.
    func testTheApplicationNameIsUnchanged() {
        XCTAssertFalse(Localization.text("CodexBridger", language: .english).isEmpty)
        XCTAssertEqual(Localization.text("CodexBridger", language: .english), "CodexBridger")
    }
}