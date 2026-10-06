import XCTest
@testable import CodexBridgerCore

/// Seam: ProviderDraft dirty tracking for a provider that is not on disk yet.
///
/// The reference screen applies every keystroke immediately. Here the edit goes into a draft
/// and is written only on Save, so the draft must know whether the provider it represents
/// already exists. If it does not, there is always something to save: without this, a
/// provider created from the picker could never be saved, because nothing about it had
/// "changed" yet.
final class ProviderDraftNewProviderTests: XCTestCase {

    private func provider() -> ProviderConfiguration {
        ProviderConfiguration(
            id: "demo",
            name: "示例提供商",
            baseURL: "https://api.example.com/v1",
            credentialMode: .bearerToken,
            bearerToken: "sk-demo",
            models: [ModelConfiguration(slug: "demo-large", displayName: "Demo Large")]
        )
    }

    func testANewProviderIsUnsavedFromTheStart() {
        let draft = ProviderDraft(provider: provider(), existingIDs: ["other"], isNew: true)
        XCTAssertTrue(
            draft.isDirty,
            "a provider that is not on disk yet always has something to save"
        )
        XCTAssertTrue(draft.canSave)
    }

    func testAnExistingProviderIsCleanUntilItIsEdited() {
        let draft = ProviderDraft(provider: provider(), existingIDs: ["demo", "other"])
        XCTAssertFalse(draft.isDirty, "an untouched provider on disk has nothing to save")
    }

    func testResetOnANewProviderLeavesItUnsaved() {
        var draft = ProviderDraft(provider: provider(), existingIDs: ["other"], isNew: true)
        draft.provider.name = "改过的名字"
        draft.reset()
        XCTAssertEqual(draft.provider.name, "示例提供商", "reset restores the starting values")
        XCTAssertTrue(draft.isDirty, "but it is still not on disk, so it is still unsaved")
    }
}
