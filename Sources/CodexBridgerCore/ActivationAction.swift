import Foundation

/// Whether the action bar's primary button can be used, and what it should say.
///
/// Kept out of the view so the rule is testable. The rule matters: the button is the only path
/// that rewrites config.toml and the model parameter file, so a state that disables it for the
/// provider ChatGPT is already using leaves that provider's settings unreachable.
public enum ActivationAction {

    public struct Availability: Equatable, Sendable {
        public var isEnabled: Bool
        /// Interface source string; the view localises it.
        public var title: String
        /// Why the button is in this state, shown as a tooltip.
        public var help: String

        public init(isEnabled: Bool, title: String, help: String) {
            self.isEnabled = isEnabled
            self.title = title
            self.help = help
        }
    }

    /// The action is unavailable until the form is in a state where writing it means something.
    ///
    /// A provider that is already active is *not* a reason to disable the button: writing it again
    /// is exactly how a settings change reaches ChatGPT, and how a renamed or re-addressed
    /// provider is re-published.
    public static func availability(
        hasModels: Bool,
        isDirty: Bool,
        hasErrors: Bool,
        isAlreadyActive: Bool
    ) -> Availability {
        let title = isAlreadyActive ? "更新配置" : "启用"
        if hasErrors {
            return Availability(isEnabled: false, title: title, help: "先解决表单里的错误")
        }
        if isDirty {
            return Availability(isEnabled: false, title: title, help: "需要先保存")
        }
        if !hasModels {
            return Availability(isEnabled: false, title: title, help: "需要至少一个模型")
        }
        if isAlreadyActive {
            return Availability(
                isEnabled: true,
                title: title,
                help: "ChatGPT 正在用它；点这里把当前设置重新写进 config.toml 和模型参数文件"
            )
        }
        return Availability(isEnabled: true, title: title, help: "把这份配置写进 ChatGPT")
    }
}
