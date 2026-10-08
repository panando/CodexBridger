import XCTest
@testable import CodexBridgerCore

/// Seam: ActivationAction.availability(...) — whether the primary action bar button can be used.
///
/// The contract the user restated on 2026-10-08:
///
/// * 保存 writes this app's own settings file and nothing else.
/// * 启用 applies the saved provider to ChatGPT, backing the previous files up first.
/// * Once that has happened for the provider in use, the button goes flat — and a save that
///   changes something brings it straight back.
///
/// The last part replaces the 1.1.0 rule, which kept the button usable for the active provider at
/// all times. The trap that rule was guarding against — a changed provider with no way to reach the
/// files — is still guarded: "changed since it was applied" is exactly what re-enables it.
final class ActivationActionTests: XCTestCase {

    private func availability(
        hasModels: Bool = true,
        isDirty: Bool = false,
        hasErrors: Bool = false,
        isAlreadyActive: Bool = false,
        isAlreadyPublished: Bool = false
    ) -> ActivationAction.Availability {
        ActivationAction.availability(
            hasModels: hasModels,
            isDirty: isDirty,
            hasErrors: hasErrors,
            isAlreadyActive: isAlreadyActive,
            isAlreadyPublished: isAlreadyPublished
        )
    }

    /// The reported complaint: after enabling, the button sat there lit while there was nothing
    /// left to apply — and pressing it wrote the same files again, with a backup on the way.
    func testTheProviderAlreadyAppliedCannotBeAppliedAgain() {
        let state = availability(isAlreadyActive: true, isAlreadyPublished: true)

        XCTAssertFalse(state.isEnabled, "applying the same settings again is a no-op")
        XCTAssertEqual(state.title, "启用")
        XCTAssertTrue(
            state.help.contains("改完保存后"),
            "the help has to say how the button comes back: " + state.help
        )
    }

    /// The way out still exists, which is what the 1.1.0 rule was protecting.
    func testSavingAChangeBringsTheButtonBack() {
        let state = availability(isAlreadyActive: true, isAlreadyPublished: false)

        XCTAssertTrue(state.isEnabled, "a saved change has to be publishable")
        XCTAssertEqual(state.title, "启用")
        XCTAssertTrue(state.help.contains("备份"), "the help promises the backup: " + state.help)
    }

    func testAProviderThatIsNotInUseCanBeApplied() {
        let state = availability()

        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.title, "启用")
        XCTAssertTrue(state.help.contains("ChatGPT"), state.help)
    }

    func testUnsavedEditsBlockTheAction() {
        let state = availability(isDirty: true)

        XCTAssertFalse(state.isEnabled, "activation must not silently use unsaved edits")
        XCTAssertEqual(state.help, "需要先保存")
    }

    func testUnsavedEditsBlockTheActiveProviderToo() {
        let state = availability(isDirty: true, isAlreadyActive: true, isAlreadyPublished: false)

        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.title, "启用", "one action, one name")
    }

    func testFormErrorsBlockTheAction() {
        let state = availability(hasErrors: true)

        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.help, "先解决表单里的错误")
    }

    func testNoModelsBlocksTheAction() {
        let state = availability(hasModels: false)

        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.help, "需要至少一个模型")
    }

    /// One action, one name: the label no longer flips between 启用 and 更新配置.
    func testTheButtonIsCalledEnableInEveryState() {
        let cases: [ActivationAction.Availability] = [
            availability(),
            availability(isAlreadyActive: true),
            availability(isAlreadyActive: true, isAlreadyPublished: true),
            availability(isDirty: true),
            availability(hasErrors: true),
            availability(hasModels: false)
        ]
        for state in cases {
            XCTAssertEqual(state.title, "启用", "unexpected label: \(state)")
        }
    }

    func testTheHelpAlwaysExplainsItself() {
        let cases: [ActivationAction.Availability] = [
            availability(),
            availability(isAlreadyActive: true),
            availability(isAlreadyActive: true, isAlreadyPublished: true),
            availability(isDirty: true),
            availability(hasErrors: true),
            availability(hasModels: false)
        ]
        for state in cases {
            XCTAssertFalse(state.help.isEmpty, "every state must explain the button: \(state)")
            XCTAssertFalse(state.title.isEmpty)
        }
    }
}
