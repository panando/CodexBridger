import SwiftUI
import CodexBridgerCore

/// Chooser shown by "新建提供商".
///
/// Mirrors the reference sidebar structure: known providers grouped by family, each row
/// showing the endpoint it will prefill. A blank entry is offered last for services that are
/// not in the catalogue.
public struct PresetPickerSheet: View {
    private let onPick: (ProviderPreset) -> Void
    private let onPickBlank: () -> Void
    private let onCancel: () -> Void

    public init(
        onPick: @escaping (ProviderPreset) -> Void,
        onPickBlank: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onPick = onPick
        self.onPickBlank = onPickBlank
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建提供商")
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Color.token(Palette.textPrimary))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(ProviderPreset.groups(ProviderPreset.builtIn)) { group in
                        SectionCaption(group.category)
                        VStack(spacing: Spacing.xs) {
                            ForEach(group.presets) { preset in
                                presetRow(preset)
                            }
                        }
                    }

                    Divider().padding(.vertical, Spacing.xs)
                    SectionCaption("其它")
                    Button(action: onPickBlank) {
                        // Same shell as a preset row. The custom entry previously had its own
                        // hand-written layout, and a width frame meant for the icon landed on the
                        // text instead, wrapping 自定义 into a vertical column.
                        rowShell(
                            icon: "square.dashed",
                            iconTint: Palette.textSecondary,
                            title: "自定义",
                            subtitle: nil
                        )
                    }
                    .buttonStyle(.plain)
                    .background(rowBorder)
                }
                .padding(Spacing.xl)
            }

            Divider()
            HStack {
                Spacer(minLength: 0)
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .padding(Spacing.lg)
        }
        .frame(width: Metrics.sheetWidth, height: Metrics.sheetHeight)
        .background(Color.token(Palette.surface))
    }

    /// Border shared by every entry so all rows read as one list.
    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: Radius.md)
            .strokeBorder(Color.token(Palette.border), lineWidth: Metrics.borderWidth)
    }

    /// Icon + title + optional subtitle + chevron, with the icon on a fixed column so the
    /// titles of every row line up. Only the icon carries a width frame; the text is free to size
    /// itself, which is what keeps a short label on one line.
    private func rowShell(
        icon: String,
        iconTint: NSColor,
        title: String,
        subtitle: String?
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .iconFont(.m)
                .foregroundStyle(Color.token(iconTint))
                .frame(width: Metrics.sidebarGlyph)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.control)
                    .foregroundStyle(Color.token(Palette.textPrimary))
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Color.token(Palette.textHelp))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .iconFont(.xs, weight: .semibold)
                .foregroundStyle(Color.token(Palette.textSecondary))
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func presetRow(_ preset: ProviderPreset) -> some View {
        Button { onPick(preset) } label: {
            rowShell(
                icon: "square.stack.3d.up",
                iconTint: Palette.accentText,
                title: preset.name,
                subtitle: preset.baseURL
            )
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.token(Palette.border), lineWidth: Metrics.borderWidth)
        )
        .help(preset.note)
    }
}
