import Foundation

/// Acceptance check: does the real ChatGPT CLI accept every value this screen can write?
///
/// It renders each value through `GlobalSettingsWriter.render` — the same code the app writes
/// with — puts it in a throwaway config.toml, and asks `codex doctor --json` whether the config
/// loads. The discriminator is the `config.load` check, because an isolated home always fails
/// unrelated checks (no credentials).
///
/// Run via scripts/verify-global-settings.sh. Not part of the test suite: each doctor run does
/// network checks and takes about 18 seconds, whatever the value.
///
/// Modes:
///   (default)  every value the controls can produce — about 18 minutes
///   --quick    only the dropdown values, which are the ones with a fixed documented set; a
///              free-form number or text field can be typed to anything, so sampling it proves
///              little. About 8 minutes.
///   --list     print what would be checked, and stop
///   --limit N  check the first N cases only
///   --timeout S  per-case watchdog, default 45 (a healthy case takes about 18)
@main
struct VerifyGlobalSettings {

    struct Case {
        let key: String
        let rendered: String
        let shown: String
    }

    /// How long one case may take. A healthy run takes about 18 seconds (the CLI probes the
    /// network on every invocation and waits for those probes), so this only fires on a real hang.
    static var timeoutSeconds: Double = 45

    static func main() {
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else {
                return nil
            }
            return arguments[index + 1]
        }
        let limit = value(after: "--limit").flatMap(Int.init)
        if let seconds = value(after: "--timeout").flatMap(Double.init) { timeoutSeconds = seconds }

        let quick = arguments.contains("--quick")
        var all = cases(quick: quick)
        if let limit { all = Array(all.prefix(limit)) }

        if arguments.contains("--list") {
            for item in all { print(item.key + " = " + item.rendered) }
            print("cases: " + String(all.count)
                  + (quick ? "（--quick：只测下拉框的固定选项）" : "（全部取值）")
                  + "  预计耗时: 约 " + String(all.count * 18 / 60) + " 分钟（每次约 18 秒）")
            return
        }

        guard let cli = CodexCLI.locate() else {
            print("找不到 ChatGPT 的 codex 可执行文件，无法验证。")
            exit(2)
        }
        print("CLI: " + cli.executableURL.path)
        print("cases: " + String(all.count))
        fflush(stdout)

        var failures: [String] = []
        for (index, item) in all.enumerated() {
            let result = check(item, cli: cli)
            let mark = result.ok ? "PASS" : "FAIL"
            let line = mark + "  " + item.key + " = " + item.rendered
            print("[\(index + 1)/\(all.count)] " + line + (result.ok ? "" : "   <-- " + result.summary))
            fflush(stdout)
            if !result.ok { failures.append(line + "   (" + result.summary + ")") }
        }

        print("")
        if failures.isEmpty {
            print("全部通过：" + String(all.count) + " 个取值，官方 CLI 全部接受。")
        } else {
            print("失败 " + String(failures.count) + " / " + String(all.count) + "：")
            for failure in failures { print("  " + failure) }
            exit(1)
        }
    }

    /// Every value the controls can produce, with a representative sample where the control is
    /// free-form. `quick` keeps only the fixed sets.
    static func cases(quick: Bool) -> [Case] {
        var out: [Case] = []
        for setting in GlobalSettingsCatalog.settings {
            var isChoice = false
            if case .choice = setting.control { isChoice = true }
            if quick && !isChoice { continue }
            switch setting.control {
            case .toggle:
                for flag in [true, false] {
                    out.append(Case(
                        key: setting.key,
                        rendered: GlobalSettingsWriter.render(.flag(flag)),
                        shown: String(flag)
                    ))
                }
            case let .choice(values):
                for value in values {
                    out.append(Case(
                        key: setting.key,
                        rendered: GlobalSettingsWriter.render(.choice(value)),
                        shown: value
                    ))
                }
            case .integer:
                for number in sampleNumbers(for: setting.key) {
                    out.append(Case(
                        key: setting.key,
                        rendered: GlobalSettingsWriter.render(.number(number)),
                        shown: String(number)
                    ))
                }
            case .text:
                for text in sampleTexts(for: setting.key) {
                    out.append(Case(
                        key: setting.key,
                        rendered: GlobalSettingsWriter.render(.text(text)),
                        shown: text
                    ))
                }
            case .stringArray:
                for list in sampleLists(for: setting.key) {
                    out.append(Case(
                        key: setting.key,
                        rendered: GlobalSettingsWriter.render(.list(list)),
                        shown: list.joined(separator: ", ")
                    ))
                }
            }
        }
        return out
    }

    static func sampleNumbers(for key: String) -> [Int] {
        switch key {
        case "model_context_window", "model_auto_compact_token_limit", "tool_output_token_limit":
            return [1, 262_144]
        case "mcp_optional_startup_grace_ms":
            return [0, 1000]
        default:
            return [1]
        }
    }

    static func sampleTexts(for key: String) -> [String] {
        switch key {
        case "review_model": return ["gpt-5.5"]
        case "service_tier": return ["fast", "default"]
        case "compact_prompt": return ["Keep the summary short."]
        case "developer_instructions": return ["Prefer plain language."]
        default: return ["sample"]
        }
    }

    static func sampleLists(for key: String) -> [[String]] {
        switch key {
        case "notify": return [["/bin/echo", "done"], []]
        case "project_root_markers": return [[".git"], []]
        default: return [["a"]]
        }
    }

    static func check(_ item: Case, cli: CodexCLI) -> (ok: Bool, summary: String) {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cb-verify-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let text = item.key + " = " + item.rendered + "\n"
            try text.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        } catch {
            return (false, "could not seed the config: " + error.localizedDescription)
        }

        let process = Process()
        process.executableURL = cli.executableURL
        process.arguments = ["doctor", "--json"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        process.environment = environment
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return (false, "could not run the CLI") }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            usleep(200_000)
        }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(5)
            while process.isRunning && Date() < grace { usleep(200_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            return (false, "超过 " + String(Int(timeoutSeconds)) + " 秒没有返回（已终止）")
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()

        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let checks = object["checks"] as? [String: Any],
            let config = checks["config.load"] as? [String: Any],
            let status = config["status"] as? String
        else {
            return (false, "no machine-readable report")
        }
        return (status == "ok", (config["summary"] as? String) ?? status)
    }
}
