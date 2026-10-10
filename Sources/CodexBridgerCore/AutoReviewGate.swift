import Foundation

/// The pure decision behind the 自动审批模型 section: which paths are open.
///
/// Keeping it out of the view means every rule is a test case instead of a
/// screenshot: no models or no usable key disables 一键检测, the dropdown only
/// offers models a fresh scan proved, and manual entry never goes away.
public enum AutoReviewGate {

    /// How a credential is available for probing right now.
    public enum Credential: Equatable, Sendable {
        /// A stored bearer token is present, or the provider needs none.
        case ready
        /// The provider needs a key and none is available yet.
        case missing
        /// env_key / command mode: the user must type a one-time key first.
        case needsOneTimeKey
        /// The provider takes no credential at all.
        case notRequired
    }

    public struct Verdict: Equatable, Sendable {
        /// 一键检测 can start now.
        public var canScan: Bool
        /// Why it cannot, when it cannot. Empty when it can.
        public var scanHint: String
        /// env_key / command mode: the one-time key sheet can open.
        public var canStartOneTimeKeyEntry: Bool
        /// The dropdown of passing models is usable.
        public var canPickFromScan: Bool
        /// Models a scan proved, in scan order.
        public var candidateSlugs: [String]
        /// A cached result exists but no longer matches the model list.
        public var cacheIsStale: Bool
        /// Manual entry of any slug. Always true.
        public var canEnterManually: Bool

        public init(
            canScan: Bool,
            scanHint: String,
            canStartOneTimeKeyEntry: Bool,
            canPickFromScan: Bool,
            candidateSlugs: [String],
            cacheIsStale: Bool,
            canEnterManually: Bool
        ) {
            self.canScan = canScan
            self.scanHint = scanHint
            self.canStartOneTimeKeyEntry = canStartOneTimeKeyEntry
            self.canPickFromScan = canPickFromScan
            self.candidateSlugs = candidateSlugs
            self.cacheIsStale = cacheIsStale
            self.canEnterManually = canEnterManually
        }
    }

    public static func availability(
        modelSlugs: [String],
        credential: Credential,
        cache: AutoReviewScanCache? = nil
    ) -> Verdict {
        var scanHint = ""
        var canScan = false
        switch credential {
        case .ready, .notRequired:
            canScan = !modelSlugs.isEmpty
            if modelSlugs.isEmpty {
                scanHint = "先在「模型配置」里添加模型，检测才有对象"
            }
        case .missing:
            scanHint = "先填写 API Key，检测才能带上凭据"
        case .needsOneTimeKey:
            scanHint = "这个认证方式每次检测需要输入一次性 Key（不会保存）"
        }

        let stale = cache?.isStale(currentSlugs: modelSlugs) ?? false
        let candidates = (stale ? [] : cache?.supportedSlugs) ?? []
        let canPick = !candidates.isEmpty

        return Verdict(
            canScan: canScan,
            scanHint: scanHint,
            canStartOneTimeKeyEntry: credential == .needsOneTimeKey && !modelSlugs.isEmpty,
            canPickFromScan: canPick,
            candidateSlugs: candidates,
            cacheIsStale: cache != nil && stale,
            canEnterManually: true
        )
    }
}
