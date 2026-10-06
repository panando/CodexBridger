import XCTest
@testable import CodexBridgerCore

/// Seam: what the welcome screen promises.
///
/// The screen used to advertise local services (Ollama, llama.cpp, LM Studio) with no key. This
/// build has no presets for them and no handling specific to them — the words appeared nowhere
/// else in the sources. A feature advertised but not implemented sends the user looking for it,
/// and they conclude the app is broken rather than the copy.
final class OnboardingCopyTests: XCTestCase {

    private func onboardingSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexBridgerUI/OnboardingView.swift")
        return try String(contentsOf: root, encoding: .utf8)
    }

    /// The title and subtitles declared on the welcome screen, in order.
    private func capabilityStrings() throws -> [String] {
        let source = try onboardingSource()
        let body = try XCTUnwrap(source.components(separatedBy: "capabilities: [Capability] = [").last)
        var strings: [String] = []
        for line in body.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for key in ["title: \"", "subtitle: \""] {
                guard trimmed.hasPrefix(key) else { continue }
                // A title line ends with `",` and a subtitle with `"`, the last one before `),`.
                var value = trimmed.dropFirst(key.count)
                if value.hasSuffix("\",") { value = value.dropLast(2) }
                else if value.hasSuffix("\"") { value = value.dropLast() }
                else { continue }
                strings.append(String(value))
            }
        }
        return strings
    }

    private static let unsupported = ["Ollama", "llama.cpp", "LM Studio"]

    /// The claim that was not true.
    ///
    /// This checks the copy the user actually reads, not the raw file: a doc comment explaining
    /// *why* the claim was removed necessarily names it, and flagging that would be wrong.
    func testTheWelcomeScreenDoesNotAdvertiseLocalServices() throws {
        for string in try capabilityStrings() {
            for word in Self.unsupported {
                XCTAssertFalse(string.contains(word),
                               "the welcome screen advertises " + word
                               + ", which this build does not support")
            }
        }
    }

    /// Nor does the English copy, which is where a stale translation would hide.
    func testNoTranslationAdvertisesLocalServices() {
        for (_, english) in Localization.english {
            for word in Self.unsupported {
                XCTAssertFalse(english.contains(word),
                               "English copy advertises " + word)
            }
        }
    }
    /// The copy exists, and every line of it can be read in English.
    func testEveryCapabilityIsTranslatable() throws {
        let strings = try capabilityStrings()
        XCTAssertEqual(strings.count, 10, "five capabilities, each with a title and a subtitle")
        for source in strings {
            XCTAssertFalse(source.isEmpty)
            let english = Localization.text(source, language: .english)
            XCTAssertNotEqual(english, source,
                              "no English text for: \(source)")
        }
    }

    /// The headline is translated too.
    func testTheHeadlineIsTranslated() {
        XCTAssertEqual(
            Localization.text("CodexBridger 能做什么？", language: .english),
            "What CodexBridger does"
        )
    }

    /// The copy no longer contains the alarming claim about a failed launch.
    func testTheCopyDoesNotPromiseAFailedStart() throws {
        let source = try onboardingSource()
        XCTAssertFalse(source.contains("启动失败"),
                       "the welcome screen should describe benefits, not threaten breakage")
    }
}