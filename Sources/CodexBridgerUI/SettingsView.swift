import SwiftUI
import AppKit
import CodexBridgerCore

/// The Settings window: language, About, and the backup files CodexBridger has written.
public struct SettingsView: View {
    @ObservedObject private var model: AppModel
    @State private var backups: [BackupFile] = []
    @State private var loadError: String?
    @State private var selection: SettingsTab

    /// Which pane the window is showing.
    public enum SettingsTab: Hashable, CaseIterable { case general, about, backups }

    /// A long backup list scrolls rather than growing without limit.
    static let maxTableHeight: CGFloat = 260

    public init(model: AppModel) {
        self.model = model
        // The opening pane can be chosen from the environment so each one can be inspected
        // without clicking. There is no way to click from a script — Accessibility permission is
        // not granted — and shipping a pane nobody has looked at is how the empty popover box and
        // the inverted Save button got through. A normal launch opens 通用.
        switch ProcessInfo.processInfo.environment["CODEXBRIDGER_SETTINGS_TAB"] {
        case "about": _selection = State(initialValue: .about)
        case "backups": _selection = State(initialValue: .backups)
        default: _selection = State(initialValue: .general)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Sized to the content. Each reduction has been because the window was still larger than
        // what it holds: 560x480, then 460x380, now this.
        .frame(width: 460, height: 320)
        .onAppear { reloadBackups() }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selection {
        case .general: general
        case .about: about
        case .backups: backupsTab
        }
    }

    /// A compact tab row, sized by its own labels.
    ///
    /// This replaces `TabView`: the selected tab was drawn as a large rounded box around a short
    /// label, so the highlight was noticeably out of proportion with the text inside it. Here the
    /// box is only as big as the label plus its padding.
    private var tabBar: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(title(for: tab))
                        .font(Typography.control)
                        .foregroundStyle(Color.token(
                            selection == tab ? Palette.textPrimary : Palette.textSecondary
                        ))
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(Color.primary.opacity(selection == tab ? 0.10 : 0))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private func title(for tab: SettingsTab) -> String {
        switch tab {
        case .general: return model.t("通用")
        case .about: return model.t("关于")
        case .backups: return model.t("备份")
        }
    }

    // MARK: - General

    private var general: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(model.t("界面语言"))
                .font(Typography.sectionTitle)
                .foregroundStyle(Color.token(Palette.textPrimary))
            Picker("", selection: languageBinding) {
                ForEach(InterfaceLanguage.allCases, id: \.self) { language in
                    Text(label(for: language)).tag(language)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text(model.t("界面语言") + "：" + languageFootnote)
                .font(Typography.help)
                .foregroundStyle(Color.token(Palette.textHelp))
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var languageBinding: Binding<InterfaceLanguage> {
        Binding(
            get: { model.configuration.interfaceLanguage },
            set: { model.setLanguage($0) }
        )
    }

    private func label(for language: InterfaceLanguage) -> String {
        // The language names stay in their own language, which is how a reader who cannot read
        // the current interface still finds their own.
        switch language {
        case .system: return model.t("跟随系统")
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    private var languageFootnote: String {
        switch model.resolvedLanguage {
        case .english: return "English"
        default: return "中文"
        }
    }

    // MARK: - About

    /// Modelled on the reference app: a centred column — icon, name, version, then the notes.
    ///
    /// It used to be a left-aligned list of label/value rows, which read like a form rather than
    /// an About screen and sat in the top-left of a mostly empty window.
    private var about: some View {
        VStack(spacing: Spacing.md) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("CodexBridger")
                .font(Typography.sectionTitle)
                .foregroundStyle(Color.token(Palette.textPrimary))
            Text(model.t("版本") + " " + SettingsView.version)
                .font(Typography.help)
                .foregroundStyle(Color.token(Palette.textHelp))
            Text(model.t(SettingsView.versionNote))
                .font(Typography.help)
                .foregroundStyle(Color.token(Palette.textHelp))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Divider().frame(maxWidth: 320)
            Text(model.t(SettingsView.aboutNote))
                .font(Typography.help)
                .foregroundStyle(Color.token(Palette.textHelp))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Where CodexBridger keeps its files, shown on the About pane.
    static let versionNote = "让第三方模型轻松接入 ChatGPT"
    static let aboutNote = "CodexBridger 只写入 ChatGPT 官方文档支持的字段，并把每次替换前的原文件备份到 backup/config-backup。"
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return short + " (" + build + ")"
    }

    // MARK: - Backups

    private var backupsTab: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(model.t("备份文件"))
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Color.token(Palette.textPrimary))
                Spacer(minLength: 0)
                Button(model.t("刷新")) { reloadBackups() }
                    .buttonStyle(.bordered)
                Button(model.t("打开备份文件夹")) { openBackupFolder() }
                    .buttonStyle(.bordered)
            }
            if let loadError {
                InlineError(loadError)
            }
            if backups.isEmpty {
                Text(model.t("还没有备份文件"))
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.textHelp))
                    .padding(.vertical, Spacing.md)
            } else {
                Table(backups) {
                    TableColumn(model.t("名称")) { row in
                        Text(row.name)
                            .font(Typography.monoSmall)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(row.url.path)
                    }
                    TableColumn(model.t("文件大小")) { row in
                        Text(row.size)
                            .font(Typography.monoSmall)
                            .foregroundStyle(Color.token(Palette.textHelp))
                    }
                    TableColumn(model.t("修改时间")) { row in
                        Text(row.modified)
                            .font(Typography.monoSmall)
                            .foregroundStyle(Color.token(Palette.textHelp))
                    }
                }
                // A small fixed minimum, then as much as the pane can give.
                //
                // This has been wrong three ways now. A bare fixed height filled the window with
                // blank rows. A fixed height taller than the pane clipped the last row in half.
                // A *computed* minimum was worse still: with many backups it demanded more height
                // than the window had, and SwiftUI resolved the overflow by squeezing the tab bar
                // out of existence, so the Backups pane had no tabs at all. The minimum has to be
                // something the window can always afford; the table scrolls for the rest.
                .frame(minHeight: 120, maxHeight: .infinity)
                .tableStyle(.inset(alternatesRowBackgrounds: false))
            }
            Text(model.paths.backupDirectory.path)
                .font(Typography.monoSmall)
                .foregroundStyle(Color.token(Palette.textHelp))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func reloadBackups() {
        do {
            backups = try BackupFile.list(in: model.paths.backupDirectory)
            loadError = nil
        } catch {
            backups = []
            loadError = error.localizedDescription
        }
    }

    private func openBackupFolder() {
        let directory = model.paths.backupDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}

/// One row of the backup browser.
public struct BackupFile: Identifiable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let size: String
    public let modified: String

    /// Height a table needs for this many rows, header included.
    static func tableHeight(forRowCount rows: Int) -> CGFloat {
        let header: CGFloat = 28
        let row: CGFloat = 28
        return header + CGFloat(max(rows, 1)) * row
    }

    /// Newest first, so the most recent backup is the one you see.
    public static func list(in directory: URL) throws -> [BackupFile] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return [] }
        let urls = try manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        return urls
            .filter { !$0.hasDirectoryPath }
            .map { url in
                let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                )
                let bytes = values?.fileSize ?? 0
                return BackupFile(
                    url: url,
                    name: url.lastPathComponent,
                    size: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file),
                    modified: values?.contentModificationDate.map(formatter.string(from:)) ?? "—"
                )
            }
            .sorted { $0.name > $1.name }
    }
}

/// A label/value pair, kept for panes that need one.
///
/// Aligned on the row centre, not on the text baseline: the label and the value use different
/// fonts, so baseline alignment left the shorter label sitting low against its value.
private struct InfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(Color.token(Palette.textSecondary))
                .frame(width: Metrics.labelColumnWidth, alignment: .trailing)
            Text(value)
                .font(Typography.monoSmall)
                .foregroundStyle(Color.token(Palette.textPrimary))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}