import SwiftUI
import CodexBridgerCore

// MARK: - Form rows
//
// Geometry follows the reference screen: the label sits in a narrow RIGHT-aligned column
// immediately left of the control, rather than a wide left-aligned column. Explanations
// move out of the label cell (either an info badge on the label, or one caption line under
// the control) so the label column stays narrow and every control starts on the same x.

/// A labelled control.
public struct FormRow<Control: View>: View {
    private let label: String
    private let help: String?
    private let info: String?
    private let isRequired: Bool
    private let isEnabled: Bool
    private let control: Control

    public init(
        _ label: String,
        help: String? = nil,
        info: String? = nil,
        isRequired: Bool = false,
        isEnabled: Bool = true,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.help = help
        self.info = info
        self.isRequired = isRequired
        self.isEnabled = isEnabled
        self.control = control()
    }

    public var body: some View {
        // The label is aligned to the CONTROL, never to the whole control column.
        //
        // `control` is a ViewBuilder closure, so a field with a warning hands us two views and the
        // column stacks them. With `.center` the label used to centre on the column as a whole, so
        // any caption pushed the label roughly (caption + spacing) / 2 below its own input — the
        // Base URL warning moved its label about 11pt off the field.
        //
        // Top alignment plus a label box of the control's own height pins the label to the first
        // line of the column, so the caption can be any height without moving it. The control
        // column is kept as a VStack because that is what stacks a multi-statement closure.
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .top, spacing: Metrics.labelToControlGap) {
                labelCell
                    .frame(height: Metrics.controlVisualHeight, alignment: .center)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    control
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: Metrics.rowHeight)
            if let help {
                // Indented to the control column so the caption still reads as belonging to the
                // field above it, not to the row as a whole.
                HelpText(help)
                    .padding(.leading, Metrics.labelColumnWidth + Metrics.labelToControlGap)
            }
        }
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityElement(children: .contain)
    }

    /// Fixed-width cell, vertically centred against the control.
    ///
    /// The label used to be pinned to `controlHeight`, which no longer matched the real control
    /// height once the fields took the system bezel, so labels sat off-centre against the field
    /// and the dropdown. Centring in the row — which now contains only the label and the control —
    /// keeps the two aligned whatever the control measures and whatever caption follows.
    private var labelCell: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Spacer(minLength: 0)
            Text(label)
                .font(Typography.label)
                .foregroundStyle(Color.token(Palette.textPrimary))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
            if isRequired {
                RequiredMark()
            }
            if let info {
                InfoBadge(info)
            }
        }
        .frame(width: Metrics.labelColumnWidth, alignment: .trailing)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

/// Read-only row showing a fixed value.
public struct InfoRow: View {
    private let label: String
    private let value: String
    private let help: String?

    public init(_ label: String, value: String, help: String? = nil) {
        self.label = label
        self.value = value
        self.help = help
    }

    public var body: some View {
        FormRow(label, help: help) {
            Text(value)
                .font(Typography.control)
                .monospaced()
                .foregroundStyle(Color.token(Palette.textPrimary))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
                .frame(height: Metrics.controlHeight)
        }
    }
}

// MARK: - Text hierarchy

/// Section heading above a group of rows, matching the reference small grey captions.
public struct SectionCaption: View {
    private let text: String
    private let trailing: AnyView?

    public init(_ text: String) {
        self.text = text
        self.trailing = nil
    }

    public init<Trailing: View>(_ text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = AnyView(trailing())
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(text)
                .font(Typography.sectionCaption)
                .foregroundStyle(Color.token(Palette.textHelp))
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }
}

/// One caption line under a control.
public struct HelpText: View {
    private let text: String
    private let lineLimit: Int

    public init(_ text: String, lineLimit: Int = 3) {
        self.text = text
        self.lineLimit = lineLimit
    }

    public var body: some View {
        Text(text)
            .font(Typography.help)
            .foregroundStyle(Color.token(Palette.textHelp))
            .lineSpacing(Typography.helpLineSpacing)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(text)
    }
}

/// Empty cell as wide as the label column, so a control or a note can start at the control
/// column without repeating the width arithmetic at every call site.
public struct LabelColumnSpacer: View {
    public init() {}

    public var body: some View {
        Color.clear.frame(width: Metrics.labelColumnWidth, height: 1)
    }
}

public struct RequiredMark: View {
    public init() {}

    public var body: some View {
        Text("*")
            .font(Typography.label)
            .foregroundStyle(Color.token(Palette.danger))
            .accessibilityLabel("必填")
    }
}

/// The reference puts an info glyph next to toggles; the explanation is the tooltip.
public struct InfoBadge: View {
    private let text: String
    @State private var isShowing = false

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        // Hover tooltips do not fire reliably on every control, so the explanation opens on
        // click. The hover tooltip is kept as well for pointers that do trigger it.
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .iconFont(.s)
                .foregroundStyle(Color.token(Palette.textHelp))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel(text)
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            InfoPopoverContent(text: text)
        }
    }
}

/// The body of an info popover.
///
/// Extracted from `InfoBadge` so its size can be measured directly. The box has to hug the text:
/// a forced minimum width made short explanations sit in an oversized empty box, and generous
/// padding inflated the height. Wrapping still happens at a comfortable reading width instead.
struct InfoPopoverContent: View {
    let text: String

    /// Widest the explanation grows before it wraps onto another line.
    static let maxWidth: CGFloat = 300

    var body: some View {
        Text(text)
            .font(Typography.help)
            .foregroundStyle(Color.token(Palette.textPrimary))
            // Wrap rather than run on: `fixedSize(vertical: true)` lets the text take as many
            // lines as it needs instead of being stretched onto one.
            .fixedSize(horizontal: false, vertical: true)
            // `maxWidth`, NOT `width`. A fixed width made every note exactly 300pt wide, so a
            // seven-character label sat in a large empty box. A maximum lets a short note hug
            // its text while a long one still wraps at a readable measure.
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .padding(Spacing.sm)
            .fixedSize(horizontal: true, vertical: true)
    }
}

public struct InlineError: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Typography.help)
                .foregroundStyle(Color.token(Palette.danger))
            Text(message)
                .font(Typography.help)
                .foregroundStyle(Color.token(Palette.danger))
                .lineSpacing(Typography.helpLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Non-blocking message under a control.
public struct InlineWarning: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle")
                .font(Typography.help)
                .foregroundStyle(Color.token(Palette.warning))
            Text(message)
                .font(Typography.help)
                .foregroundStyle(Color.token(Palette.warning))
                .lineSpacing(Typography.helpLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
