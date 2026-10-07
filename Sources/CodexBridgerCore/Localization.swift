import Foundation

/// The language the interface is drawn in.
public enum InterfaceLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case chinese
    case english

    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

/// A tiny lookup table keyed by the Chinese source string.
///
/// Keying on the Chinese text rather than an invented identifier means an untranslated string
/// falls back to readable Chinese instead of showing a bare key, so partial coverage degrades
/// gracefully and a translation can be added one line at a time.
public enum Localization {

    /// Resolves a source string for a language.
    public static func text(_ source: String, language: InterfaceLanguage) -> String {
        switch resolved(language) {
        case .english: return english[source] ?? source
        case .chinese, .system: return source
        }
    }

    /// Turns a `system` preference into a concrete language using the usual order.
    public static func resolved(
        _ language: InterfaceLanguage,
        preferred: [String] = Locale.preferredLanguages
    ) -> InterfaceLanguage {
        guard language == .system else { return language }
        for identifier in preferred {
            let lowered = identifier.lowercased()
            if lowered.hasPrefix("zh") { return .chinese }
            if lowered.hasPrefix("en") { return .english }
        }
        return .chinese
    }

    /// Localises a generated warning, which may carry a value.
    ///
    /// These come from the activation guard rather than from a view, and they embed a host name or
    /// a URL, so a plain lookup table cannot cover them. The shapes are few and defined in one
    /// place, so they are matched by prefix and rebuilt in the target language.
    public static func warning(_ message: String, language: InterfaceLanguage) -> String {
        guard resolved(language) == .english else { return message }
        if message.hasPrefix("没有填写 base_url") {
            return "No base_url yet. Add one before this is written to the configuration."
        }
        if message.hasPrefix("base_url 不是一个合法的网址") {
            let value = message.components(separatedBy: "：").last ?? ""
            return "base_url is not a valid address: " + value
        }
        if message.hasPrefix("base_url 指向本机") {
            let host = message
                .components(separatedBy: "（").last?
                .components(separatedBy: "）").first ?? ""
            return "base_url points at this machine (" + host
                + "); ChatGPT can only use it while a local service is running."
        }
        return message
    }

    /// English strings, keyed by the Chinese source.
    public static let english: [String: String] = [
        // Window and navigation
        "模型提供商": "Providers",
        "新建提供商": "New provider",
        "常用云服务": "Cloud services",
        "自定义": "Custom",
        "聚合平台": "Aggregators",
        "其它": "Other",
        "还没有提供商": "No providers yet",
        "使用中": "In use",
        "当前已激活": "Currently active",
        "还没填地址": "No address yet",
        "模型名需要你自己填": "You will need to enter the model name",
        "ChatGPT 正在使用这个提供商": "ChatGPT is using this provider",

        // Action bar
        "添加": "Add",
        "删除": "Delete",
        "重置": "Revert",
        "取消": "Cancel",
        "保存": "Save",
        "保存中…": "Saving…",
        "启用": "Activate",
        "更新配置": "Update configuration",
        "把这份配置写进 ChatGPT": "Write this configuration into ChatGPT",
        "需要先保存": "Save first",
        "需要至少一个模型": "At least one model is required",
        "先解决表单里的错误": "Fix the errors in the form first",
        "ChatGPT 正在用它；点这里把当前设置重新写进 config.toml 和模型参数文件":
            "ChatGPT is using it; this rewrites config.toml and the model catalogue from the "
            + "current settings",

        // Sections
        "提供商信息": "Provider",
        "认证": "Credentials",
        "模型配置": "Models",
        "模型推理": "Model reasoning",
        "添加模型": "Add model",
        "从文件导入": "Import from file",
        "从模型参数文件导入": "Import from a model catalogue file",

        // Fields
        "名称": "Name",
        "标识符": "Identifier",
        // Deliberately short: the label column is 100pt and "Credential mode" was truncated
        // to "Credential…" in the running app.
        "认证方式": "Credential",
        "模型 ID": "Model ID",
        "显示名称": "Display name",
        "描述": "Description",
        "上下文窗口": "Context window",
        "最大上下文": "Max context",
        "可用推理强度": "Reasoning levels",
        "默认推理强度": "Default reasoning",
        "模型列表": "Model list",
        "排序": "Priority",
        "排序 priority": "Priority",

        // Settings
        "设置": "Settings",
        "通用": "General",
        "语言": "Language",
        "界面语言": "Interface language",
        "关于": "About",
        "备份": "Backups",
        "查看备份": "View backups",
        "版本": "Version",
        "打开备份文件夹": "Open backup folder",
        "刷新": "Refresh",
        "还没有备份文件": "No backups yet",
        "备份文件": "Backup files",
        "文件大小": "Size",
        "修改时间": "Modified",

        // Detail pane, section by section
        "ChatGPT 当前状态": "Current ChatGPT state",
        "模型参数模板": "Model parameter template",
        "上下文": "Context",
        "标识": "Identity",
        "目录": "Directory",
        "参数": "Parameters",
        "推理强度": "Reasoning effort",
        "工作目录": "Working directory",
        "命令": "Command",
        "当前可用来源": "Available sources",
        "提示说明": "Notes",
        "模板 slug": "Template slug",
        "环境变量名": "Environment variable",
        "超时 (ms)": "Timeout (ms)",

        // Welcome screen
        "CodexBridger 能做什么？": "What CodexBridger does",
        "写入 ChatGPT 配置": "Writes your ChatGPT configuration",
        "生成 config.toml、auth.json 与模型目录文件，打开 ChatGPT 即可使用":
            "Creates config.toml, auth.json and the model catalogue, ready for ChatGPT to use",
        "仅写入官方支持的字段": "Only writes supported fields",
        "每个参数都对照 ChatGPT 官方配置参考，不写入未经支持的字段":
            "Every setting follows the official ChatGPT configuration reference; nothing else is written",
        "内置常见服务商预设": "Presets for common providers",
        "DeepSeek、Moonshot、MiniMax、智谱 GLM、OpenRouter 可直接选择，也可自定义":
            "Pick DeepSeek, Moonshot, MiniMax, Zhipu GLM or OpenRouter, or define your own",
        "每个模型独立设置": "Each model configured separately",
        "上下文窗口、最大上下文、推理强度与显示状态，均可逐模型配置":
            "Context window, maximum context, reasoning effort and visibility are set per model",
        "修改前自动备份": "Backs up before changing anything",
        "改动 config.toml 或 auth.json 之前，先保存原文件副本":
            "The existing config.toml or auth.json is copied aside before it is replaced",

        // Toggles and notices
        "跟随系统": "Follow system",
        "当作 OpenAI 官方端点处理": "Treat as the official OpenAI endpoint",
        "让第三方模型轻松接入 ChatGPT": "Brings third-party models into ChatGPT with ease",
        "CodexBridger 只写入 ChatGPT 官方文档支持的字段，并把每次替换前的原文件备份到 backup/config-backup。":
            "CodexBridger only writes fields the official ChatGPT documentation supports, and backs "
            + "up the previous file to backup/config-backup before every replacement.",
    ]
}