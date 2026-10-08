import Foundation

/// One config.toml parameter this screen shows.
///
/// Every key here is documented in the official Configuration Reference for config.toml,
/// and every one of them is also present in the ChatGPT-bundled Codex binary (measured
/// 2026-10-08: every key shown on this screen, 16-104 hits each). Nothing is invented.
public struct GlobalSetting: Equatable, Sendable {

    /// The control the key is drawn with.
    public enum Control: Equatable, Sendable {
        case toggle
        case choice([String])
        case integer
        case text
        case stringArray
    }

    /// Which collapsible section the key appears under.
    ///
    /// Two groups only, by the user's ruling of 2026-10-08: this page draws the approval and
    /// sandbox keys plus the two reasoning-visibility switches, and nothing else. Every key that
    /// left is recorded in `excluded` with its reason, so the accounting still covers all 78.
    public enum Group: String, Sendable, CaseIterable {
        case approvalsAndSandbox
        case reasoningVisibility

        /// Order the sections are drawn in.
        public static let displayOrder: [Group] = [.approvalsAndSandbox, .reasoningVisibility]

        /// The section heading, in the interface language.
        public var displayName: String {
            switch self {
            case .approvalsAndSandbox: return "审批与沙箱"
            case .reasoningVisibility: return "推理可见性"
            }
        }
    }

    public let key: String
    public let group: Group
    public let control: Control
    /// The explanation behind the ⓘ badge, in the source language (Chinese).
    ///
    /// It is the only place a key is explained, so it has to carry the whole job in a few lines:
    /// what the key decides, every value the control offers, and the documented default. A
    /// paragraph per key was tried and rejected (2026-10-08, eighth review) — the text is read
    /// once, in a popover, and length there is a cost, not thoroughness. `GlobalSettingsCatalogTests`
    /// caps the length so "thorough" cannot creep back in.
    ///
    /// The English entry for the same string opens with the official sentence verbatim (one word
    /// adapted: the reference says 「Codex」 and this interface must say ChatGPT, which the product
    /// naming test enforces) and then carries the same value-by-value gloss, so the English side
    /// stays checkable against `docs/reference/codex-config-reference.md`.
    public let detail: String

    public init(
        key: String,
        group: Group,
        control: Control,
        detail: String
    ) {
        self.key = key
        self.group = group
        self.control = control
        self.detail = detail
    }
}

/// A config.toml key that is known and deliberately kept off the screen.
///
/// It carries why, so a later reader does not have to guess whether the omission was a
/// decision or an oversight.
public struct ExcludedSetting: Equatable, Sendable {
    /// Why the key is off the screen. Separate from `GlobalSetting.Tier` because an
    /// excluded key has no control and therefore no editable/read-only distinction.
    public enum Tier: String, Sendable, CaseIterable {
        /// Known and deliberately not drawn.
        case hidden
        /// Deliberately not part of this screen at all.
        case omitted
    }

    public let key: String
    public let tier: Tier
    public let reason: String

    public init(key: String, tier: Tier, reason: String) {
        self.key = key
        self.tier = tier
        self.reason = reason
    }
}

/// Every config.toml key this app has an opinion about.
public enum GlobalSettingsCatalog {

    /// Keys this screen shows and may change — the same set, deliberately: a key the page draws
    /// is a key it may write, so there is no way to show something that cannot be edited.
    public static let settings: [GlobalSetting] = [
        GlobalSetting(
            key: "approval_policy",
            group: .approvalsAndSandbox,
            control: .choice(["on-request", "never"]),
            detail: "执行命令前要不要先停一下。"
                + "on-request：先问你（默认）；never：不问，直接执行。"
        ),
        GlobalSetting(
            key: "approvals_reviewer",
            group: .approvalsAndSandbox,
            control: .choice(["user", "auto_review"]),
            detail: "上一条拦下来的请示由谁审。"
                + "user：你自己看（默认）；auto_review：自动审查，不打扰你。"
        ),
        GlobalSetting(
            key: "sandbox_mode",
            group: .approvalsAndSandbox,
            control: .choice(["read-only", "workspace-write", "danger-full-access"]),
            detail: "能碰什么。"
                + "read-only：只能读；workspace-write：改工作目录；"
                + "danger-full-access：全放开，含联网。"
        ),
        GlobalSetting(
            key: "allow_login_shell",
            group: .approvalsAndSandbox,
            control: .toggle,
            detail: "命令要不要像你打开终端那样先读一遍 shell 配置（.zshrc 等）。默认打开。"
        ),
        GlobalSetting(
            key: "hide_agent_reasoning",
            group: .reasoningVisibility,
            control: .toggle,
            detail: "把模型思考的过程藏起来，终端和命令行输出都不显示。和下面那一项互不影响。"
        ),
        GlobalSetting(
            key: "show_raw_agent_reasoning",
            group: .reasoningVisibility,
            control: .toggle,
            detail: "把模型的原始推理原文显示出来（模型会输出才有）。"
        ),
    // SETTINGS-SLOT
    ]

    /// Keys known and deliberately not shown, with the reason.
    public static let excluded: [ExcludedSetting] = [
        ExcludedSetting(key: "agents", tier: .hidden,
                        reason: "多智能体设置，是复杂表，不在这一页。"),
        ExcludedSetting(key: "hooks", tier: .hidden,
                        reason: "生命周期钩子，是复杂表，不在这一页。"),
        ExcludedSetting(key: "instructions", tier: .hidden,
                        reason: "官方标注为 reserved for future use。"),
        // Ruling A, 2026-10-08: the same concept already has a home. The provider screen sets
        // context_window / max_context_window per model in the model catalog, and one global
        // number cannot be right for models whose real windows differ (262k, 500k, 1048k in
        // the user's own catalogs). Setting it in two places is what the exclusion list is for.
        ExcludedSetting(key: "model_context_window", tier: .omitted,
                        reason: "逐模型的上下文窗口由提供商界面管理（参数文件的 context_window / max_context_window），本页不重复设置。"),
        ExcludedSetting(key: "model_instructions_file", tier: .omitted,
                        reason: "值是 AGENTS.md 一类文件的路径，属于别的文件。"),
        ExcludedSetting(key: "experimental_compact_prompt_file", tier: .omitted,
                        reason: "值是提示词文件的路径，属于别的文件。"),
        ExcludedSetting(key: "project_doc_fallback_filenames", tier: .omitted,
                        reason: "管的是 AGENTS.md 的文件名，不是 config.toml 自己的参数。"),
        ExcludedSetting(key: "project_doc_max_bytes", tier: .omitted,
                        reason: "管的是 AGENTS.md 读多少字节，同上。"),
        ExcludedSetting(key: "background_terminal_max_timeout", tier: .omitted,
                        reason: "偏命令行的后台终端轮询。"),
        ExcludedSetting(key: "cli_auth_credentials_store", tier: .omitted,
                        reason: "偏命令行的凭据存放位置。"),
        ExcludedSetting(key: "mcp_oauth_credentials_store", tier: .omitted,
                        reason: "管的是凭据存放位置，与 auth.json 强耦合。"),
        ExcludedSetting(key: "oss_provider", tier: .omitted,
                        reason: "只在命令行 --oss 下有意义。"),
        ExcludedSetting(key: "tui", tier: .omitted,
                        reason: "终端界面专用。"),
        ExcludedSetting(key: "experimental_use_unified_exec_tool", tier: .omitted,
                        reason: "官方标注为 legacy，改用 features.unified_exec。"),
        ExcludedSetting(key: "disable_paste_burst", tier: .omitted,
                        reason: "终端界面专用。"),
        ExcludedSetting(key: "windows_wsl_setup_acknowledged", tier: .omitted,
                        reason: "Windows 专用。"),
        // 2026-10-08, second UI review: the page keeps two groups. The keys that left are
        // recorded here rather than deleted, so `allKeys` still accounts for all 78 documented
        // keys and a later reader can see this was a decision. None of them is ever written:
        // the writer only names a key the user changed on this page.
        ExcludedSetting(key: "model_auto_compact_token_limit", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "model_auto_compact_token_limit_scope", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "tool_output_token_limit", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "plan_mode_reasoning_effort", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "review_model", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "service_tier", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "web_search", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "personality", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "file_opener", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "notify", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "project_root_markers", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "developer_instructions", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "compact_prompt", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "mcp_optional_startup_grace_ms", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "check_for_update_on_startup", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "suppress_unstable_features_warning", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "chatgpt_base_url", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "openai_base_url", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "forced_login_method", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "forced_chatgpt_workspace_id", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "mcp_oauth_callback_port", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "mcp_oauth_callback_url", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "log_dir", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "sqlite_home", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        ExcludedSetting(key: "default_permissions", tier: .omitted,
                        reason: "用户裁定（2026-10-08）：本页只保留「审批与沙箱」与「推理可见性」两组，其余不显示。写入器不会碰它。"),
        // EXCLUDED-SLOT
    ]

    public static var hidden: [ExcludedSetting] { excluded.filter { $0.tier == .hidden } }
    public static var omitted: [ExcludedSetting] { excluded.filter { $0.tier == .omitted } }

    /// Every key the catalog accounts for, shown or excluded.
    public static var allKeys: Set<String> {
        Set(settings.map(\.key)).union(excluded.map(\.key))
    }

    /// Keys the provider screen and the activation flow already write. Excluded here so one
    /// key can only ever be changed from one place.
    public static let ownedByProviderFeature: Set<String> = [
        "model", "model_provider", "model_catalog_json", "model_reasoning_effort",
        "model_reasoning_summary", "model_verbosity", "model_supports_reasoning_summaries"
    ]

    /// Top-level keys that are TOML tables. This screen never reads or writes them, and the
    /// writer cannot name them.
    public static let tableKeys: Set<String> = [
        "analytics", "apps", "auto_review", "browser_use", "computer_use", "desktop",
        "features", "feedback", "history", "marketplaces", "mcp_servers", "memories",
        "model_providers", "notice", "otel", "permissions", "plugins", "projects",
        "sandbox_workspace_write", "shell_environment_policy", "skills", "tool_suggest",
        "tools", "windows"
    ]
}
