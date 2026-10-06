import SwiftUI
import AppKit

// MARK: - Shared field chrome
//
// Dropdowns, text fields and the key-value editor all draw the same chrome from the
// same tokens, so a row can change control type without the border, radius, height or
// hover colour shifting.

struct FieldChrome: ViewModifier {
    let phase: ControlPhase
    let isInvalid: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(strokeColor, lineWidth: strokeWidth)
            )
            .animation(.easeOut(duration: Motion.hover), value: phase)
    }

    private var fillColor: Color {
        if !isEnabled(phase) { return Color.token(Palette.surface).opacity(0.5) }
        switch phase {
        case .pressed: return Color.token(Palette.hoverFill)
        default: return Color.token(Palette.surfaceSunken)
        }
    }

    private var strokeColor: Color {
        if isInvalid { return Color.token(Palette.danger) }
        switch phase {
        case .disabled: return Color.token(Palette.border)
        case .focused, .focusedHovered, .pressed: return Color.token(Palette.accent)
        case .hovered: return Color.token(Palette.borderStrong)
        default: return Color.token(Palette.border)
        }
    }

    private var strokeWidth: CGFloat {
        if isInvalid { return 1.5 }
        switch phase {
        case .focused, .focusedHovered: return 1.5
        default: return 1
        }
    }

    private func isEnabled(_ phase: ControlPhase) -> Bool { phase != .disabled }
}

extension View {
    func fieldChrome(
        phase: ControlPhase,
        isInvalid: Bool = false,
        cornerRadius: CGFloat = Radius.sm
    ) -> some View {
        modifier(FieldChrome(phase: phase, isInvalid: isInvalid, cornerRadius: cornerRadius))
    }
}

// MARK: - Dropdown

/// The dropdown used everywhere a value is chosen from a list.
///
/// Built on Menu so click-outside dismissal, Escape, arrow-key navigation and
/// disabled handling are the platform implementation rather than a re-implementation.
/// The label is ours, which is what keeps a long selected value truncated to one line
/// instead of wrapping the control onto two lines.
public struct SelectField<Value: Hashable>: View {
    public struct Option: Identifiable {
        public let id: Value
        public let title: String
        public let help: String?

        public init(value: Value, title: String, help: String? = nil) {
            self.id = value
            self.title = title
            self.help = help
        }
    }

    private let options: [Option]
    @Binding private var selection: Value
    private let isEnabled: Bool
    private let accessibilityLabel: String
    private let isInvalid: Bool

    @State private var interaction = ControlInteractionState()
    @FocusState private var isFocused: Bool

    public init(
        options: [Option],
        selection: Binding<Value>,
        isEnabled: Bool = true,
        isInvalid: Bool = false,
        accessibilityLabel: String
    ) {
        self.options = options
        self._selection = selection
        self.isEnabled = isEnabled
        self.isInvalid = isInvalid
        self.accessibilityLabel = accessibilityLabel
    }

    private var selectedTitle: String {
        options.first { $0.id == selection }?.title ?? "-"
    }

    public var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    guard isEnabled else { return }
                    selection = option.id
                } label: {
                    Text(option.title)
                }
                .disabled(!isEnabled)
                .help(option.help ?? option.title)
            }
        } label: {
            labelBody
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!isEnabled)
        .focused($isFocused)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selectedTitle)
        .onHover { hovering in
            interaction.send(hovering ? .hoverEnter : .hoverExit)
        }
        .onChange(of: isFocused) { _, focused in
            interaction.send(focused ? .focusGain : .focusLoss)
        }
        .onChange(of: isEnabled) { _, enabled in
            interaction.send(enabled ? .enable : .disable)
        }
        // A full-width control is already an easy target; padding it out to 44pt doubled the
        // row pitch. The dense floor only guarantees a usable height.
        .hitTarget(minWidth: 0, minHeight: Metrics.minDenseHitTarget)
        // The borderless button menu style lets AppKit draw the label itself, which swallows any
        // background or overlay applied inside it. The chrome therefore lives here, wrapping the
        // Menu, so it is actually painted.
        .background(chromeFill)
        .overlay(chromeBorder)
    }

    private var chromeFill: some View {
        RoundedRectangle(cornerRadius: Radius.sm)
            .fill(Color.token(Palette.surfaceSunken))
    }


    @ViewBuilder
    private var chromeBorder: some View {
        RoundedRectangle(cornerRadius: Radius.sm)
            .strokeBorder(
                // Measured against the system text field bezel: using borderStrong here made the
                // dropdown visibly darker than every input next to it.
                isInvalid ? Color.token(Palette.danger) : Color.token(Palette.border),
                lineWidth: Metrics.borderWidth
            )
    }

    private var labelBody: some View {
        HStack(spacing: Spacing.sm) {
            Text(selectedTitle)
                .font(Typography.control)
                .foregroundStyle(Color.token(interaction.isEnabled ? Palette.textPrimary
                                                            : Palette.textSecondary))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(selectedTitle)
            Spacer(minLength: Spacing.xs)
            Image(systemName: "chevron.up.chevron.down")
                .iconFont(.xs, weight: .semibold)
                .foregroundStyle(Color.token(Palette.textSecondary))
        }
        .padding(.horizontal, Spacing.md)
    }
}

// MARK: - Text field

/// A directory path with a button that opens the system folder picker.
///
/// Typing a path by hand is the wrong interaction for a filesystem location: it invites typos
/// and gives no way to see what is actually there. The text stays editable so a path can also
/// be pasted.
public struct FolderPathField: View {
    @Binding private var path: String
    private let isEnabled: Bool
    private let accessibilityLabel: String

    public init(
        path: Binding<String>,
        isEnabled: Bool = true,
        accessibilityLabel: String
    ) {
        self._path = path
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            ValueTextField(
                text: $path,
                isEnabled: isEnabled,
                monospaced: true,
                accessibilityLabel: accessibilityLabel
            )
            Button("选取…") { chooseFolder() }
                .buttonStyle(.bordered)
                .disabled(!isEnabled)
                .help("打开系统文件夹选择器")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选取"
        panel.message = "选择一个工作目录"
        if !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

public struct ValueTextField: View {
    @Binding private var text: String
    private let prompt: String
    private let isEnabled: Bool
    private let isInvalid: Bool
    private let isMonospaced: Bool
    private let accessibilityLabel: String
    /// Multi-line fields size themselves between these line counts.
    private let lineRange: ClosedRange<Int>?

    @State private var interaction = ControlInteractionState()
    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        prompt: String = "",
        isEnabled: Bool = true,
        isInvalid: Bool = false,
        monospaced: Bool = true,
        accessibilityLabel: String,
        lineRange: ClosedRange<Int>? = nil
    ) {
        self._text = text
        self.prompt = prompt
        self.isEnabled = isEnabled
        self.isInvalid = isInvalid
        self.isMonospaced = monospaced
        self.accessibilityLabel = accessibilityLabel
        self.lineRange = lineRange
    }

    public var body: some View {
        field
            .disabled(!isEnabled)
            .focused($isFocused)
            .accessibilityLabel(accessibilityLabel)
            .onHover { hovering in
                interaction.send(hovering ? .hoverEnter : .hoverExit)
            }
            .onChange(of: isFocused) { _, focused in
                interaction.send(focused ? .focusGain : .focusLoss)
            }
            .onChange(of: isEnabled) { _, enabled in
                interaction.send(enabled ? .enable : .disable)
            }
            // See SelectField: the 44pt floor is for small controls, not full-width fields.
            .hitTarget(minWidth: 0, minHeight: Metrics.minDenseHitTarget)
    }

    @ViewBuilder
    private var field: some View {
        let font = isMonospaced
            ? Font.system(size: 12, design: .monospaced)
            : Typography.control
        if let lineRange {
            TextField(prompt, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .lineLimit(lineRange)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fieldChrome(phase: interaction.phase, isInvalid: isInvalid)
        } else {
            // Stock bezel, matching APIBypass which uses a bare TextField. No forced height:
            // the system decides. The invalid state is an outline on top so the system bezel
            // stays intact.
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(font)
                .lineLimit(1)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(Color.token(Palette.danger), lineWidth: Metrics.borderWidth)
                        .opacity(isInvalid ? 1 : 0)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Optional boolean with three explicit choices, rendered as a dropdown with nowrap labels.
public struct TriStateBoolField: View {
    @Binding private var value: Bool?
    private let accessibilityLabel: String

    private enum Choice: Hashable { case unset, on, off }

    public init(value: Binding<Bool?>, accessibilityLabel: String) {
        self._value = value
        self.accessibilityLabel = accessibilityLabel
    }

    private var choice: Binding<Choice> {
        Binding(
            get: {
                switch value {
                case .none: return .unset
                case .some(true): return .on
                case .some(false): return .off
                }
            },
            set: { newValue in
                switch newValue {
                case .unset: value = nil
                case .on: value = true
                case .off: value = false
                }
            }
        )
    }

    public var body: some View {
        SelectField(
            options: [
                .init(value: Choice.unset, title: "不写入"),
                .init(value: Choice.on, title: "true"),
                .init(value: Choice.off, title: "false")
            ],
            selection: choice,
            accessibilityLabel: accessibilityLabel
        )
        .frame(maxWidth: 220)
    }
}

// MARK: - Checkbox

/// A checkbox with a full-size pointer target.
///
/// The stock checkbox is roughly 14pt across. The visual stays a native-looking
/// square, but the tappable area and the focus handling are ours, and VoiceOver still
/// sees a real toggle through accessibilityRepresentation.
public struct CheckboxControl: View {
    @Binding private var isOn: Bool
    private let isEnabled: Bool
    private let accessibilityLabel: String

    @State private var interaction = ControlInteractionState()
    @FocusState private var isFocused: Bool

    public init(isOn: Binding<Bool>, isEnabled: Bool = true, accessibilityLabel: String) {
        self._isOn = isOn
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        Button {
            guard isEnabled else { return }
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .iconFont(.m)
                .foregroundStyle(isOn ? Color.token(Palette.accent)
                                      : Color.token(Palette.textSecondary))
                .frame(width: Metrics.minDenseHitTarget, height: Metrics.minDenseHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(interaction.phase == .hovered || interaction.phase == .pressed
                              ? Color.token(Palette.hoverFill)
                              : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .focused($isFocused)
        .accessibilityRepresentation {
            Toggle(accessibilityLabel, isOn: $isOn)
        }
        .onHover { hovering in interaction.send(hovering ? .hoverEnter : .hoverExit) }
        .onChange(of: isFocused) { _, focused in
            interaction.send(focused ? .focusGain : .focusLoss)
        }
        .hitTarget(minWidth: Metrics.minHitTarget, minHeight: Metrics.minHitTarget)
        .focusRing(interaction.phase == .focused || interaction.phase == .focusedHovered,
                   cornerRadius: Radius.sm)
        .animation(.easeOut(duration: Motion.hover), value: interaction.phase)
    }
}
