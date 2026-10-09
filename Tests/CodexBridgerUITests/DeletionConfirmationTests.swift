import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: deleting asks first, and the click alone does not delete anything.
///
/// Reported from the running app (2026-10-09): 删除按钮没有确认机制. The released 1.2.0 had no
/// prompt at all — the sidebar's 删除 button and the provider row's context menu both called
/// `deleteProvider` straight away, so one slip of the mouse lost the provider and its models with
/// nothing to undo it. The prompt now lives in `AppModel.pendingDeletion` and `ContentView` draws
/// it; these tests hold both halves, because the earlier activation prompt was produced and never
/// drawn, and that failure looked exactly like a dead button.
@MainActor
final class DeletionConfirmationTests: XCTestCase {

    private var home: URL!
    private var paths: CodexPaths { CodexPaths(codexHome: home) }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("delete-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    private func readyModel() throws -> AppModel {
        let model = AppModel(paths: paths)
        model.load()
        let preset = try XCTUnwrap(ProviderPreset.builtIn.first)
        model.createProvider(from: preset)
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft())
        return model
    }

    private func providerCount(_ model: AppModel) -> Int { model.configuration.providers.count }

    private func storedConfig() throws -> String {
        try String(contentsOf: paths.appConfiguration, encoding: .utf8)
    }

    // MARK: - The click alone deletes nothing

    /// The reported defect. Asking must be a question, not a formality: the provider is still
    /// there until the user agrees, in memory and on disk.
    func testAskingDoesNotDeleteTheProvider() throws {
        let model = try readyModel()
        let provider = try XCTUnwrap(model.draft?.provider)
        let before = try storedConfig()

        model.requestDeleteProvider(provider.id)

        XCTAssertEqual(providerCount(model), 1, "asking must not remove the provider")
        XCTAssertNotNil(model.pendingDeletion, "the prompt has to be waiting for an answer")
        XCTAssertEqual(try storedConfig(), before, "asking must not write the settings file")
    }

    func testAgreeingDeletesIt() throws {
        let model = try readyModel()
        let provider = try XCTUnwrap(model.draft?.provider)
        model.requestDeleteProvider(provider.id)

        model.confirmPendingDeletion()

        XCTAssertTrue(model.configuration.providers.isEmpty, "agreeing has to delete it")
        XCTAssertNil(model.pendingDeletion, "the prompt must not stay up and fire again")
    }

    func testDecliningKeepsIt() throws {
        let model = try readyModel()
        let provider = try XCTUnwrap(model.draft?.provider)
        let before = try storedConfig()
        model.requestDeleteProvider(provider.id)

        model.cancelPendingDeletion()

        XCTAssertEqual(providerCount(model), 1, "declining has to keep the provider")
        XCTAssertNil(model.pendingDeletion)
        XCTAssertEqual(try storedConfig(), before)
    }

    /// Dismissing the alert (Escape, clicking away) goes through the same binding, and SwiftUI
    /// reports that as `false`. It must count as declining, not as agreeing. Calling
    /// `cancelPendingDeletion` here would only restate the model, so the view's binding is read
    /// instead: it is the only place that sees a dismissal.
    func testDismissingThePromptCountsAsDeclining() throws {
        let source = try String(
            contentsOf: Snapshot.packageRoot
                .appendingPathComponent("Sources/CodexBridgerUI/ContentView.swift"),
            encoding: .utf8
        )
        let squeezed = source.replacingOccurrences(of: " ", with: "")
        XCTAssertTrue(
            squeezed.contains("get:{model.pendingDeletion!=nil}"),
            "the prompt is bound to the value that asks for it"
        )
        XCTAssertTrue(
            squeezed.contains("set:{if!$0{model.cancelPendingDeletion()}}"),
            "a dismissal arrives as false, and it has to decline the delete"
        )
    }

    /// Deleting the provider being edited has to take its form off screen with it.
    ///
    /// The window reloads the draft when the selection changes, so the running app got this right
    /// by accident; the model itself kept pointing at a provider that no longer existed. These two
    /// tests pin the model, where the invariant belongs.
    func testDeletingTheProviderBeingEditedDropsItsDraft() throws {
        let model = try readyModel()
        let second = try XCTUnwrap(ProviderPreset.builtIn.dropFirst().first)
        model.createProvider(from: second)
        model.draft?.provider.bearerToken = "sk-test"
        XCTAssertTrue(model.saveDraft(), "a second provider is the fixture for this test")
        XCTAssertGreaterThanOrEqual(model.configuration.providers.count, 2,
                                    "the fixture needs something left over")
        let victim = try XCTUnwrap(model.configuration.providers.first)
        model.beginEditing(providerID: victim.id)
        XCTAssertEqual(model.draft?.original.id, victim.id, "the fixture edits that provider")

        model.requestDeleteProvider(victim.id)
        model.confirmPendingDeletion()

        XCTAssertNotEqual(
            model.draft?.original.id, victim.id,
            "the editor must not keep a provider that was deleted"
        )
        XCTAssertEqual(
            model.draft?.original.id, model.selectedProviderID,
            "and it should be editing whatever the selection moved to"
        )
    }

    /// Deleting the last provider leaves nothing to edit, so the pane has to fall back to the
    /// empty state rather than a form for a provider that is gone.
    func testDeletingTheLastProviderLeavesNoDraft() throws {
        let model = try readyModel()
        let only = try XCTUnwrap(model.draft?.provider)

        model.requestDeleteProvider(only.id)
        model.confirmPendingDeletion()

        XCTAssertNil(model.selectedProviderID)
        XCTAssertNil(model.draft, "no provider is left, so there is nothing to edit")
    }

    // MARK: - What the prompt says

    func testThePromptNamesTheProviderAndItsModels() throws {
        let model = try readyModel()
        let provider = try XCTUnwrap(model.draft?.provider)
        model.addModel(to: provider.id)
        model.addModel(to: provider.id)
        let reloaded = try XCTUnwrap(model.configuration.provider(id: provider.id))
        let count = reloaded.models.count
        XCTAssertGreaterThanOrEqual(count, 3, "the fixture has to have several models")

        model.requestDeleteProvider(provider.id)

        let pending = try XCTUnwrap(model.pendingDeletion)
        XCTAssertTrue(
            pending.message.contains(reloaded.name),
            "the prompt names what is going away: " + pending.message
        )
        XCTAssertTrue(
            pending.message.contains(String(count) + " 个模型"),
            "and how much goes with it: " + pending.message
        )
        XCTAssertFalse(pending.message.contains("{count}"), "placeholders must be filled in")
        XCTAssertFalse(pending.title.isEmpty)
        XCTAssertFalse(pending.confirmTitle.isEmpty)
    }

    /// The count is a phrase, and English needs the singular.
    func testTheModelCountHasASingularForm() throws {
        let model = try readyModel()
        // A preset brings more than one model, so the singular case is built by removing one
        // from the draft and saving — the fixture has to actually hold one model.
        while (model.draft?.provider.models.count ?? 0) > 1 {
            let extra = try XCTUnwrap(model.draft?.provider.models.last)
            model.requestRemoveModelFromDraft(extra.id)
            model.confirmPendingDeletion()
        }
        XCTAssertTrue(model.saveDraft())
        let provider = try XCTUnwrap(model.configuration.providers.first)
        XCTAssertEqual(provider.models.count, 1, "the fixture has to hold exactly one model")

        model.requestDeleteProvider(provider.id)

        let pending = try XCTUnwrap(model.pendingDeletion)
        XCTAssertTrue(pending.message.contains("1 个模型"), pending.message)
        XCTAssertEqual(model.t("1 个模型"), "1 个模型", "Chinese is the source language")
        XCTAssertEqual(Localization.text("1 个模型", language: .english), "1 model")
        XCTAssertEqual(Localization.text(" 个模型", language: .english), " models")
    }

    /// Deleting the provider ChatGPT is switched to leaves the disk and the app disagreeing, and
    /// the prompt has to say so rather than let the in-use mark vanish unexplained.
    func testDeletingTheProviderInUseSaysTheFilesAreNotRewritten() throws {
        let model = try readyModel()
        let provider = try XCTUnwrap(model.draft?.provider)
        let target = try XCTUnwrap(provider.models.first)
        model.activate(providerID: provider.id, modelID: target.id)
        let deadline = Date().addingTimeInterval(20)
        while model.isActivating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(model.configuration.activeProviderID, provider.id, "fixture must be active")
        let configBefore = try String(contentsOf: paths.configTOML, encoding: .utf8)

        model.requestDeleteProvider(provider.id)
        let activePrompt = try XCTUnwrap(model.pendingDeletion)
        XCTAssertTrue(
            activePrompt.message.contains("配置文件"),
            "the prompt explains the files are not rewritten: " + activePrompt.message
        )

        // Agreeing still must not rewrite anything ChatGPT reads.
        model.confirmPendingDeletion()
        XCTAssertEqual(
            try String(contentsOf: paths.configTOML, encoding: .utf8), configBefore,
            "deleting a provider is this app's own bookkeeping, not a write to ChatGPT"
        )
    }

    /// A provider that is not in use gets the plain prompt: no talk of files being rewritten.
    func testTheOrdinaryPromptDoesNotMentionInUseFiles() throws {
        let model = try readyModel()
        let provider = try XCTUnwrap(model.draft?.provider)
        XCTAssertNil(model.configuration.activeProviderID, "nothing is activated in this fixture")

        model.requestDeleteProvider(provider.id)

        let pending = try XCTUnwrap(model.pendingDeletion)
        XCTAssertFalse(
            pending.message.contains("配置文件"),
            "an unused provider does not need that caveat: " + pending.message
        )
        XCTAssertTrue(pending.message.contains("config.toml"), "but it says what is not touched")
    }

    // MARK: - Removing a model from the draft

    /// A model removal is an unsaved edit, so the prompt says so and the stored provider keeps
    /// the model until the draft is saved.
    func testRemovingAModelAsksAndOnlyEditsTheDraft() throws {
        let model = try readyModel()
        let provider = try XCTUnwrap(model.draft?.provider)
        let entry = try XCTUnwrap(provider.models.first)
        let providerID = provider.id

        let before = try XCTUnwrap(provider.models.count)
        let storedBefore = try XCTUnwrap(model.configuration.provider(id: providerID)?.models.count)

        model.requestRemoveModelFromDraft(entry.id)
        let pending = try XCTUnwrap(model.pendingDeletion)
        XCTAssertEqual(pending.target, .model(id: entry.id))
        XCTAssertEqual(
            model.draft?.provider.models.count, before,
            "asking must not remove the model from the draft either"
        )

        model.confirmPendingDeletion()

        XCTAssertEqual(
            model.draft?.provider.models.count, before - 1,
            "agreeing removes it from the draft"
        )
        XCTAssertEqual(
            model.configuration.provider(id: providerID)?.models.count, storedBefore,
            "and the saved provider keeps it until the draft is saved"
        )
    }

    /// Asking for a model that is not in the draft must not put up a prompt for nothing.
    func testAskingAboutAnUnknownModelPutsUpNoPrompt() throws {
        let model = try readyModel()

        model.requestRemoveModelFromDraft(UUID())

        XCTAssertNil(model.pendingDeletion)
    }

    /// Every entry point goes through the request. A view that calls the raw delete, or the raw
    /// draft removal, is how the click came to delete without asking in the first place.
    func testNoViewDeletesWithoutAsking() throws {
        let root = Snapshot.packageRoot
        let sidebar = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexBridgerUI/ContentView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            sidebar.contains("model.deleteProvider("),
            "the sidebar must ask, not delete: `model.deleteProvider(` is a raw delete"
        )
        XCTAssertTrue(
            sidebar.contains("model.requestDeleteProvider("),
            "both the button and the row menu have to go through the request"
        )
        XCTAssertEqual(
            sidebar.components(separatedBy: "model.requestDeleteProvider(").count - 1, 2,
            "two entry points only (the 删除 button and the context menu); a third has to be "
            + "confirmed too"
        )

        let form = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexBridgerUI/ProviderFormBody.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            form.contains(".removeModelFromDraft("),
            "the model menu must ask first"
        )
        XCTAssertTrue(form.contains("model.requestRemoveModelFromDraft("))
    }

    /// The other half: a view has to draw the prompt, or the state is produced and never shown.
    func testAViewDrawsThePromptAndOffersBothAnswers() throws {
        let source = try String(
            contentsOf: Snapshot.packageRoot
                .appendingPathComponent("Sources/CodexBridgerUI/ContentView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("model.pendingDeletion"), "nothing draws the prompt")
        XCTAssertTrue(
            source.contains("model.confirmPendingDeletion()"),
            "the prompt must be able to go ahead"
        )
        XCTAssertTrue(
            source.contains("model.cancelPendingDeletion()"),
            "and the user must be able to say no"
        )
        XCTAssertTrue(
            source.contains("role: .destructive"),
            "deleting is destructive and the button should say so"
        )
    }

    /// The raw deletes stay reachable from the confirmation only.
    ///
    /// The provider one is `private`, so this is enforced by the compiler and not by reading the
    /// source: rewiring a view to delete directly no longer builds. The scan stays as the record
    /// of why, and to catch a `public` slipping back in.
    func testTheRawDeleteHasExactlyOneCaller() throws {
        let root = Snapshot.packageRoot
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexBridgerUI/AppModel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("private func applyDeletion(of id: String)"),
            "the unconfirmed delete has to be private, or a view can call it again"
        )
        XCTAssertEqual(
            source.components(separatedBy: "applyDeletion(of").count - 1, 2,
            "one definition and one call — `confirmPendingDeletion`"
        )
        XCTAssertEqual(
            source.components(separatedBy: "removeModelFromDraft(id)").count - 1, 1,
            "`removeModelFromDraft(id)` belongs to `confirmPendingDeletion` and nowhere else"
        )

        let sidebar = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexBridgerUI/ContentView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(sidebar.contains("model.applyDeletion("), "views cannot delete directly")
    }

    // MARK: - The prompt is bilingual like the rest of the screen

    func testEveryPromptStringHasAnEnglishVersion() throws {
        let model = try readyModel()
        let provider = try XCTUnwrap(model.draft?.provider)
        model.requestDeleteProvider(provider.id)
        let providerPrompt = try XCTUnwrap(model.pendingDeletion)

        let entry = try XCTUnwrap(provider.models.first)
        model.requestRemoveModelFromDraft(entry.id)
        let modelPrompt = try XCTUnwrap(model.pendingDeletion)

        // The two prompts are built at runtime, so the English cannot be looked up by the built
        // string. Check the templates and the fixed titles instead.
        let keys = [
            "删除这个提供商？", "移除这个模型？", "移除",
            "1 个模型", " 个模型",
            "「{name}」下有 {count}。删除只改 CodexBridger 自己的设置，config.toml 和 auth.json 不会被动。",
            "ChatGPT 正指着它：删掉以后「使用中」的标记也没了，配置文件要等你激活别的提供商时才会改写。",
            "「{name}」会从这个提供商里移除。这是还没保存的改动，点「取消」可以让它回来，保存或更新配置之后才真正生效。",
        ]
        for key in keys {
            let english = Localization.english[key]
            XCTAssertNotNil(english, "no English for " + key)
            XCTAssertNotEqual(english, key, "the English entry must differ: " + key)
        }
        XCTAssertNotEqual(providerPrompt.title, modelPrompt.title)
        XCTAssertNotEqual(providerPrompt.confirmTitle, modelPrompt.confirmTitle)
        XCTAssertEqual(Localization.text("删除这个提供商？", language: .english), "Delete this provider?")
    }
}
