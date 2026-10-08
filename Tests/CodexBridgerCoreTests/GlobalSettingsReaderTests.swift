import XCTest
@testable import CodexBridgerCore

/// Seam: `GlobalSettingsReader` turns config.toml text into, per key, either a value this
/// screen may rewrite, a form it must leave alone, or nothing at all.
///
/// The fragments below are copied from the user's real ~/.codex/config.toml (read
/// 2026-10-08), including its mixed single/double quotes. They also contain keys this screen
/// does not show — `model`, `notify`, `personality` — on purpose: they are the control group
/// for "not shown means not read".
final class GlobalSettingsReaderTests: XCTestCase {

    /// The first top-level keys of the real file, verbatim.
    static let realHead = """
    approval_policy = "on-request"
    approvals_reviewer = "auto_review"
    model = "deepseek-v4.1-flash"
    model_provider = "cpa"
    model_catalog_json = "/Users/panando/.codex/model-catalogs/cpa-model-catalog.json"
    model_reasoning_effort = "high"
    notify = [
        '/Users/panando/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient',
        'turn-ended'
    ]
    personality = 'pragmatic'
    sandbox_mode = 'workspace-write'
    """

    func testEveryShownKeyIsReported() {
        let states = GlobalSettingsReader.states(in: Self.realHead)
        for setting in GlobalSettingsCatalog.settings {
            XCTAssertNotNil(states[setting.key], setting.key + " is missing from the report")
        }
        XCTAssertEqual(states.count, 6)
    }

    /// The other half of the same rule, and the reason a write cannot disturb the rest of the
    /// file: a key this screen does not draw is not even read, so it can never be rewritten.
    func testKeysTheScreenDoesNotShowAreNotReported() {
        let states = GlobalSettingsReader.states(in: Self.realHead)
        for key in ["model", "model_provider", "model_reasoning_effort", "notify", "personality"] {
            XCTAssertNil(states[key], key + " is not shown, so it must not appear in the report")
        }
    }

    func testTheRealFilesDoubleQuotedChoiceIsRead() {
        let states = GlobalSettingsReader.states(in: Self.realHead)
        XCTAssertEqual(
            states["approval_policy"],
            .value(raw: "\"on-request\"", parsed: .choice("on-request"))
        )
        XCTAssertEqual(
            states["approvals_reviewer"],
            .value(raw: "\"auto_review\"", parsed: .choice("auto_review"))
        )
    }

    func testTheRealFilesSingleQuotedValueIsRead() {
        XCTAssertEqual(
            GlobalSettingsReader.states(in: Self.realHead)["sandbox_mode"],
            .value(raw: "'workspace-write'", parsed: .choice("workspace-write"))
        )
    }

    func testAKeyTheFileDoesNotHaveIsUnset() {
        let states = GlobalSettingsReader.states(in: Self.realHead)
        XCTAssertEqual(states["hide_agent_reasoning"], .unset)
        XCTAssertEqual(states["show_raw_agent_reasoning"], .unset)
    }

    func testAGranularApprovalPolicyIsReadButNeverOfferedForEditing() {
        let text = "approval_policy = { granular = { sandbox_approval = true } }"
        let states = GlobalSettingsReader.states(in: text)
        XCTAssertEqual(
            states["approval_policy"],
            .advancedForm(raw: "{ granular = { sandbox_approval = true } }")
        )
    }

    func testAKeyInsideATableIsNotMistakenForATopLevelKey() {
        let text = """
        model = "gpt-5.5"
        
        [features]
        approval_policy = "never"
        """
        let states = GlobalSettingsReader.states(in: text)
        XCTAssertEqual(states["approval_policy"], .unset, "approval_policy lives inside [features] here")
    }

    func testBooleanValuesAreParsed() {
        XCTAssertEqual(
            GlobalSettingsReader.states(in: "allow_login_shell = false")["allow_login_shell"],
            .value(raw: "false", parsed: .flag(false))
        )
        XCTAssertEqual(
            GlobalSettingsReader.states(in: "allow_login_shell = true")["allow_login_shell"],
            .value(raw: "true", parsed: .flag(true))
        )
    }

    /// A choice value this build has never heard of must not be silently replaced: a newer
    /// build of the product may accept it.
    func testAChoiceValueThisBuildDoesNotKnowIsLeftAlone() {
        XCTAssertEqual(
            GlobalSettingsReader.states(in: "sandbox_mode = \"readonly\"")["sandbox_mode"],
            .advancedForm(raw: "\"readonly\"")
        )
    }

    func testAValueOfTheWrongShapeIsTreatedAsAnAdvancedForm() {
        XCTAssertEqual(
            GlobalSettingsReader.states(in: "sandbox_mode = 3")["sandbox_mode"],
            .advancedForm(raw: "3")
        )
        XCTAssertEqual(
            GlobalSettingsReader.states(in: "allow_login_shell = \"yes\"")["allow_login_shell"],
            .advancedForm(raw: "\"yes\"")
        )
    }
}
