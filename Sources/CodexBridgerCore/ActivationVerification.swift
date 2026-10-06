import Foundation

/// Checks that a completed write actually landed in the files Codex reads.
///
/// The write path writes and reports success. This re-reads what is on disk and compares it
/// with what was requested, so "saved" means "verified", not "the call returned". It checks
/// the file layer only: it does not prove the third-party service is reachable.
public enum ActivationVerification {

    /// Returns one message per problem found. Empty means the write is consistent.
    public static func warnings(
        expectedProviderID: String,
        expectedModelSlug: String,
        snapshot: CodexConfigSnapshot
    ) -> [String] {
        var warnings: [String] = []
        if !snapshot.configExists {
            warnings.append("config.toml 写入后没有找到")
        }
        if snapshot.modelProviderID != expectedProviderID {
            warnings.append(
                "config.toml 里的 model_provider 是 "
                    + (snapshot.modelProviderID ?? "空") + "，期望是 " + expectedProviderID
            )
        }
        if snapshot.modelSlug != expectedModelSlug {
            warnings.append(
                "config.toml 里的 model 是 "
                    + (snapshot.modelSlug ?? "空") + "，期望是 " + expectedModelSlug
            )
        }
        if (snapshot.modelCatalogJSON ?? "").isEmpty {
            warnings.append("config.toml 里没有 model_catalog_json")
        }
        if !snapshot.catalogFileExists {
            warnings.append("模型参数文件写入后没有找到")
        }
        if !snapshot.providerIDs.contains(expectedProviderID) {
            warnings.append("config.toml 里没有 [model_providers." + expectedProviderID + "] 段落")
        }
        return warnings
    }
}
