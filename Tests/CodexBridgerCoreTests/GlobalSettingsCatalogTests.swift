import XCTest
@testable import CodexBridgerCore

/// The parameter catalog is data, so these tests pin the data itself: which keys are
/// editable, which are only shown, and that the four tiers plus the keys other parts of
/// the app already own account for every top-level key the official reference documents
/// for config.toml.
///
/// The expected key lists below are a transcription of the official Configuration
/// Reference (config.toml section, 297 rows), read 2026-10-08 from
/// https://learn.chatgpt.com/docs/config-file/config-reference — an independent source of
/// truth, not a recomputation of the code under test.
final class GlobalSettingsCatalogTests: XCTestCase {

    // MARK: - The official universe, transcribed from the reference

    /// The 54 keys the reference lists as a bare table row.
    static let officialBareKeys: Set<String> = [
        "agents", "allow_login_shell", "approval_policy", "approvals_reviewer",
        "background_terminal_max_timeout", "chatgpt_base_url", "check_for_update_on_startup",
        "cli_auth_credentials_store", "compact_prompt", "default_permissions",
        "developer_instructions", "disable_paste_burst", "experimental_compact_prompt_file",
        "experimental_use_unified_exec_tool", "file_opener", "forced_chatgpt_workspace_id",
        "forced_login_method", "hide_agent_reasoning", "hooks", "instructions", "log_dir",
        "mcp_oauth_callback_port", "mcp_oauth_callback_url", "mcp_oauth_credentials_store",
        "mcp_optional_startup_grace_ms", "model", "model_auto_compact_token_limit",
        "model_auto_compact_token_limit_scope", "model_catalog_json", "model_context_window",
        "model_instructions_file", "model_provider", "model_reasoning_effort",
        "model_reasoning_summary", "model_supports_reasoning_summaries", "model_verbosity",
        "notify", "openai_base_url", "oss_provider", "personality",
        "plan_mode_reasoning_effort", "project_doc_fallback_filenames", "project_doc_max_bytes",
        "project_root_markers", "review_model", "sandbox_mode", "service_tier",
        "show_raw_agent_reasoning", "sqlite_home", "suppress_unstable_features_warning",
        "tool_output_token_limit", "tui", "web_search", "windows_wsl_setup_acknowledged"
    ]

    /// The 24 keys the reference documents only through their sub-keys (no bare row).
    static let officialTableKeys: Set<String> = [
        "analytics", "apps", "auto_review", "browser_use", "computer_use", "desktop",
        "features", "feedback", "history", "marketplaces", "mcp_servers", "memories",
        "model_providers", "notice", "otel", "permissions", "plugins", "projects",
        "sandbox_workspace_write", "shell_environment_policy", "skills", "tool_suggest",
        "tools", "windows"
    ]

    /// The keys the provider screen and the activation flow already write (ruling Q3=A).
    static let ownedByProviderFeature: Set<String> = [
        "model", "model_provider", "model_catalog_json", "model_reasoning_effort",
        "model_reasoning_summary", "model_verbosity", "model_supports_reasoning_summaries"
    ]

    /// The six keys the page draws, and therefore the only six it may write.
    static let ruledShown: Set<String> = [
        "approval_policy", "approvals_reviewer", "sandbox_mode", "allow_login_shell",
        "hide_agent_reasoning", "show_raw_agent_reasoning"
    ]

    static let ruledHidden: Set<String> = ["agents", "hooks", "instructions"]

    static let ruledOmitted: Set<String> = [
        "model_context_window", "model_instructions_file", "experimental_compact_prompt_file",
        "project_doc_fallback_filenames", "project_doc_max_bytes",
        "background_terminal_max_timeout", "cli_auth_credentials_store",
        "mcp_oauth_credentials_store", "oss_provider", "tui",
        "experimental_use_unified_exec_tool", "disable_paste_burst",
        "windows_wsl_setup_acknowledged",
        // Added by the 2026-10-08 ruling: the page keeps two groups and these keys left it.
        "model_auto_compact_token_limit", "model_auto_compact_token_limit_scope",
        "tool_output_token_limit", "plan_mode_reasoning_effort", "review_model",
        "service_tier", "web_search", "personality", "file_opener", "notify",
        "project_root_markers", "developer_instructions", "compact_prompt",
        "mcp_optional_startup_grace_ms", "check_for_update_on_startup",
        "suppress_unstable_features_warning", "chatgpt_base_url", "openai_base_url",
        "forced_login_method", "forced_chatgpt_workspace_id", "mcp_oauth_callback_port",
        "mcp_oauth_callback_url", "log_dir", "sqlite_home", "default_permissions"
    ]

    // MARK: - The accounting

    /// Six, by the 2026-10-08 ruling: two groups, four approval/sandbox keys and two reasoning
    /// switches. This is also the set the draft may write, which the draft tests pin.
    func testTheScreenShowsExactlyTheRuledSixKeys() {
        XCTAssertEqual(GlobalSettingsCatalog.settings.count, 6)
        XCTAssertEqual(Set(GlobalSettingsCatalog.settings.map(\.key)), Self.ruledShown)
    }

    func testHiddenTierIsExactlyTheRuledThreeKeys() {
        XCTAssertEqual(Set(GlobalSettingsCatalog.hidden.map(\.key)), Self.ruledHidden)
    }

    func testOmittedTierIsExactlyTheRuledThirtyEightKeys() {
        XCTAssertEqual(GlobalSettingsCatalog.omitted.count, 38)
        XCTAssertEqual(Set(GlobalSettingsCatalog.omitted.map(\.key)), Self.ruledOmitted)
    }

    func testCatalogListsTheTwentyFourTablesAndTheSevenOwnedKeys() {
        XCTAssertEqual(GlobalSettingsCatalog.tableKeys, Self.officialTableKeys)
        XCTAssertEqual(GlobalSettingsCatalog.ownedByProviderFeature, Self.ownedByProviderFeature)
    }

    func testTheThreeBucketsNeverOverlapAndCoverEveryCatalogedKey() {
        let keys = GlobalSettingsCatalog.settings.map(\.key)
            + GlobalSettingsCatalog.hidden.map(\.key)
            + GlobalSettingsCatalog.omitted.map(\.key)
        XCTAssertEqual(keys.count, 47, "shown + hidden + omitted must hold every cataloged key")
        XCTAssertEqual(keys.count, Set(keys).count, "a key appears in more than one bucket")
    }

    func testEveryCatalogKeyIsADocumentedConfigTOMLKey() {
        // Non-vacuity: an empty catalog would satisfy the loop below without checking anything.
        XCTAssertEqual(GlobalSettingsCatalog.allKeys.count, 47)
        for setting in GlobalSettingsCatalog.settings {
            XCTAssertTrue(
                Self.officialBareKeys.contains(setting.key),
                setting.key + " is not a documented config.toml key"
            )
        }
    }

    /// Compares the catalog's own data against the official universe, so it can actually
    /// disagree with the code (the expected side is the transcription, not a recomputation).
    func testCatalogAccountsForEveryDocumentedConfigTOMLKey() {
        let accounted = GlobalSettingsCatalog.allKeys
            .union(GlobalSettingsCatalog.ownedByProviderFeature)
            .union(GlobalSettingsCatalog.tableKeys)
        XCTAssertEqual(
            accounted,
            Self.officialBareKeys.union(Self.officialTableKeys),
            "every documented config.toml key must be either shown, excluded, owned or a table"
        )
        XCTAssertEqual(accounted.count, 78)
    }

    // MARK: - Controls and allowed values

    /// The allowed values and the control of each key, read off the reference's
    /// "Type / Values" column. A typo in the catalog's data must fail here.
    static let expectedChoices: [String: [String]] = [
        "approval_policy": ["on-request", "never"],
        "approvals_reviewer": ["user", "auto_review"],
        "sandbox_mode": ["read-only", "workspace-write", "danger-full-access"]
    ]

    static let expectedToggles: Set<String> = [
        "allow_login_shell", "hide_agent_reasoning", "show_raw_agent_reasoning"
    ]

    func testAllowedValuesMatchTheDocumentedTypeColumn() {
        for setting in GlobalSettingsCatalog.settings {
            guard case let .choice(values) = setting.control else { continue }
            XCTAssertEqual(
                values,
                Self.expectedChoices[setting.key],
                setting.key + " lists values the reference does not document"
            )
        }
    }

    func testEveryChoiceKeyUsesAChoiceControlAndEveryOtherKeyDoesNot() {
        for setting in GlobalSettingsCatalog.settings {
            let isChoice = Self.expectedChoices[setting.key] != nil
            if case .choice = setting.control {
                XCTAssertTrue(isChoice, setting.key + " should not be a dropdown")
            } else {
                XCTAssertFalse(isChoice, setting.key + " should be a dropdown")
            }
        }
    }

    func testBooleanKeysUseTheToggleControl() {
        // Non-vacuity: three of the six keys must be switches, or the loop below proves nothing.
        XCTAssertEqual(Self.expectedToggles.count, 3)
        for setting in GlobalSettingsCatalog.settings where Self.expectedToggles.contains(setting.key) {
            XCTAssertEqual(setting.control, .toggle, setting.key)
        }
    }

    /// After the 2026-10-08 ruling the page has no free-text, number or array rows left. Pinned
    /// so that adding one is a deliberate act rather than a side effect.
    func testTheScreenUsesOnlySwitchesAndDropdowns() {
        let kinds = Set(GlobalSettingsCatalog.settings.map { setting -> String in
            switch setting.control {
            case .toggle: return "toggle"
            case .choice: return "choice"
            case .integer: return "integer"
            case .text: return "text"
            case .stringArray: return "stringArray"
            }
        })
        XCTAssertEqual(kinds, ["toggle", "choice"])
    }

    func testEveryShownSettingExplainsItselfInPlainLanguage() {
        XCTAssertEqual(GlobalSettingsCatalog.settings.count, 6, "non-vacuity: the loop must run")
        for setting in GlobalSettingsCatalog.settings {
            XCTAssertFalse(
                setting.detail.isEmpty,
                setting.key + " has no explanation behind the info badge"
            )
        }
    }

    /// The eighth review: 注释需要精简. The ⓘ is read once, in a popover that has to fit on screen,
    /// so length is a cost. The cap is deliberately tight enough that it has to be argued with:
    /// the previous text was roughly twice this and named the same values.
    func testEveryExplanationIsShortEnoughToReadAtAGlance() {
        XCTAssertEqual(GlobalSettingsCatalog.settings.count, 6, "non-vacuity: the loop must run")
        let cap = 70
        var longest = 0
        for setting in GlobalSettingsCatalog.settings {
            longest = max(longest, setting.detail.count)
            XCTAssertLessThanOrEqual(
                setting.detail.count, cap,
                setting.key + " is " + String(setting.detail.count) + " characters, over the "
                + String(cap) + " cap: " + setting.detail
            )
        }
        // Without this the cap could be satisfied by texts that say nothing.
        XCTAssertGreaterThan(longest, 25, "the cap has to be within reach, longest=" + String(longest))
    }

    // MARK: - The annotations (seventh review round, 2026-10-08)

    /// The annotation follows the interface language. Reported from the running app: the info badge
    /// always showed English — an English quote sitting in a Chinese page. A missing entry degrades
    /// to Chinese at runtime rather than failing, so only a test can catch it. (The caption under
    /// each control had the opposite problem and no English at all; that caption is now gone.)
    func testEveryAnnotationHasAnEnglishVersion() {
        XCTAssertEqual(GlobalSettingsCatalog.settings.count, 6, "non-vacuity: the loop must run")
        for setting in GlobalSettingsCatalog.settings {
            XCTAssertNotNil(
                Localization.english[setting.detail],
                "no English for the info text of " + setting.key + ": " + setting.detail
            )
            XCTAssertEqual(
                Localization.text(setting.detail, language: .chinese), setting.detail,
                "Chinese is the source language: a Chinese interface shows the string as written"
            )
        }
    }

    /// The reference's own sentence per key, transcribed from
    /// docs/reference/codex-config-reference.md (the config.toml table), so the expected side is an
    /// independent source rather than a recomputation of the code under test.
    static let officialSentences: [String: String] = [
        "approval_policy":
            "Controls when Codex pauses for approval before executing commands.",
        "approvals_reviewer":
            "Who reviews eligible approval prompts under `on-request` or granular approval policies.",
        "sandbox_mode":
            "Sandbox policy for filesystem and network access during command execution.",
        "allow_login_shell":
            "Allow shell-based tools to use login-shell semantics.",
        "hide_agent_reasoning":
            "Suppress reasoning events in both the TUI and `codex exec` output.",
        "show_raw_agent_reasoning":
            "Surface raw reasoning content when the active model emits it.",
    ]

    /// Rewriting the annotation so a reader understands it must not drift away from the reference:
    /// the English text still opens with the official sentence, with the one word the product naming
    /// rule forces.
    func testTheEnglishExplanationStillQuotesTheOfficialSentence() {
        XCTAssertEqual(
            Self.officialSentences.count, GlobalSettingsCatalog.settings.count,
            "every shown key needs a transcribed sentence, or this proves nothing"
        )
        for setting in GlobalSettingsCatalog.settings {
            let official = Self.officialSentences[setting.key] ?? ""
            XCTAssertFalse(official.isEmpty, setting.key + " has no transcribed official sentence")
            // The reference marks code spans with backticks and names the product Codex;
            // the interface draws plain text and says ChatGPT, so both come off before the
            // comparison and the difference is stated here rather than hidden.
            let adapted = official
                .replacingOccurrences(of: "Codex", with: "ChatGPT")
                .replacingOccurrences(of: "`", with: "")
            let english = Localization.text(setting.detail, language: .english)
            XCTAssertTrue(
                english.contains(adapted),
                setting.key + " no longer quotes the reference: " + english
            )
        }
    }

    /// The complaint that opened the round: the annotation did not say what the choices mean. Every
    /// value the drop-down offers has to be named, in both languages.
    func testEveryValueADropDownOffersIsExplainedInBothLanguages() {
        var dropDowns = 0
        for setting in GlobalSettingsCatalog.settings {
            guard case let .choice(values) = setting.control else { continue }
            dropDowns += 1
            let chinese = Localization.text(setting.detail, language: .chinese)
            let english = Localization.text(setting.detail, language: .english)
            for value in values {
                XCTAssertTrue(
                    chinese.contains(value),
                    setting.key + ": the Chinese text never mentions " + value
                )
                XCTAssertTrue(
                    english.contains(value),
                    setting.key + ": the English text never mentions " + value
                )
            }
        }
        XCTAssertEqual(dropDowns, 3, "non-vacuity: three keys are drop-downs")
    }

    /// The interface calls the product ChatGPT, including inside the adapted official quotes.
    /// Pinned here as well as in ProductNamingTests so the reason travels with this catalog.
    func testCatalogNeverShowsTheRetiredProductName() {
        for setting in GlobalSettingsCatalog.settings {
            XCTAssertFalse(
                setting.detail.contains("Codex"),
                setting.key + " info text still says Codex"
            )
        }
        for excluded in GlobalSettingsCatalog.excluded {
            XCTAssertFalse(excluded.reason.contains("Codex"), excluded.key + " reason still says Codex")
        }
    }


}
