import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: AppModel's 一键检测 wiring — start a scan with the responder seam
/// substituted, observe results, cache persistence, and the credential rules.
///
/// The prober is built through autoReviewProberFactory with a responder closure,
/// so no test here sends a real request.
@MainActor
final class AutoReviewScanFlowTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("autoreview-flow-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    /// An AppModel whose probes are answered by a responder that accepts the
    /// given slugs and refuses the rest with the strict-schema error.
    private func app(accepting supported: Set<String>) -> AppModel {
        let model = AppModel(paths: CodexPaths(codexHome: home))
        model.autoReviewProberFactory = {
            AutoReviewProbe(responder: { slug in
                supported.contains(slug) ? 200 : 400
            })
        }
        return model
    }

    private func draftProvider() -> ProviderDraft {
        var provider = ProviderConfiguration(
            id: "cpa",
            name: "示例",
            baseURL: "https://api.example.com/v1",
            credentialMode: .bearerToken,
            bearerToken: "sk-demo"
        )
        provider.models = [
            ModelConfiguration(slug: "kimi-k2.7-code", displayName: "Kimi"),
            ModelConfiguration(slug: "deepseek-v4-flash", displayName: "DeepSeek"),
            ModelConfiguration(slug: "glm-5.2", displayName: "GLM")
        ]
        return ProviderDraft(provider: provider)
    }

    private func waitForScan(_ app: AppModel) async {
        let deadline = Date().addingTimeInterval(5)
        while app.autoReviewState.isScanning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testScanPopulatesResultsAndCachesWithoutCredential() async throws {
        let app = self.app(accepting: ["kimi-k2.7-code", "glm-5.2"])
        app.startAutoReviewScan(draft: draftProvider(), oneTimeKey: nil)
        await waitForScan(app)

        XCTAssertFalse(app.autoReviewState.isScanning)
        let results = app.autoReviewState.results
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results.first { $0.slug == "kimi-k2.7-code" }?.status, .supported)
        XCTAssertEqual(results.first { $0.slug == "glm-5.2" }?.status, .supported)
        XCTAssertEqual(results.first { $0.slug == "deepseek-v4-flash" }?.status, .unsupported)

        // Persisted for the next launch, and fresh against the model list.
        let cache = app.configuration.autoReviewScans["cpa"]
        XCTAssertEqual(cache?.supportedSlugs.sorted(), ["glm-5.2", "kimi-k2.7-code"])
        XCTAssertFalse(
            cache?.isStale(currentSlugs: ["kimi-k2.7-code", "deepseek-v4-flash", "glm-5.2"]) ?? true
        )

        // Hard rule: the saved configuration file carries no credential inside
        // the scan cache.
        let data = try Data(contentsOf: CodexPaths(codexHome: home).appConfiguration)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("authorization"), "scan cache must not declare a credential")
        XCTAssertFalse(text.contains("\"token\""), "scan cache must not declare a token")
    }

    func testScanForCredentiallessProviderNeedsNoKey() async throws {
        let app = self.app(accepting: ["only"])
        var provider = ProviderConfiguration(
            id: "local", name: "本机", baseURL: "http://127.0.0.1:8317/v1", credentialMode: .none
        )
        provider.models = [ModelConfiguration(slug: "only", displayName: "Only")]
        let draft = ProviderDraft(provider: provider)
        XCTAssertTrue(
            app.autoReviewVerdict(draft: draft, credential: app.autoReviewCredential(for: draft)).canScan
        )
        app.startAutoReviewScan(draft: draft, oneTimeKey: nil)
        await waitForScan(app)
        XCTAssertEqual(app.autoReviewState.results.first?.status, .supported)
    }

    func testOneTimeKeyIsUsedForEnvironmentKeyModeAndNeverPersisted() async throws {
        let app = self.app(accepting: ["only"])
        var provider = ProviderConfiguration(
            id: "env", name: "环境变量", baseURL: "https://api.example.com/v1",
            credentialMode: .environmentKey
        )
        provider.environmentKeyName = "MY_KEY"
        provider.models = [ModelConfiguration(slug: "only", displayName: "Only")]
        let draft = ProviderDraft(provider: provider)

        // The gate sends the user through the one-time key sheet instead of
        // using a stored one.
        let verdict = app.autoReviewVerdict(draft: draft, credential: app.autoReviewCredential(for: draft))
        XCTAssertFalse(verdict.canScan)
        XCTAssertTrue(verdict.canStartOneTimeKeyEntry)

        app.startAutoReviewScan(draft: draft, oneTimeKey: "sk-once")
        await waitForScan(app)
        XCTAssertEqual(app.autoReviewState.results.first?.status, .supported)

        // The key is nowhere in the persisted configuration.
        let data = try Data(contentsOf: CodexPaths(codexHome: home).appConfiguration)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("sk-once"), "a one-time key must never be written to disk")
    }
}
