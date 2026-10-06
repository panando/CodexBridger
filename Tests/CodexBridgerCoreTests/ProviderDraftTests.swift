import XCTest
@testable import CodexBridgerCore

/// Seam: ProviderDraft.
///
/// The reference screen edits a provider in place with immediate Apply. Editing a live
/// configuration that writes Codex files needs a draft: the user can type freely, see what
/// is wrong before anything is written, and back out with Reset.
final class ProviderDraftTests: XCTestCase {

    private func provider(
        id: String = "demo",
        name: String = "示例提供商",
        baseURL: String = "https://api.example.com/v1",
        mode: ProviderCredentialMode = .bearerToken,
        bearerToken: String = "sk-demo",
        requiresOpenAIAuth: Bool = false,
        models: [ModelConfiguration] = [ModelConfiguration(slug: "demo-large", displayName: "Demo Large")]
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            id: id, name: name, baseURL: baseURL, credentialMode: mode,
            requiresOpenAIAuth: requiresOpenAIAuth, bearerToken: bearerToken,
            models: models
        )
    }

    private func draft(_ provider: ProviderConfiguration) -> ProviderDraft {
        ProviderDraft(provider: provider, existingIDs: ["demo", "other"])
    }

    // MARK: - Dirty tracking

    func testFreshDraftIsCleanAndSavable() {
        let draft = draft(provider())
        XCTAssertFalse(draft.isDirty)
        XCTAssertTrue(draft.errors.isEmpty)
        XCTAssertTrue(draft.canSave)
    }

    func testEditingAFieldMarksTheDraftDirty() {
        var draft = draft(provider())
        draft.provider.name = "改过的名字"
        XCTAssertTrue(draft.isDirty)
    }

    func testChangingBackToTheOriginalValueIsNotDirty() {
        var draft = draft(provider())
        draft.provider.name = "临时"
        draft.provider.name = "示例提供商"
        XCTAssertFalse(draft.isDirty, "dirty must compare values, not count edits")
    }

    func testResetRestoresTheOriginalAndClearsDirty() {
        // Compare against the same instance: ModelConfiguration carries a fresh UUID, so two
        // separately built providers are never equal.
        let original = provider()
        var draft = ProviderDraft(provider: original, existingIDs: ["demo", "other"])
        draft.provider.id = "changed"
        draft.provider.baseURL = "https://other.example.com"
        draft.provider.models = []
        draft.reset()
        XCTAssertEqual(draft.provider, original)
        XCTAssertEqual(draft.provider.models.map(\.slug), ["demo-large"])
        XCTAssertFalse(draft.isDirty)
    }

    // MARK: - Validation: identifier

    func testEmptyIdentifierIsAnError() {
        var draft = draft(provider())
        draft.provider.id = ""
        XCTAssertTrue(draft.errors.contains { $0.field == .identifier })
        XCTAssertFalse(draft.canSave)
    }

    func testIdentifierWithADotIsRejectedBecauseCodexKeysCannotCarryIt() {
        var draft = draft(provider())
        draft.provider.id = "has.dot"
        XCTAssertTrue(draft.errors.contains { $0.field == .identifier })
    }

    func testIdentifierCollidingWithAnotherProviderIsAnError() {
        var draft = draft(provider())
        draft.provider.id = "other"
        XCTAssertTrue(
            draft.errors.contains { $0.field == .identifier },
            "two providers cannot share one [model_providers.<id>] table"
        )
    }

    func testIdentifierMayEqualItsOwnOriginalValue() {
        let draft = draft(provider())
        XCTAssertFalse(
            draft.errors.contains { $0.field == .identifier },
            "a provider keeping its own id is not a collision"
        )
    }

    func testInvalidIdentifierAlsoProducesAFieldLevelMessage() {
        var draft = draft(provider())
        draft.provider.id = "有空格 的"
        let issue = try? XCTUnwrap(draft.issue(for: .identifier))
        XCTAssertNotNil(issue, "the row shows the message inline, so it must be reachable per field")
    }

    // MARK: - Validation: name and base URL

    func testBlankNameIsAnError() {
        var draft = draft(provider())
        draft.provider.name = "   "
        XCTAssertTrue(draft.errors.contains { $0.field == .name })
    }

    func testBlankBaseURLIsAnError() {
        var draft = draft(provider())
        draft.provider.baseURL = ""
        XCTAssertTrue(draft.errors.contains { $0.field == .baseURL })
    }

    func testBaseURLWithoutASchemeIsAnError() {
        var draft = draft(provider())
        draft.provider.baseURL = "api.example.com/v1"
        XCTAssertTrue(draft.errors.contains { $0.field == .baseURL })
    }

    func testLoopbackBaseURLIsAWarningNotAnError() {
        var draft = draft(provider())
        draft.provider.baseURL = "http://127.0.0.1:8000/v1"
        XCTAssertTrue(draft.errors.isEmpty, "a local server is legitimate")
        XCTAssertTrue(draft.warnings.contains { $0.field == .baseURL })
        XCTAssertTrue(draft.canSave)
    }

    // MARK: - Validation: credentials

    func testBearerModeRequiresAToken() {
        var draft = draft(provider(bearerToken: ""))
        draft.provider.credentialMode = .bearerToken
        XCTAssertTrue(draft.errors.contains { $0.field == .credential })
    }

    func testEnvironmentModeRequiresAVariableName() {
        var draft = draft(provider(mode: .environmentKey))
        XCTAssertTrue(draft.errors.contains { $0.field == .credential })
        var fixed = draft
        fixed.provider.environmentKeyName = "MY_KEY"
        XCTAssertTrue(fixed.errors.isEmpty)
    }

    func testCommandModeRequiresACommand() {
        var draft = draft(provider(mode: .command))
        XCTAssertTrue(draft.errors.contains { $0.field == .credential })
    }

    func testCommandAuthPlusOpenAIAuthIsAnErrorNotTwoSeparateFields() {
        var draft = draft(provider(mode: .command))
        draft.provider.commandAuth.command = "print-token"
        draft.provider.requiresOpenAIAuth = true
        let issue = draft.issue(for: .credential)
        XCTAssertNotNil(issue, "the official reference forbids combining .auth with requires_openai_auth")
        XCTAssertTrue(issue?.message.contains("requires_openai_auth") ?? false)
    }

    func testSwitchingToNoCredentialClearsTheBearerTokenError() {
        var draft = draft(provider(bearerToken: ""))
        XCTAssertTrue(draft.errors.contains { $0.field == .credential })
        draft.provider.credentialMode = .none
        XCTAssertTrue(draft.errors.isEmpty)
    }

    // MARK: - Validation: models

    func testProviderWithoutModelsCanBeSavedButWarns() {
        var draft = draft(provider(models: []))
        draft.provider.models = []
        XCTAssertTrue(draft.errors.isEmpty, "saving a provider first and adding models next is fine")
        XCTAssertTrue(draft.warnings.contains { $0.field == .models })
    }

    func testDuplicateModelSlugsAreAnError() {
        var draft = draft(provider())
        draft.provider.models = [
            ModelConfiguration(slug: "same", displayName: "A"),
            ModelConfiguration(slug: "same", displayName: "B")
        ]
        XCTAssertTrue(draft.errors.contains { $0.field == .models })
    }

    func testBlankModelSlugIsAnError() {
        var draft = draft(provider())
        draft.provider.models = [ModelConfiguration(slug: "  ", displayName: "A")]
        XCTAssertTrue(draft.errors.contains { $0.field == .models })
    }

    func testContextWindowBelowTheFloorIsAnError() {
        var draft = draft(provider())
        draft.provider.models = [
            ModelConfiguration(slug: "m", displayName: "M", contextWindow: 100, maxContextWindow: 100)
        ]
        XCTAssertTrue(draft.errors.contains { $0.field == .models })
    }

    func testMaxContextWindowSmallerThanContextWindowIsAnError() {
        var draft = draft(provider())
        draft.provider.models = [
            ModelConfiguration(slug: "m", displayName: "M", contextWindow: 200_000, maxContextWindow: 64_000)
        ]
        let issue = draft.issue(for: .models)
        XCTAssertNotNil(issue)
        XCTAssertTrue(issue?.subject == "m", "the message must name the offending model")
    }

    func testDefaultReasoningEffortOutsideTheSupportedSetIsAnError() {
        var draft = draft(provider())
        draft.provider.models = [
            ModelConfiguration(
                slug: "m", displayName: "M",
                supportedReasoningEfforts: [.low],
                defaultReasoningEffort: .ultra
            )
        ]
        XCTAssertTrue(draft.errors.contains { $0.field == .models })
    }

    // MARK: - Commit

    func testCommitRefusesWhileErrorsRemain() {
        var draft = draft(provider())
        draft.provider.id = ""
        XCTAssertThrowsError(try draft.commit()) { error in
            let failure = error as? ValidationFailure
            XCTAssertNotNil(failure)
            XCTAssertFalse(failure?.issues.isEmpty ?? true)
        }
    }

    func testCommitTrimsSurroundingWhitespace() throws {
        var draft = draft(provider())
        draft.provider.name = "  示例  "
        draft.provider.id = "  demo  "
        let committed = try draft.commit()
        XCTAssertEqual(committed.name, "示例")
        XCTAssertEqual(committed.id, "demo")
    }

    func testCommitRepairsMaxContextWindowInsteadOfFailing() throws {
        var draft = draft(provider())
        draft.provider.models = [
            ModelConfiguration(slug: "m", displayName: "M", contextWindow: 200_000, maxContextWindow: 64_000)
        ]
        XCTAssertThrowsError(try draft.commit())
        var repaired = draft
        repaired.provider.models[0].maxContextWindow = 200_000
        let committed = try repaired.commit()
        XCTAssertEqual(committed.models[0].maxContextWindow, 200_000)
    }

    // MARK: - Submit gate

    func testSubmitGateAllowsOnlyOneInFlightSubmission() {
        var gate = SubmitGate()
        XCTAssertTrue(gate.begin(), "first submit is allowed")
        XCTAssertFalse(gate.begin(), "a second click while saving must be ignored")
        gate.end()
        XCTAssertTrue(gate.begin(), "after completion a new submit is allowed")
    }

    func testSubmitGateResetClearsAStuckSubmission() {
        var gate = SubmitGate()
        _ = gate.begin()
        gate.reset()
        XCTAssertTrue(gate.begin())
    }
}
