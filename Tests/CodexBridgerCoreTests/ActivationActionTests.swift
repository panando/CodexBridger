import XCTest
@testable import CodexBridgerCore

/// Seam: ActivationAction.availability(...) — whether the primary action bar button can be used.
///
/// This is the regression guard for the reported bug. The button used to be disabled whenever the
/// provider was the one ChatGPT was already using, and that was the only path that rewrote the
/// model parameter file. So a user who edited the active provider's model parameters had no way
/// to make the change reach ChatGPT. The button must stay usable there.
final class ActivationActionTests: XCTestCase {

    private func availability(
        hasModels: Bool = true,
        isDirty: Bool = false,
        hasErrors: Bool = false,
        isAlreadyActive: Bool = false
    ) -> ActivationAction.Availability {
        ActivationAction.availability(
            hasModels: hasModels,
            isDirty: isDirty,
            hasErrors: hasErrors,
            isAlreadyActive: isAlreadyActive
        )
    }

    func testTheProviderAlreadyInUseCanStillBeWrittenAgain() {
        let state = availability(isAlreadyActive: true)

        XCTAssertTrue(state.isEnabled, "the active provider must still be writable")
        XCTAssertEqual(state.title, "更新配置")
    }

    func testTheActiveProviderSaysWhatTheButtonDoes() {
        let state = availability(isAlreadyActive: true)

        XCTAssertTrue(state.help.contains("ChatGPT"), "the help must say what gets written: \(state.help)")
    }

    func testANonActiveProviderSaysEnable() {
        let state = availability()

        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.title, "启用")
    }

    func testUnsavedEditsBlockTheAction() {
        let state = availability(isDirty: true)

        XCTAssertFalse(state.isEnabled, "activation must not silently use unsaved edits")
        XCTAssertEqual(state.help, "需要先保存")
    }

    func testUnsavedEditsBlockUpdatingTheActiveProviderToo() {
        let state = availability(isDirty: true, isAlreadyActive: true)

        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.title, "更新配置", "the title still describes the action")
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

    func testTheHelpAlwaysExplainsItself() {
        let cases: [ActivationAction.Availability] = [
            availability(),
            availability(isAlreadyActive: true),
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
