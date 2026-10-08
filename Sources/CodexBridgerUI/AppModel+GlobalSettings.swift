import Foundation
import CodexBridgerCore

/// The global settings screen's behaviour.
///
/// Kept out of `AppModel.swift` so the file that owns the window's state does not also own this
/// screen's rules. Everything that touches the file goes through the Core reader, draft and
/// writer, so nothing here re-implements a rule that is already tested.
@MainActor
extension AppModel {

    /// Reads config.toml into the screen and forgets any pending edit.
    public func loadGlobalSettings() {
        let text = (try? String(contentsOf: paths.configTOML, encoding: .utf8)) ?? ""
        let states = GlobalSettingsReader.states(in: text)
        globalSettingsStates = states
        globalSettingsDraft = GlobalSettingsDraft(loaded: states)
        globalSettingsConflicts = []
        globalSettingsNotice = nil
    }

    public func setGlobalSetting(_ value: SettingValue, for key: String) {
        globalSettingsDraft.set(value, for: key)
        clearConflictState()
    }

    public func clearGlobalSetting(_ key: String) {
        globalSettingsDraft.clear(key)
        clearConflictState()
    }

    public func resetGlobalSettings() {
        globalSettingsDraft.reset()
        clearConflictState()
    }

    public var globalSettingsIsDirty: Bool { globalSettingsDraft.isDirty }

    /// The value the screen shows for a key: the pending edit if there is one, else the file's.
    public func globalSettingPendingChange(for key: String) -> SettingChange? {
        globalSettingsDraft.changes[key]
    }

    /// Writes the pending edits, having first re-read the file.

    /// A key somebody else changed stops the whole write: nothing is written and nothing is
    /// backed up until the user decides. `acceptingConflicts` is that decision.
    public func updateGlobalConfiguration(acceptingConflicts: Bool = false) {
        let writer = GlobalSettingsWriter(paths: paths)
        do {
            let result = try writer.write(globalSettingsDraft, acceptingConflicts: acceptingConflicts)
            globalSettingsConflicts = []
            if result.writtenKeys.isEmpty {
                globalSettingsNotice = GlobalSettingsNotice(
                    kind: .success, message: t("没有需要更新的内容。")
                )
            } else {
                globalSettingsNotice = GlobalSettingsNotice(
                    kind: .success,
                    message: updatedSettingsMessage(
                        writtenCount: result.writtenKeys.count,
                        backupName: result.backupURL?.lastPathComponent
                    )
                )
            }
            if !result.warnings.isEmpty {
                globalSettingsNotice = GlobalSettingsNotice(
                    kind: .warning, message: result.warnings.joined(separator: " ")
                )
            }
            // Show what the file holds now, not what we meant to write.
            reloadGlobalSettingsKeepingNotice()
        } catch let error as GlobalSettingsWriteError {
            if case let .conflictingKeys(conflicts) = error {
                globalSettingsConflicts = conflicts
                globalSettingsNotice = GlobalSettingsNotice(
                    kind: .warning,
                    message: t("这些参数刚被别的程序改了，没有写入任何东西。")
                )
            } else {
                globalSettingsNotice = GlobalSettingsNotice(
                    kind: .failure, message: error.localizedDescription
                )
            }
        } catch {
            globalSettingsNotice = GlobalSettingsNotice(
                kind: .failure, message: error.localizedDescription
            )
        }
    }

    /// The conflict prompt's second choice: give up on the keys somebody else touched and write
    /// whatever is left.
    public func dropConflictingChanges() {
        globalSettingsDraft.discardChanges(for: globalSettingsConflicts.map(\.key))
        globalSettingsConflicts = []
        updateGlobalConfiguration()
    }

    /// The success notice, built from one whole sentence per case.
    ///
    /// It used to be translated fragments joined with `+`, which works only while every language
    /// puts the count, the punctuation and the file name in the same order as Chinese does. Written
    /// as a sentence with `{n}` and `{file}` in it, the word order belongs to the language and the
    /// substitution is checkable (see `GlobalSettingsModelTests`).
    private func updatedSettingsMessage(writtenCount: Int, backupName: String?) -> String {
        let one = writtenCount == 1
        let template = backupName.map { _ in
            one ? t("已更新 1 个参数，原文件已备份为 {file}。")
                : t("已更新 {n} 个参数，原文件已备份为 {file}。")
        } ?? (one ? t("已更新 1 个参数。") : t("已更新 {n} 个参数。"))
        return template
            .replacingOccurrences(of: "{n}", with: String(writtenCount))
            .replacingOccurrences(of: "{file}", with: backupName ?? "")
    }

    private func clearConflictState() {
        globalSettingsConflicts = []
        globalSettingsNotice = nil
    }

    private func reloadGlobalSettingsKeepingNotice() {
        let text = (try? String(contentsOf: paths.configTOML, encoding: .utf8)) ?? ""
        let states = GlobalSettingsReader.states(in: text)
        globalSettingsStates = states
        globalSettingsDraft = GlobalSettingsDraft(loaded: states)
    }
}
