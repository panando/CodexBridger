import XCTest
@testable import CodexBridgerCore

/// Seam: `GlobalSettingsDraft` decides what actually has to change on disk.
///
/// Its whole job is to answer "is there anything to write, and what exactly" — so the tests
/// are all about the difference between what the file holds and what the user has chosen.
///
/// After the 2026-10-08 ruling the screen draws six keys in two groups, so these fixtures use
/// only those. The keys that left behave like any other key the screen does not know: the draft
/// refuses them, which is what keeps the point of the page honest.
final class GlobalSettingsDraftTests: XCTestCase {

    /// Three of the six shown keys set, a third absent, and one key that is not on the screen.
    static let file = """
    approval_policy = "on-request"
    sandbox_mode = 'workspace-write'
    allow_login_shell = true
    personality = 'pragmatic'
    """

    private func draft() -> GlobalSettingsDraft {
        GlobalSettingsDraft(loaded: GlobalSettingsReader.states(in: Self.file))
    }

    func testAFreshDraftHasNothingToWrite() {
        let draft = draft()
        XCTAssertFalse(draft.isDirty)
        XCTAssertTrue(draft.changes.isEmpty)
    }

    func testChangingAKeyRecordsTheWrite() {
        var draft = draft()
        draft.set(.choice("never"), for: "approval_policy")
        XCTAssertTrue(draft.isDirty)
        XCTAssertEqual(draft.changes, ["approval_policy": .write(.choice("never"))])
    }

    func testChangingAKeyBackToTheValueTheFileAlreadyHasLeavesNothingToWrite() {
        var draft = draft()
        draft.set(.choice("never"), for: "approval_policy")
        draft.set(.choice("on-request"), for: "approval_policy")
        XCTAssertFalse(draft.isDirty, "a value equal to the file's own value is not a change")
        XCTAssertTrue(draft.changes.isEmpty)
    }

    func testChangingAKeyBackToTheFileValueLeavesTheOtherChangesAlone() {
        var draft = draft()
        draft.set(.choice("never"), for: "approval_policy")
        draft.set(.flag(false), for: "allow_login_shell")
        draft.set(.choice("on-request"), for: "approval_policy")
        XCTAssertEqual(draft.changes, ["allow_login_shell": .write(.flag(false))])
    }

    func testClearingAKeyRecordsARemoval() {
        var draft = draft()
        draft.clear("sandbox_mode")
        XCTAssertEqual(draft.changes, ["sandbox_mode": .remove])
    }

    func testClearingAKeyTheFileDoesNotHaveChangesNothing() {
        var draft = draft()
        draft.clear("show_raw_agent_reasoning")
        XCTAssertFalse(draft.isDirty)
    }

    func testSettingAKeyTheFileDoesNotHaveRecordsAWrite() {
        var draft = draft()
        draft.set(.flag(true), for: "show_raw_agent_reasoning")
        XCTAssertEqual(draft.changes, ["show_raw_agent_reasoning": .write(.flag(true))])
    }

    func testClearingAKeyThenSettingItBackLeavesNothingToWrite() {
        var draft = draft()
        draft.clear("sandbox_mode")
        draft.set(.choice("workspace-write"), for: "sandbox_mode")
        XCTAssertFalse(draft.isDirty)
    }

    func testResetLeavesNothingToWrite() {
        var draft = draft()
        draft.set(.choice("never"), for: "approval_policy")
        draft.clear("sandbox_mode")
        draft.reset()
        XCTAssertFalse(draft.isDirty)
        XCTAssertTrue(draft.changes.isEmpty)
    }

    /// The conflict prompt offers "drop these keys, write the rest", so the draft has to be
    /// able to forget a chosen subset while keeping everything else pending.
    func testDiscardingChosenKeysKeepsTheOtherPendingChanges() {
        var draft = draft()
        draft.set(.choice("never"), for: "approval_policy")
        draft.set(.flag(false), for: "allow_login_shell")
        draft.set(.flag(true), for: "show_raw_agent_reasoning")

        draft.discardChanges(for: ["approval_policy", "show_raw_agent_reasoning"])

        XCTAssertEqual(draft.changes, ["allow_login_shell": .write(.flag(false))])
    }

    func testDiscardingAKeyThatHasNoPendingChangeIsHarmless() {
        var draft = draft()
        draft.discardChanges(for: ["show_raw_agent_reasoning", "not_a_key"])
        XCTAssertFalse(draft.isDirty)
    }

    /// Ruling A, 2026-10-08: the context window is set per model on the provider screen, so this
    /// screen must refuse the global key. Pinned so re-adding it to the catalog fails loudly
    /// instead of quietly creating a second place to set one thing.
    func testAKeyRuledOutOfThisScreenCannotBeChangedHere() {
        var draft = GlobalSettingsDraft(loaded: GlobalSettingsReader.states(
            in: "model_context_window = 100000"
        ))
        draft.set(.number(200_000), for: "model_context_window")
        XCTAssertFalse(draft.isDirty, "a key ruled off this screen must not become settable")
        draft.clear("model_context_window")
        XCTAssertFalse(draft.isDirty)
    }

    /// The second ruling, same day: the screen draws six keys in two groups and nothing else.
    /// Every other key in config.toml must stay out of reach, whatever its type.
    func testAKeyThatLeftTheScreenCannotBeChangedHere() {
        var draft = draft()
        for key in ["chatgpt_base_url", "personality", "web_search", "notify"] {
            draft.set(.text("https://elsewhere.example"), for: key)
            draft.clear(key)
        }
        XCTAssertFalse(draft.isDirty, "a key off the screen must not become settable")
    }

    func testKeysTheFileDoesNotOfferForEditingCannotBeChangedHere() {
        var draft = GlobalSettingsDraft(loaded: GlobalSettingsReader.states(
            in: "approval_policy = { granular = { sandbox_approval = true } }"
        ))
        draft.set(.choice("never"), for: "approval_policy")
        draft.clear("approval_policy")
        XCTAssertFalse(draft.isDirty, "an advanced form must never be overwritten from this screen")
    }

    func testTheDraftRemembersTheRawTextItLoadedSoAConflictCanBeDetected() {
        let draft = draft()
        XCTAssertEqual(draft.loadedRawValue(for: "approval_policy"), "\"on-request\"")
        XCTAssertEqual(draft.loadedRawValue(for: "sandbox_mode"), "'workspace-write'")
        XCTAssertEqual(draft.loadedRawValue(for: "allow_login_shell"), "true")
        XCTAssertNil(draft.loadedRawValue(for: "show_raw_agent_reasoning"))
    }

    func testChangedKeysComeBackInAStableOrder() {
        var draft = draft()
        draft.set(.flag(true), for: "show_raw_agent_reasoning")
        draft.set(.choice("never"), for: "approval_policy")
        // Catalog order, so the writer's output does not depend on the order keys were touched.
        XCTAssertEqual(draft.changedKeys, ["approval_policy", "show_raw_agent_reasoning"])
    }
}
