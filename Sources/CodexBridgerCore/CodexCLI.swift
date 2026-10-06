import Foundation

/// Locates the Codex CLI and reads its bundled model catalog.
///
/// The bundled catalog is the highest-fidelity template source for a generated
/// model catalog: it is produced by the same Codex build the user runs, so every
/// field it carries provably satisfies that build schema. CodexBridger treats it
/// as an optional enhancement and falls back to a verified built-in template.
public struct CodexCLI: Sendable {
    public let executableURL: URL

    public init(executableURL: URL) {
        self.executableURL = executableURL
    }

    /// Known install locations, most specific first. The ChatGPT desktop app ships
    /// a Codex CLI inside its bundle, which is where Codex lives on a stock macOS
    /// install.
    public static func candidateURLs(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [URL] {
        var paths: [String] = []
        if let override = environment["CODEX_CLI_PATH"], !override.isEmpty {
            paths.append(override)
        }
        paths.append("/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        paths.append("/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        paths.append("/Applications/ChatGPT.app/Contents/Resources/codex")
        paths.append("/opt/homebrew/bin/codex")
        paths.append("/usr/local/bin/codex")
        let home = fileManager.homeDirectoryForCurrentUser
        // Most of these exist because a window opened from Finder inherits a minimal PATH
        // (`/usr/bin:/bin:/usr/sbin:/sbin`), so a CLI installed by a version manager is invisible
        // to the PATH lookup below even though the user can run `codex` in their terminal. Each
        // entry is a fixed location that a node or python version manager uses on macOS.
        let relativeCandidates = [
            ".local/bin/codex",
            ".nvm/current/bin/codex",
            ".volta/bin/codex",
            ".bun/bin/codex",
            ".cargo/bin/codex",
            ".asdf/shims/codex",
            ".npm-global/bin/codex",
            "Library/pnpm/codex",
            "n/bin/codex",
            ".nodenv/shims/codex",
            ".nodenv/bin/codex",
            "Library/Application Support/fnm_multishells",
        ]
        for relative in relativeCandidates {
            paths.append(home.appendingPathComponent(relative).path)
        }
        // Homebrew puts node-installed binaries here, next to the Cellar links.
        paths.append("/opt/homebrew/lib/node_modules/.bin/codex")
        paths.append("/usr/local/lib/node_modules/.bin/codex")
        let pathEntries = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for entry in pathEntries where !entry.isEmpty {
            paths.append(entry + "/codex")
        }
        var seen = Set<String>()
        var result: [URL] = []
        for path in paths {
            guard seen.insert(path).inserted else { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            guard fileManager.isExecutableFile(atPath: path) else { continue }
            result.append(URL(fileURLWithPath: path))
        }
        return result
    }

    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> CodexCLI? {
        guard let first = candidateURLs(environment: environment, fileManager: fileManager).first else {
            return nil
        }
        return CodexCLI(executableURL: first)
    }

    public enum CLIError: Error, LocalizedError {
        case launchFailed(String)
        case nonZeroExit(Int32, String)
        case unparsableOutput

        public var errorDescription: String? {
            switch self {
            case let .launchFailed(message): return "无法启动 ChatGPT CLI: " + message
            case let .nonZeroExit(code, message): return "ChatGPT CLI 退出码 " + String(code) + ": " + message
            case .unparsableOutput: return "ChatGPT CLI 输出无法解析为 JSON"
            }
        }
    }

    /// Runs "codex debug models --bundled" and returns the parsed object.
    ///
    /// The pipe is drained before waiting for exit: the catalog is several hundred
    /// kilobytes, which is far more than a pipe buffer, so waiting first would
    /// deadlock.
    public func bundledCatalog(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> [String: Any] {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["debug", "models", "--bundled"]
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw CLIError.launchFailed(error.localizedDescription)
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.nonZeroExit(
                process.terminationStatus,
                String(data: errorOutput, encoding: .utf8) ?? ""
            )
        }
        guard let object = try? JSONSerialization.jsonObject(with: output) as? [String: Any] else {
            throw CLIError.unparsableOutput
        }
        return object
    }
}
