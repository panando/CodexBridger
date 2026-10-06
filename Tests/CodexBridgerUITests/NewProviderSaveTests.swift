import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: AppModel.createProvider -> saveDraft.
///
/// Creating a provider from the picker and then not being able to save it is the worst
/// failure this screen can have: the work looks done, the sidebar lists it, and the file
/// never changes. So creating one must immediately count as unsaved work.
@MainActor
final class NewProviderSaveTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("new-provider-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    func testAProviderCreatedFromThePickerCanBeSaved() throws {
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first, "the catalogue is not empty")

        model.createProvider(from: preset)

        XCTAssertEqual(model.configuration.providers.count, 1)
        XCTAssertTrue(
            model.hasUnsavedEdits,
            "a provider that is not on disk yet must be offered as savable"
        )

        // The credential is empty until the person pastes their key.
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft(), "saving must succeed once the form is valid")
        XCTAssertFalse(model.hasUnsavedEdits)

        let reloaded = AppModel(paths: paths)
        reloaded.load()
        XCTAssertEqual(reloaded.configuration.providers.count, 1, "it must be on disk now")
        XCTAssertEqual(reloaded.configuration.providers.first?.id, preset.id)
    }

    func testDiscardingANewProviderRemovesItFromTheList() throws {
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        model.createProvider(from: preset)

        model.resetDraft()

        XCTAssertTrue(model.configuration.providers.isEmpty, "an unsaved new provider is discarded")
        XCTAssertNil(model.draft)
    }

    func testDiscardingAnEditedExistingProviderKeepsIt() throws {
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        let model = AppModel(paths: paths)
        model.load()
        model.createProvider(from: preset)
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft())

        model.draft?.provider.name = "改过的名字"
        XCTAssertTrue(model.hasUnsavedEdits)
        model.resetDraft()

        XCTAssertEqual(model.configuration.providers.count, 1, "reset must not delete saved work")
        XCTAssertNotEqual(model.draft?.provider.name, "改过的名字")
    }
}
