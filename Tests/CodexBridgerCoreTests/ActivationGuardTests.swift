import XCTest
@testable import CodexBridgerCore

/// Seam: ActivationGuard.assess
///
/// Codex has exactly one active provider. Activating replaces whatever is there, so the
/// app has to say what it is about to replace when that is not the same provider.
final class ActivationGuardTests: XCTestCase {

    func testFirstActivationOnAnEmptyConfigDoesNotNeedConfirmation() {
        let assessment = ActivationGuard.assess(
            currentProviderID: nil,
            targetProviderID: "demo",
            targetName: "示例提供商"
        )
        XCTAssertFalse(assessment.requiresConfirmation)
        XCTAssertTrue(assessment.message.isEmpty)
    }

    func testReactivatingTheSameProviderDoesNotNeedConfirmation() {
        let assessment = ActivationGuard.assess(
            currentProviderID: "demo",
            targetProviderID: "demo",
            targetName: "示例提供商"
        )
        XCTAssertFalse(
            assessment.requiresConfirmation,
            "re-activating the provider Codex already uses is not a destructive change"
        )
    }

    func testSwitchingAwayFromAnotherProviderNeedsConfirmation() {
        let assessment = ActivationGuard.assess(
            currentProviderID: "cpa",
            targetProviderID: "demo",
            targetName: "示例提供商"
        )
        XCTAssertTrue(assessment.requiresConfirmation)
        XCTAssertEqual(assessment.replacedProviderID, "cpa")
        XCTAssertTrue(assessment.message.contains("cpa"), "must name what is being replaced")
        XCTAssertTrue(assessment.message.contains("示例提供商"), "must name the new provider")
    }

    func testProviderIDIsCaseSensitiveLikeCodex() {
        let assessment = ActivationGuard.assess(
            currentProviderID: "Demo",
            targetProviderID: "demo",
            targetName: "示例提供商"
        )
        XCTAssertTrue(assessment.requiresConfirmation)
    }

    func testEmptyCurrentProviderIsTreatedAsUnset() {
        let assessment = ActivationGuard.assess(
            currentProviderID: "",
            targetProviderID: "demo",
            targetName: "示例提供商"
        )
        XCTAssertFalse(assessment.requiresConfirmation)
    }

    func testConfirmationTextAlwaysMentionsTheBackup() {
        let assessment = ActivationGuard.assess(
            currentProviderID: "cpa",
            targetProviderID: "demo",
            targetName: "示例提供商"
        )
        XCTAssertTrue(
            assessment.message.contains("备份"),
            "the user must know a backup is taken before anything is written"
        )
    }

    func testLocalhostTargetIsFlaggedAsProbablyNotReachable() {
        let local = ActivationGuard.assess(
            currentProviderID: nil,
            targetProviderID: "demo",
            targetName: "示例提供商",
            targetBaseURL: "http://127.0.0.1:8000/v1"
        )
        XCTAssertTrue(local.warnings.contains { $0.contains("本机") })
        let remote = ActivationGuard.assess(
            currentProviderID: nil,
            targetProviderID: "demo",
            targetName: "示例提供商",
            targetBaseURL: "https://api.example.com/v1"
        )
        XCTAssertTrue(remote.warnings.isEmpty)
    }

    func testMissingBaseURLIsWarnedAbout() {
        let assessment = ActivationGuard.assess(
            currentProviderID: nil,
            targetProviderID: "demo",
            targetName: "示例提供商",
            targetBaseURL: "   "
        )
        XCTAssertTrue(assessment.warnings.contains { $0.contains("base_url") })
    }
}
