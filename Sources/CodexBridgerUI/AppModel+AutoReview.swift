import Foundation
import SwiftUI
import CodexBridgerCore

/// The 一键检测 lifecycle owned by AppModel.
///
/// The one-time key lives here and nowhere else: it is used to build the probe
/// request, then dropped when the run ends. It never enters the configuration,
/// the draft, or the persisted scan cache.
@MainActor
public final class AutoReviewScanState: ObservableObject {

    public enum Phase: Equatable {
        case idle
        case scanning
        case cancelled
    }

    @Published public private(set) var phase: Phase = .idle
    /// Slugs probed so far, in input order, with their outcome.
    @Published public private(set) var progress: [AutoReviewProbeOutcome] = []
    @Published public private(set) var total: Int = 0
    /// Set when the run finished; the results list reads from here.
    @Published public private(set) var results: [AutoReviewProbeOutcome] = []
    /// Non-nil while the env_key / command one-time key sheet is open.
    @Published public var oneTimeKeyInput: String = ""
    @Published public var isOneTimeKeySheetPresented = false
    /// Credential-less providers need no sheet.
    @Published public var oneTimeKeyError: String?

    public init() {}

    public var isScanning: Bool { phase == .scanning }

    public func begin(slugCount: Int) {
        phase = .scanning
        progress = []
        total = slugCount
        results = []
    }

    public func record(_ outcome: AutoReviewProbeOutcome) {
        progress.append(outcome)
    }

    public func finish(_ outcomes: [AutoReviewProbeOutcome]) {
        phase = .idle
        results = outcomes
        progress = outcomes
        total = outcomes.count
        oneTimeKeyInput = ""
    }

    public func cancel() {
        phase = .cancelled
        progress = []
        results = []
        oneTimeKeyInput = ""
        phase = .idle
    }

    public func discardResults() {
        results = []
        progress = []
    }
}

/// AppModel-side wiring for the 自动审批模型 section.
@MainActor
public extension AppModel {

    /// The gate verdict for the draft being edited.
    func autoReviewVerdict(
        draft: ProviderDraft,
        credential: AutoReviewGate.Credential
    ) -> AutoReviewGate.Verdict {
        AutoReviewGate.availability(
            modelSlugs: draft.provider.models.map { $0.slug },
            credential: credential,
            cache: configuration.autoReviewScans[draft.provider.id]
        )
    }

    /// Which credential path the current draft implies for probing.
    func autoReviewCredential(for draft: ProviderDraft) -> AutoReviewGate.Credential {
        switch draft.provider.credentialMode {
        case .none:
            return .notRequired
        case .bearerToken:
            return draft.provider.bearerToken
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .missing : .ready
        case .environmentKey, .command:
            return .needsOneTimeKey
        }
    }

    /// Builds the probe request for a draft. The one-time key, when given,
    /// overrides nothing that is persisted: it is used for this run only.
    func autoReviewRequest(
        for draft: ProviderDraft,
        oneTimeKey: String?
    ) -> AutoReviewProbeRequest {
        let provider = draft.provider
        let bearer: String?
        switch provider.credentialMode {
        case .bearerToken:
            bearer = provider.bearerToken
        case .environmentKey, .command:
            bearer = oneTimeKey
        case .none:
            bearer = nil
        }
        return AutoReviewProbeRequest(
            baseURL: provider.baseURL,
            bearerToken: bearer,
            httpHeaders: provider.httpHeaders,
            queryParams: provider.queryParams,
            modelSlug: provider.models.first?.slug ?? "",
            // Responses first, the shape Codex itself uses; chat/completions
            // remains the fallback for a proxy that lacks the Responses wire.
            wire: .responses,
            strictOverrides: configuration.autoReviewStrictOverrides,
            timeout: 60
        )
    }


    /// Starts a scan. Cancels any run in flight first, then probes every model
    /// of the draft, stores the result in the configuration, and saves.
    func startAutoReviewScan(draft: ProviderDraft, oneTimeKey: String?) {
        autoReviewState.cancel()
        let slugs = draft.provider.models.map { $0.slug }
        guard !slugs.isEmpty else { return }
        let request = autoReviewRequest(for: draft, oneTimeKey: oneTimeKey)
        autoReviewState.begin(slugCount: slugs.count)
        let state = autoReviewState
        let providerID = draft.provider.id
        Task {
            let prober = self.autoReviewProberFactory()
            let outcomes: [AutoReviewProbeOutcome]
            do {
                outcomes = try await prober.probeAll(request, slugs: slugs)
            } catch {
                // Cancelled or transport-wide failure: keep whatever rows made
                // it out so the user can see partial progress.
                outcomes = state.progress
            }
            state.finish(outcomes)
            configuration.autoReviewScans[providerID] = AutoReviewScanCache(
                providerID: providerID,
                slugs: slugs,
                scannedAt: Date(),
                outcomes: outcomes
            )
            persist()
        }
    }

    /// Stores the chosen reviewer slug into the draft. No scan needed: manual
    /// entry is the fallback that always works.
    func setAutoReviewOverride(on draft: ProviderDraft, slug: String?) -> ProviderDraft {
        var updated = draft
        updated.provider.autoReviewModelOverride = slug
        return updated
    }
}
