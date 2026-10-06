import XCTest
import SwiftUI
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: when Save is available.
///
/// Reported by the user: the Save button was live on an untouched provider and greyed out as
/// soon as something was actually changed — exactly backwards. The condition had been written
/// as `!draft.isDirty`, so "nothing to save" is what enabled it.
///
/// This is a one-character bug that 220 green tests did not catch, because nothing asserted
/// the button's availability at all. Both states are asserted here so it cannot come back.
@MainActor
final class SaveButtonStateTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("savebtn-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    /// Saves the provider, then reopens it in a fresh session so the draft is untouched.
    private func reopenedProvider() throws -> (AppModel, ProviderConfigView) {
        let writer = AppModel(paths: paths)
        writer.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        writer.createProvider(from: preset)
        writer.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(writer.saveDraft())
        let id = try XCTUnwrap(writer.draft?.provider.id)

        let reopened = AppModel(paths: paths)
        reopened.load()
        reopened.beginEditing(providerID: id)
        let view = ProviderConfigView(model: reopened, draft: Binding(
            get: { reopened.draft ?? ProviderDraft(provider: writer.draft!.provider, existingIDs: [id]) },
            set: { reopened.draft = $0 }
        ))
        return (reopened, view)
    }

    func testSaveIsUnavailableWhenThereIsNothingToSave() throws {
        let (_, view) = try reopenedProvider()
        XCTAssertFalse(view.canSave,
                       "an untouched provider must not offer Save")
    }

    func testSaveBecomesAvailableOnceSomethingChanges() throws {
        let (model, view) = try reopenedProvider()
        XCTAssertFalse(view.canSave, "baseline")
        var draft = try XCTUnwrap(model.draft)
        draft.provider.name = "Changed"
        model.draft = draft
        XCTAssertTrue(model.draft?.isDirty == true, "the edit must register as unsaved")

        let updated = ProviderConfigView(model: model, draft: Binding(
            get: { model.draft ?? draft }, set: { model.draft = $0 }
        ))
        XCTAssertTrue(updated.canSave,
                      "a real change must enable Save — the inverse of the reported bug")
    }

    func testSaveStaysUnavailableWhenTheChangeIsInvalid() throws {
        let (model, _) = try reopenedProvider()
        var draft = try XCTUnwrap(model.draft)
        draft.provider.baseURL = ""
        model.draft = draft
        XCTAssertFalse(model.draft?.canSave ?? true, "an empty address is not saveable")

        let updated = ProviderConfigView(model: model, draft: Binding(
            get: { model.draft ?? draft }, set: { model.draft = $0 }
        ))
        XCTAssertFalse(updated.canSave,
                       "an invalid change must not enable Save")
    }
}