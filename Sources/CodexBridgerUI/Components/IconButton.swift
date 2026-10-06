import SwiftUI

/// Icon-only action button.
///
/// The visible glyph stays compact, but the button reserves the full accessibility
/// pointer target and declares hover, pressed, focus and disabled states through the
/// shared interaction state machine. The old buttons were ~16pt with no hover state and
/// no focus ring, which is why they were hard to hit and impossible to find by keyboard.
public struct IconButton: View {
    public enum Role { case normal, destructive }

    private let systemName: String
    private let label: String
    private let role: Role
    private let isEnabled: Bool
    private let action: () -> Void

    @State private var interaction = ControlInteractionState()
    @FocusState private var isFocused: Bool

    public init(
        systemName: String,
        label: String,
        role: Role = .normal,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.label = label
        self.role = role
        self.isEnabled = isEnabled
        self.action = action
    }

    private var tint: Color {
        guard isEnabled else { return Color.token(Palette.textSecondary).opacity(0.5) }
        return role == .destructive ? Color.token(Palette.danger) : Color.token(Palette.textPrimary)
    }

    public var body: some View {
        Button {
            // Route the click through the same state machine the tests exercise, so a
            // disabled or drag-out press cannot activate.
            var state = interaction
            state.send(.hoverEnter)
            state.send(.pressDown)
            let activated = state.send(.pressUp)
            if activated { action() }
        } label: {
            Image(systemName: systemName)
                .iconFont(.s, weight: .medium)
                .foregroundStyle(tint)
                .frame(width: Metrics.iconChrome + 6, height: Metrics.iconChrome)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(backgroundFill)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .focused($isFocused)
        .accessibilityLabel(label)
        .help(label)
        .onHover { hovering in
            interaction.send(hovering ? .hoverEnter : .hoverExit)
        }
        .onChange(of: isFocused) { _, focused in
            interaction.send(focused ? .focusGain : .focusLoss)
        }
        .onChange(of: isEnabled) { _, enabled in
            interaction.send(enabled ? .enable : .disable)
        }
        .hitTarget()
        .focusRing(interaction.phase == .focused || interaction.phase == .focusedHovered,
                   cornerRadius: Radius.sm)
        .animation(.easeOut(duration: Motion.hover), value: interaction.phase)
    }

    private var backgroundFill: Color {
        guard isEnabled else { return .clear }
        switch interaction.phase {
        case .pressed: return Color.token(Palette.pressFill).opacity(0.25)
        case .hovered, .focusedHovered: return Color.token(Palette.hoverFill)
        default: return .clear
        }
    }
}

/// The app primary action, kept on the native button style so macOS keeps owning its
/// hover, press, focus ring and disabled rendering.
public struct PrimaryActionButton: View {
    private let title: String
    private let isEnabled: Bool
    private let isBusy: Bool
    private let action: () -> Void

    public init(title: String, isEnabled: Bool = true, isBusy: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.isBusy = isBusy
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Text(title).font(Typography.control)
            }
            .frame(minWidth: 120)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled || isBusy)
        .hitTarget()
    }
}
