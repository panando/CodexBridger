import Foundation

/// Decides whether activating a provider is a destructive change that the user has to
/// confirm first.
///
/// Codex keeps exactly one active provider, so activating replaces whatever the user was
/// using. Replacing a working provider by accident leaves Codex pointing at something
/// that may not even be running, and the user sees only "ChatGPT 坏了". This makes that
/// swap an explicit decision instead of a silent side effect.
public enum ActivationGuard {

    public struct Assessment: Equatable, Sendable {
        /// True when the activation would replace a different active provider.
        public let requiresConfirmation: Bool
        /// The provider Codex currently uses, when it differs from the target.
        public let replacedProviderID: String?
        public let title: String
        /// Empty when no confirmation is needed.
        public let message: String
        public let confirmTitle: String
        /// Non-blocking problems worth showing before the write.
        public let warnings: [String]

        public init(
            requiresConfirmation: Bool,
            replacedProviderID: String?,
            title: String,
            message: String,
            confirmTitle: String,
            warnings: [String]
        ) {
            self.requiresConfirmation = requiresConfirmation
            self.replacedProviderID = replacedProviderID
            self.title = title
            self.message = message
            self.confirmTitle = confirmTitle
            self.warnings = warnings
        }
    }

    public static func assess(
        currentProviderID: String?,
        targetProviderID: String,
        targetName: String,
        targetBaseURL: String = "",
        managedProviderIDs: Set<String> = []
    ) -> Assessment {
        let warnings = baseURLWarnings(targetBaseURL)
        // An empty string means Codex has no provider set; only a real, different id counts.
        let current = (currentProviderID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Moving between two providers this app manages is not a takeover, so it must not ask.
        // A config naming a provider we do not manage is the foreign one that needs backing up.
        if managedProviderIDs.contains(current) {
            return Assessment(
                requiresConfirmation: false,
                replacedProviderID: nil,
                title: "",
                message: "",
                confirmTitle: "",
                warnings: warnings
            )
        }
        guard !current.isEmpty, current != targetProviderID else {
            return Assessment(
                requiresConfirmation: false,
                replacedProviderID: nil,
                title: "",
                message: "",
                confirmTitle: "",
                warnings: warnings
            )
        }
        let displayName = targetName.isEmpty ? targetProviderID : targetName
        return Assessment(
            requiresConfirmation: true,
            replacedProviderID: current,
            title: "切换 ChatGPT 正在使用的提供商？",
            message: "ChatGPT 当前使用 " + current + "，激活后将切换为 " + displayName
                + "（" + targetProviderID + "）。写入前会自动备份现有的 config.toml 和 auth.json。",
            confirmTitle: "切换并写入",
            warnings: warnings
        )
    }

    /// Flags configuration that will produce a Codex that cannot reach anything.
    static func baseURLWarnings(_ rawBaseURL: String) -> [String] {
        let baseURL = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseURL.isEmpty {
            return ["没有填写 base_url，写进配置之前请先补上。"]
        }
        guard let url = URL(string: baseURL), let host = url.host?.lowercased() else {
            return ["base_url 不是一个合法的网址：" + baseURL]
        }
        let loopbackHosts = ["127.0.0.1", "localhost", "::1", "0.0.0.0"]
        if loopbackHosts.contains(host) {
            return ["base_url 指向本机（" + host + "），只有本地服务运行时 ChatGPT 才能用。"]
        }
        return []
    }
}
