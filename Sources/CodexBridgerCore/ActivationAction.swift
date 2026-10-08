import Foundation

/// Whether the action bar's primary button can be used, and what it should say.
///
/// The contract, as the user restated it on 2026-10-08:
///
/// * 保存 writes this app's own settings file. It touches nothing ChatGPT reads and takes no
///   backup, because it is not replacing anybody's file.
/// * 启用 applies the saved provider: the model parameter file, config.toml and auth.json, with
///   the previous files backed up first, every time.
/// * Once a provider is the one in use *and* the files already hold exactly these settings,
///   there is nothing left to apply, so the button goes flat. Saving a change brings it back.
///
/// The last point replaces the 1.1.0 rule, which kept the button usable for the active provider
/// at all times because disabling it had once left a changed provider with no way to reach the
/// files. That trap is still avoided: it is precisely "changed since it was applied" that makes
/// the button usable again, so the path out exists while the no-op is gone.
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

    /// The action is unavailable until the form is in a state where applying it means something.
    ///
    /// `isAlreadyPublished` is the new input: it says the files already hold this provider, so
    /// pressing 启用 would write the same thing again and take a backup on the way.
    public static func availability(
        hasModels: Bool,
        isDirty: Bool,
        hasErrors: Bool,
        isAlreadyActive: Bool,
        isAlreadyPublished: Bool
    ) -> Availability {
        // One name for one action, by the same ruling: it applies this provider to ChatGPT.
        let title = "启用"
        if hasErrors {
            return Availability(isEnabled: false, title: title, help: "先解决表单里的错误")
        }
        if isDirty {
            return Availability(isEnabled: false, title: title, help: "需要先保存")
        }
        if !hasModels {
            return Availability(isEnabled: false, title: title, help: "需要至少一个模型")
        }
        if isAlreadyActive, isAlreadyPublished {
            return Availability(
                isEnabled: false,
                title: title,
                help: "ChatGPT 正在用它，文件里就是这套设置；改完保存后这里会重新可用"
            )
        }
        if isAlreadyActive {
            return Availability(
                isEnabled: true,
                title: title,
                help: "设置改过了，还没写进 ChatGPT；点这里重新写入（写入前先备份）"
            )
        }
        return Availability(
            isEnabled: true,
            title: title,
            help: "把这套设置写进 ChatGPT（写入前先备份）"
        )
    }
}
