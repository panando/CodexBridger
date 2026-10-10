import SwiftUI
import AppKit

/// A dropdown you can also type into.
///
/// SwiftUI has no combo box on macOS, so this is the project's own: a text
/// field carrying the current value, and a candidate list shown as a popover
/// while the field is focused. Typing narrows the list; picking one replaces
/// the text; a value that is not in the list is kept as typed — manual entry
/// of a slug a scan never proved must stay possible.
///
/// The list is a popover on purpose: a click anywhere outside it dismisses it,
/// which is the behaviour a combo box has and an inline list does not.
public struct EditableSelectField: View {
    private let options: [String]
    @Binding private var text: String
    private let accessibilityLabel: String

    @State private var interaction = ControlInteractionState()
    @FocusState private var isFocused: Bool
    @State private var isListShown = false

    public init(
        options: [String],
        text: Binding<String>,
        accessibilityLabel: String
    ) {
        self.options = options
        self._text = text
        self.accessibilityLabel = accessibilityLabel
    }

    /// Candidates matching what is typed. Empty input shows everything.
    public static func filtered(_ options: [String], by query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return options }
        return options.filter { $0.lowercased().contains(trimmed) }
    }

    private var filtered: [String] { Self.filtered(options, by: text) }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            field
                .popover(isPresented: $isListShown, arrowEdge: .bottom) {
                    candidateList
                }
            Image(systemName: "chevron.up.chevron.down")
                .font(Typography.help)
                .foregroundStyle(Color.token(Palette.textSecondary))
                .onTapGesture { isListShown.toggle() }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityLabel(accessibilityLabel)
    }

    private var field: some View {
        TextField("输入或选择模型", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(Typography.control)
            .focused($isFocused)
            .accessibilityLabel(accessibilityLabel)
            .onHover { hovering in
                interaction.send(hovering ? .hoverEnter : .hoverExit)
            }
            // Focus opens the list; losing it closes it, so a click on blank
            // space anywhere on the screen retracts the dropdown.
            .onChange(of: isFocused) { _, focused in
                isListShown = focused
            }
    }

    private var candidateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if filtered.isEmpty {
                    Text("没有通过检测的模型，可直接输入")
                        .font(Typography.help)
                        .foregroundStyle(Color.token(Palette.textSecondary))
                        .padding(Spacing.sm)
                }
                ForEach(filtered, id: \.self) { option in
                    Button {
                        text = option
                        isListShown = false
                    } label: {
                        HStack {
                            Text(option)
                                .font(Typography.control)
                                .foregroundStyle(Color.token(Palette.textPrimary))
                            Spacer(minLength: 0)
                            if option == text {
                                Image(systemName: "checkmark")
                                    .font(Typography.help)
                                    .foregroundStyle(Color.token(Palette.accent))
                            }
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if option != filtered.last { Divider() }
                }
            }
        }
        .frame(width: 320, height: filtered.isEmpty ? 60 : min(CGFloat(filtered.count) * 28 + 12, 160))
        .background(Color.token(Palette.surface))
    }
}
