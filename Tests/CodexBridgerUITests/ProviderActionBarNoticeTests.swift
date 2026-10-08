import XCTest
import SwiftUI
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: what the provider screen's action bar says after an action.

/// The artefact writes the bar itself: the scrolling form above it comes out blank under
/// `ImageRenderer` (a `ScrollView` has no viewport to lay its content into headlessly), so this is
/// a picture of the messages, not of the screen. It exists because the reported bug was a message
/// that never reached the screen, and a picture of the bar is the cheapest way to see the three
/// channels — this app's save, the model parameter file, and the activation — side by side.
@MainActor
final class ProviderActionBarNoticeTests: XCTestCase {
    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("action-bar-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    /// An activation leaves its result on the bar, and a skipped backup rides along as a note on
    /// a success rather than as the red failure it used to be drawn as.
    func testTheBarShowsTheActivationResultAfterAnActivation() throws {
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        model.createProvider(from: preset)
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft())
        let first = try XCTUnwrap(model.draft?.provider)
        model.activate(providerID: first.id, modelID: try XCTUnwrap(first.models.first).id)
        waitForActivationToEnd(model)

        // A second provider, so the artifact shows the message for a normal switch.
        let other = try XCTUnwrap(ProviderPreset.builtIn.dropFirst().first)
        model.createProvider(from: other)
        model.draft?.provider.bearerToken = "sk-second"
        XCTAssertTrue(model.saveDraft())
        let provider = try XCTUnwrap(model.draft?.provider)
        model.activate(providerID: provider.id, modelID: try XCTUnwrap(provider.models.first).id)
        waitForActivationToEnd(model)

        XCTAssertEqual(model.status.kind, .success, model.status.message)

        let saved = try XCTUnwrap(model.draft)
        // The bar is one line high and the frame cannot grow, so the message has to be one line at
        // the width it is given there. The backup note was pasted into this message once and
        // wrapped it onto three lines; this is the guard for that.
        let oneLine = try XCTUnwrap(
            Snapshot.size(StatusBanner(kind: .success, message: "已激活"), width: 520),
            "the banner must render"
        )
        let slug = try XCTUnwrap(provider.models.first).slug
        let message = "已激活 " + provider.name + " · " + slug
        let measured = try XCTUnwrap(
            Snapshot.size(StatusBanner(kind: .success, message: message), width: 520),
            "the banner must render"
        )
        XCTAssertEqual(
            measured.height, oneLine.height,
            "the message must stay on one line, got \(measured.height)pt for " + message
        )
        // Non-vacuity: the measurement has to be able to see a wrapped message, or the
        // assertion above would pass for any text at all.
        let wrapped = try XCTUnwrap(
            Snapshot.size(
                StatusBanner(kind: .success, message: message + "（已跳过备份：当前配置由本软件生成，可随时重新生成。）"),
                width: 520
            ),
            "the banner must render"
        )
        XCTAssertGreaterThan(
            wrapped.height, oneLine.height,
            "a message with the backup note appended must be seen as taller"
        )
        model.status = .success(message)
        let size = try Snapshot.writeArtifact(
            ProviderConfigView(model: model, draft: .constant(saved)),
            named: "provider-action-bar-messages", width: 820
        )
        XCTAssertGreaterThan(size.height, 200, "the bar must render")
    }

    private func waitForActivationToEnd(_ model: AppModel) {
        let deadline = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
