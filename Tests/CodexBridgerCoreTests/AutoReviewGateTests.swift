import Foundation
import XCTest
@testable import CodexBridgerCore

/// Seam: AutoReviewGate — the pure decision behind the 自动审批模型 section's
/// controls. The rules are the ones agreed in planning: no models, no usable
/// key, or no scan result removes a path; manual entry always remains.
final class AutoReviewGateTests: XCTestCase {

    // MARK: Scan availability

    func testScanDisabledWithoutModels() {
        let verdict = AutoReviewGate.availability(
            modelSlugs: [], credential: .ready
        )
        XCTAssertFalse(verdict.canScan)
        XCTAssertTrue(verdict.scanHint.contains("模型"))
    }

    func testScanEnabledWithModelsAndKey() {
        let verdict = AutoReviewGate.availability(
            modelSlugs: ["kimi-k2.7-code"], credential: .ready
        )
        XCTAssertTrue(verdict.canScan)
    }

    func testScanDisabledWhenBearerModeHasNoKey() {
        let verdict = AutoReviewGate.availability(
            modelSlugs: ["m"], credential: .missing
        )
        XCTAssertFalse(verdict.canScan)
        XCTAssertTrue(verdict.scanHint.contains("Key") || verdict.scanHint.contains("API Key"))
    }

    func testScanRequiresOneTimeKeyForEnvironmentOrCommandMode() {
        let verdict = AutoReviewGate.availability(
            modelSlugs: ["m"], credential: .needsOneTimeKey
        )
        XCTAssertFalse(verdict.canScan)
        XCTAssertTrue(verdict.canStartOneTimeKeyEntry)
    }

    func testScanNeedsNothingForCredentiallessProvider() {
        let verdict = AutoReviewGate.availability(
            modelSlugs: ["m"], credential: .notRequired
        )
        XCTAssertTrue(verdict.canScan)
    }

    // MARK: Dropdown availability

    func testDropdownNeedsAScanWithAtLeastOneSupportedModel() {
        let cache = AutoReviewScanCache(
            providerID: "cpa",
            scannedSlugs: ["bad"],
            scannedAt: Date(),
            outcomes: [AutoReviewProbeOutcome(slug: "bad", status: .unsupported, latencyMs: 1, summary: nil)]
        )
        let verdict = AutoReviewGate.availability(
            modelSlugs: ["bad"], credential: .ready, cache: cache
        )
        XCTAssertFalse(verdict.canPickFromScan)
    }

    func testDropdownAvailableWhenScanPassedModelsAndCacheIsFresh() {
        let cache = AutoReviewScanCache(
            providerID: "cpa",
            scannedSlugs: ["good", "bad"],
            scannedAt: Date(),
            outcomes: [
                AutoReviewProbeOutcome(slug: "good", status: .supported, latencyMs: 800, summary: nil),
                AutoReviewProbeOutcome(slug: "bad", status: .unsupported, latencyMs: 300, summary: nil)
            ]
        )
        let verdict = AutoReviewGate.availability(
            modelSlugs: ["good", "bad"], credential: .ready, cache: cache
        )
        XCTAssertTrue(verdict.canPickFromScan)
        XCTAssertEqual(verdict.candidateSlugs, ["good"])
        XCTAssertFalse(verdict.cacheIsStale)
    }

    func testDropdownBlockedWhenCacheIsStale() {
        let cache = AutoReviewScanCache(
            providerID: "cpa",
            scannedSlugs: ["good"],
            scannedAt: Date(),
            outcomes: [AutoReviewProbeOutcome(slug: "good", status: .supported, latencyMs: 10, summary: nil)]
        )
        let verdict = AutoReviewGate.availability(
            modelSlugs: ["good", "added-later"], credential: .ready, cache: cache
        )
        XCTAssertFalse(verdict.canPickFromScan)
        XCTAssertTrue(verdict.cacheIsStale)
    }

    func testManualEntryAlwaysAvailable() {
        let nothing = AutoReviewGate.availability(modelSlugs: [], credential: .missing)
        XCTAssertTrue(nothing.canEnterManually)
    }
}
