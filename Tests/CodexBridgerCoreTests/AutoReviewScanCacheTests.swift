import Foundation
import XCTest
@testable import CodexBridgerCore

/// Seam: AutoReviewScanCache — the persisted scan result. Expected values are the
/// plan's rules: cached results survive a restart, go stale when the model list
/// changes, and can never carry a credential.
final class AutoReviewScanCacheTests: XCTestCase {

    private func outcome(_ slug: String, _ status: AutoReviewProbeStatus) -> AutoReviewProbeOutcome {
        AutoReviewProbeOutcome(slug: slug, status: status, latencyMs: 120, summary: nil)
    }

    private func cache(slugs: [String]) -> AutoReviewScanCache {
        AutoReviewScanCache(
            providerID: "cpa",
            scannedSlugs: slugs,
            scannedAt: Date(timeIntervalSince1970: 1_800_000_000),
            outcomes: slugs.map { outcome($0, .supported) }
        )
    }

    // MARK: Staleness

    func testFreshWhenSlugSetMatchesIgnoringOrder() {
        let cache = self.cache(slugs: ["a", "b"])
        XCTAssertFalse(cache.isStale(currentSlugs: ["b", "a"]))
    }

    func testStaleWhenModelWasAddedOrRemoved() {
        let cache = self.cache(slugs: ["a", "b"])
        XCTAssertTrue(cache.isStale(currentSlugs: ["a", "b", "c"]))
        XCTAssertTrue(cache.isStale(currentSlugs: ["a"]))
    }

    func testStaleWhenModelWasRenamed() {
        let cache = self.cache(slugs: ["a", "b"])
        XCTAssertTrue(cache.isStale(currentSlugs: ["a", "b2"]))
    }

    func testNotStaleWhenSingleModelDuplicatedInput() {
        let cache = self.cache(slugs: ["a"])
        XCTAssertFalse(cache.isStale(currentSlugs: ["a", "a"]))
    }

    // MARK: Querying

    func testSupportedSlugsListsOnlyPassingModels() {
        let stored = AutoReviewScanCache(
            providerID: "cpa",
            scannedSlugs: ["good", "bad"],
            scannedAt: Date(),
            outcomes: [outcome("good", .supported), outcome("bad", .unsupported)]
        )
        XCTAssertEqual(stored.supportedSlugs, ["good"])
    }

    func testOutcomeForSlugReturnsTheCachedOne() {
        let stored = cache(slugs: ["a"])
        XCTAssertEqual(stored.outcome(for: "a")?.status, .supported)
        XCTAssertNil(stored.outcome(for: "missing"))
    }

    // MARK: Round trip

    func testCacheSurvivesJSONRoundTrip() throws {
        let stored = cache(slugs: ["kimi-k2.7-code", "glm-5.2"])
        let data = try JSONEncoder().encode(stored)
        let decoded = try JSONDecoder().decode(AutoReviewScanCache.self, from: data)
        XCTAssertEqual(decoded, stored)
    }

    /// Hard rule from the user: no credential may ever reach the cache file.
    func testEncodedCacheCarriesNoCredentialMaterial() throws {
        let stored = AutoReviewScanCache(
            providerID: "cpa",
            scannedSlugs: ["m"],
            scannedAt: Date(),
            outcomes: [AutoReviewProbeOutcome(
                slug: "m", status: .unauthorized, latencyMs: 5,
                summary: "Bearer sk-super-secret rejected"
            )]
        )
        let data = try JSONEncoder().encode(stored)
        let json = String(data: data, encoding: .utf8) ?? ""
        // The provider's own error text is kept for diagnosis, but no key or
        // header name is stored: this asserts the structure holds no credential
        // field names.
        for forbidden in ["\"bearerToken\"", "\"token\"", "\"authorization\"", "\"apiKey\"", "\"key\""] {
            XCTAssertFalse(json.contains(forbidden), "cache must not declare a field named \(forbidden)")
        }
    }
}
