import Foundation
// This file is compiled together with Sources/CodexBridgerCore by
// scripts/generate-examples.sh. It exercises the real activation path so the
// committed example files are genuinely produced by CodexBridger, not hand written.

let arguments = Array(CommandLine.arguments.dropFirst())

func value(for flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

let outPath = value(for: "--out") ?? "docs/examples"
let root = URL(fileURLWithPath: outPath, isDirectory: true)
let paths = CodexPaths(codexHome: root)

try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

var provider = ProviderConfiguration(
    id: "demo",
    name: "示例提供商",
    baseURL: "https://api.example.com/v1",
    credentialMode: .bearerToken,
    requiresOpenAIAuth: true,
    bearerToken: "sk-example-token",
    models: [
        ModelConfiguration(
            slug: "demo-large",
            displayName: "Demo Large",
            modelDescription: "示例大模型",
            contextWindow: 200_000,
            maxContextWindow: 200_000,
            supportedReasoningEfforts: [.low, .medium, .high, .xhigh],
            defaultReasoningEffort: .high,
            priority: 1
        ),
        ModelConfiguration(
            slug: "demo-small",
            displayName: "Demo Small",
            modelDescription: "示例小模型",
            contextWindow: 64_000,
            maxContextWindow: 64_000,
            supportedReasoningEfforts: [.low, .medium],
            defaultReasoningEffort: .medium,
            priority: 2
        )
    ]
)
provider.queryParams = ["api-version": "2025-04-01"]
provider.httpHeaders = ["X-Example-Header": "example-value"]
provider.requestMaxRetries = 3

let configuration = CodexBridgerConfiguration(
    providers: [provider],
    activeProviderID: "demo",
    activeModelSlug: "demo-large",
    modelReasoningEffort: .xhigh
)

// A fixed timestamp keeps the committed backups reproducible.
let fixed = Date(timeIntervalSince1970: 1_791_000_000)
let writer = CodexConfigWriter(
    paths: paths,
    templateSource: StaticCatalogTemplate(),
    now: { fixed }
)

// A pre-existing config and auth file, so the example also demonstrates backups.
let existingConfig = [
    "approval_policy = \"on-request\"",
    "sandbox_mode = 'workspace-write'",
    "",
    "[features]",
    "goals = true"
].joined(separator: "\n") + "\n"
let existingAuth = "{\"OPENAI_API_KEY\": \"sk-old-value\"}\n"

try existingConfig.write(to: paths.configTOML, atomically: true, encoding: .utf8)
try existingAuth.write(to: paths.authJSON, atomically: true, encoding: .utf8)
try ConfigurationStore(paths: paths).save(configuration)

do {
    let result = try writer.activate(
        provider: provider,
        model: provider.models[0],
        configuration: configuration
    )
    print("示例已生成到 " + root.path)
    print("模板来源: " + result.templateSourceDescription)
    for url in [result.configURL, result.authURL, result.catalogURL] {
        print("  " + url.path)
    }
    if let backup = result.backupConfigURL { print("  备份: " + backup.lastPathComponent) }
    if let backup = result.backupAuthURL { print("  备份: " + backup.lastPathComponent) }
    let resolver = CatalogTemplateResolver(preferredSlug: configuration.catalogTemplateSlug)
    print("在本机运行时模板来源会是: " + resolver.sourceDescription)
    for warning in result.warnings { print("提示: " + warning) }
} catch {
    FileHandle.standardError.write(Data(("生成失败: " + error.localizedDescription + "\n").utf8))
    exit(1)
}
