import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: the save notice is news and must clear itself.
///
/// Reported from the running app: after saving, the green "已保存 …" banner stayed at the
/// bottom of the window forever. A stale success notice is noise, not information.
@MainActor
final class SaveNoticeTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("save-notice-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    func testSuccessNoticeAppearsThenClearsItself() async throws {
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        model.createProvider(from: preset)
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft())

        XCTAssertTrue(model.editorPhase.isSuccess,
                      "saving reports success immediately")

        // The notice clears on its own without any further action.
        try await Task.sleep(nanoseconds: 4_500_000_000)
        XCTAssertFalse(
            model.editorPhase.isSuccess,
            "the success notice must not linger at the bottom of the window"
        )
    }

    func testFailureNoticeStaysUntilReplaced() async throws {
        // A failed write can be the only explanation of the problem, so it is not timed out.
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        model.createProvider(from: preset)
        // No token with a bearer-token provider: the save cannot succeed.
        XCTAssertFalse(model.saveDraft())
        XCTAssertTrue(model.editorPhase.isError, "a failed save is reported")

        try await Task.sleep(nanoseconds: 4_500_000_000)
        XCTAssertTrue(model.editorPhase.isError,
                      "a failure notice must remain readable until the next action")
    }
}
