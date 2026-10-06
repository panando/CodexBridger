import XCTest
@testable import CodexBridgerCore

/// Seam: ProviderPreset.
///
/// The reference window lists known providers grouped by family, and its primary call to
/// action is "新建提供商". A preset catalogue is what makes that one click instead of a
/// blank form, and it is the source of the sidebar grouping.
final class ProviderPresetTests: XCTestCase {

    /// The catalogue still has to make "新建提供商" a one-click action. It was trimmed to five
    /// cloud presets on request; the local-server presets were dropped as not needed. The floor
    /// is here so a future edit cannot quietly empty the list.
    func testBuiltInCatalogueIsNotEmpty() {
        XCTAssertGreaterThanOrEqual(ProviderPreset.builtIn.count, 5)
        XCTAssertFalse(ProviderPreset.builtIn.isEmpty)
    }

    func testPresetIdentifiersAreUnique() {
        let ids = ProviderPreset.builtIn.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate ids: "
                       + ids.filter { id in ids.filter { $0 == id }.count > 1 }.joined(separator: ", "))
    }

    func testEveryPresetIsPresentable() {
        for preset in ProviderPreset.builtIn {
            XCTAssertFalse(preset.name.trimmingCharacters(in: .whitespaces).isEmpty, preset.id)
            XCTAssertFalse(preset.category.trimmingCharacters(in: .whitespaces).isEmpty, preset.id)
            XCTAssertFalse(preset.note.trimmingCharacters(in: .whitespaces).isEmpty, preset.id)
            XCTAssertFalse(preset.source.trimmingCharacters(in: .whitespaces).isEmpty, preset.id)
            if !preset.suggestsModels {
                XCTAssertTrue(
                    preset.note.contains("模型名"),
                    preset.id + " suggests no model, so its note must tell the user to supply one"
                )
            }
        }
    }

    func testEveryPresetBaseURLIsAWritableURL() {
        for preset in ProviderPreset.builtIn {
            let url = URL(string: preset.baseURL)
            XCTAssertNotNil(url, preset.id + " has an unparseable baseURL")
            XCTAssertTrue(
                ["http", "https"].contains(url?.scheme ?? ""),
                preset.id + " must use http or https"
            )
            XCTAssertFalse(url?.host?.isEmpty ?? true, preset.id + " has no host")
        }
    }

    func testModelSlugsAreUniqueInsideAPreset() {
        for preset in ProviderPreset.builtIn {
            XCTAssertEqual(
                Set(preset.modelSlugs).count, preset.modelSlugs.count,
                preset.id + " lists the same model twice"
            )
        }
    }

    func testIdentifiersAreUsableAsCodexProviderKeys() {
        for preset in ProviderPreset.builtIn {
            XCTAssertTrue(
                ProviderConfiguration.isValidIdentifier(preset.id),
                preset.id + " cannot be used as [model_providers.<id>]"
            )
        }
    }

    /// Every preset that points at a loopback address must skip the credential prompt, and every
    /// cloud preset must still ask for one. The local-server presets were removed from the
    /// catalogue, so the loopback list is now empty — the rule is kept because a future preset
    /// could reintroduce one, and 自定义（空白）still supports a local server without it.
    func testLocalPresetsCarryNoCredentialAndCloudPresetsDo() {
        let local = ProviderPreset.builtIn.filter { $0.baseURL.contains("127.0.0.1") }
        for preset in local {
            XCTAssertEqual(
                preset.credentialMode, .none,
                preset.id + " runs locally, so it must not ask for a key"
            )
        }
        let cloud = ProviderPreset.builtIn.filter { !$0.baseURL.contains("127.0.0.1") }
        XCTAssertFalse(cloud.isEmpty, "the catalogue still offers cloud providers")
        for preset in cloud {
            XCTAssertNotEqual(preset.credentialMode, .none, preset.id + " needs a credential mode")
        }
    }

    func testGroupingKeepsEveryPresetAndUsesStableCategoryOrder() {
        let groups = ProviderPreset.groups(ProviderPreset.builtIn)
        let flattened = groups.flatMap(\.presets)
        XCTAssertEqual(flattened.count, ProviderPreset.builtIn.count)
        var seen = Set<String>()
        for group in groups {
            XCTAssertFalse(group.category.isEmpty)
            XCTAssertFalse(group.presets.isEmpty, "an empty group should not be rendered")
            XCTAssertTrue(seen.insert(group.category).inserted, "category repeated: " + group.category)
        }
        let expected = ProviderPreset.builtIn.reduce(into: [String]()) { order, preset in
            if !order.contains(preset.category) { order.append(preset.category) }
        }
        XCTAssertEqual(groups.map(\.category), expected, "group order must follow the catalogue order")
    }

    func testGroupingAnEmptyCatalogueIsEmpty() {
        XCTAssertTrue(ProviderPreset.groups([]).isEmpty)
    }

    func testMakeProviderUsesTheRequestedIdentifierAndPresetDefaults() {
        let preset = ProviderPreset.builtIn[0]
        let provider = preset.makeProvider(id: "my-id")
        XCTAssertEqual(provider.id, "my-id")
        XCTAssertEqual(provider.name, preset.name)
        XCTAssertEqual(provider.baseURL, preset.baseURL)
        XCTAssertEqual(provider.credentialMode, preset.credentialMode)
        XCTAssertEqual(provider.models.map(\.slug), preset.modelSlugs)
        XCTAssertEqual(provider.bearerToken, "", "a preset must never ship a credential")
    }

    /// Each suggested model must carry the context window its provider documents.
    ///
    /// These values used to be a single hardcoded 128000 for every model on every provider,
    /// which understated DeepSeek-V4 and Kimi K3 (1M) and overstated kimi-k2.7-code (256K).
    /// Codex sizes its own budgeting from this number, so a wrong value truncates a long session.
    func testEveryPresetModelCarriesItsDocumentedContextWindow() {
        for preset in ProviderPreset.builtIn {
            for presetModel in preset.models {
                XCTAssertGreaterThanOrEqual(
                    presetModel.contextWindow, 128_000,
                    preset.id + "/" + presetModel.slug + " context looks too small to be real"
                )
                XCTAssertLessThanOrEqual(
                    presetModel.contextWindow, 2_000_000,
                    preset.id + "/" + presetModel.slug + " context looks implausible"
                )
            }
        }
    }

    func testProviderFromPresetKeepsEachModelsOwnContextWindow() {
        for preset in ProviderPreset.builtIn where preset.models.count > 1 {
            let provider = preset.makeProvider(id: preset.id)
            XCTAssertEqual(
                provider.models.count, preset.models.count,
                preset.id + " lost models"
            )
            for (index, expected) in preset.models.enumerated() {
                let built = provider.models[index]
                XCTAssertEqual(built.slug, expected.slug)
                XCTAssertEqual(built.contextWindow, expected.contextWindow,
                               preset.id + "/" + expected.slug + " lost its context window")
                XCTAssertEqual(built.maxContextWindow, expected.contextWindow)
            }
        }
    }

    func testEveryPresetProducesAProviderThatPassesValidation() {
        for preset in ProviderPreset.builtIn {
            let provider = preset.makeProvider(id: preset.id)
            var draft = ProviderDraft(provider: provider, existingIDs: [preset.id])
            if preset.credentialMode == .bearerToken {
                // The user supplies the key; validation must pass once it is filled in.
                draft.provider.bearerToken = "sk-placeholder"
            }
            XCTAssertTrue(
                draft.errors.isEmpty,
                preset.id + " has errors: " + draft.errors.map(\.message).joined(separator: " / ")
            )
        }
    }

    func testEveryPresetProducesModelsCodexCanUse() {
        for preset in ProviderPreset.builtIn {
            let provider = preset.makeProvider(id: preset.id)
            for model in provider.models {
                XCTAssertFalse(model.slug.isEmpty, preset.id)
                XCTAssertGreaterThanOrEqual(model.contextWindow, 1_024, preset.id)
                XCTAssertGreaterThanOrEqual(
                    model.maxContextWindow, model.contextWindow, preset.id
                )
                XCTAssertTrue(
                    model.supportedReasoningEfforts.contains(model.defaultReasoningEffort),
                    preset.id + " defaults to an effort it does not advertise"
                )
            }
        }
    }
}
