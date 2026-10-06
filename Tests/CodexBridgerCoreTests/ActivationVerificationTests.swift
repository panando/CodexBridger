import XCTest
@testable import CodexBridgerCore

/// Seam: ActivationVerification.warnings.
///
/// The write path cannot fail loudly enough on its own: if the file it wrote disagrees with
/// what was requested, the user finds out only when Codex misbehaves. This turns that into a
/// reportable result.
final class ActivationVerificationTests: XCTestCase {

    private func snapshot(
        configExists: Bool = true,
        provider: String? = "demo",
        model: String? = "demo-large",
        catalogJSON: String? = "/tmp/demo-model-catalog.json",
        catalogExists: Bool = true,
        providerIDs: [String] = ["demo"]
    ) -> CodexConfigSnapshot {
        CodexConfigSnapshot(
            configExists: configExists,
            modelProviderID: provider,
            modelSlug: model,
            modelCatalogJSON: catalogJSON,
            providerIDs: providerIDs,
            catalogFileExists: catalogExists
        )
    }

    func testConsistentWriteReportsNothing() {
        let warnings = ActivationVerification.warnings(
            expectedProviderID: "demo",
            expectedModelSlug: "demo-large",
            snapshot: snapshot()
        )
        XCTAssertTrue(warnings.isEmpty, warnings.joined(separator: " / "))
    }

    func testWrongProviderIsReported() {
        let warnings = ActivationVerification.warnings(
            expectedProviderID: "demo",
            expectedModelSlug: "demo-large",
            snapshot: snapshot(provider: "other")
        )
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("model_provider"))
        XCTAssertTrue(warnings[0].contains("other"))
    }

    func testWrongModelIsReported() {
        let warnings = ActivationVerification.warnings(
            expectedProviderID: "demo",
            expectedModelSlug: "demo-large",
            snapshot: snapshot(model: "demo-small")
        )
        XCTAssertTrue(warnings.contains { $0.contains("model 是") })
    }

    func testMissingConfigIsReported() {
        let warnings = ActivationVerification.warnings(
            expectedProviderID: "demo",
            expectedModelSlug: "demo-large",
            snapshot: snapshot(configExists: false)
        )
        XCTAssertTrue(warnings.contains { $0.contains("config.toml") })
    }

    func testMissingCatalogFileIsReported() {
        let warnings = ActivationVerification.warnings(
            expectedProviderID: "demo",
            expectedModelSlug: "demo-large",
            snapshot: snapshot(catalogExists: false)
        )
        XCTAssertTrue(warnings.contains { $0.contains("模型参数文件") })
    }

    func testMissingProviderTableIsReported() {
        let warnings = ActivationVerification.warnings(
            expectedProviderID: "demo",
            expectedModelSlug: "demo-large",
            snapshot: snapshot(providerIDs: ["other"])
        )
        XCTAssertTrue(warnings.contains { $0.contains("model_providers.demo") })
    }

    func testEveryProblemIsReportedTogetherNotJustTheFirst() {
        let warnings = ActivationVerification.warnings(
            expectedProviderID: "demo",
            expectedModelSlug: "demo-large",
            snapshot: snapshot(configExists: false, provider: nil, model: nil,
                                catalogJSON: nil, catalogExists: false, providerIDs: [])
        )
        XCTAssertEqual(warnings.count, 6, warnings.joined(separator: " / "))
    }

    func testUnsetValuesAreDescribedRatherThanPrintedAsNil() {
        let warnings = ActivationVerification.warnings(
            expectedProviderID: "demo",
            expectedModelSlug: "demo-large",
            snapshot: snapshot(provider: nil)
        )
        XCTAssertFalse(warnings.contains { $0.contains("nil") })
        XCTAssertTrue(warnings.contains { $0.contains("空") })
    }
}
