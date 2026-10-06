import SwiftUI

/// Collapsible group inside a card.
///
/// The title sits at the same left edge as the form rows inside it, so expanding a
/// group never shifts the label column. The chevron is trailing, matching the platform
/// convention and keeping the title aligned.
public struct DisclosureSection<Content: View>: View {
    private let title: String
    private let subtitle: String?
    @Binding private var isExpanded: Bool
    private let content: Content

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    public init(
        title: String,
        subtitle: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isExpanded = isExpanded
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(title)
                            .font(Typography.label)
                            .foregroundStyle(Color.token(Palette.textPrimary))
                        if let subtitle {
                            HelpText(subtitle, lineLimit: 1)
                        }
                    }
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.right")
                        .iconFont(.xs, weight: .semibold)
                        .foregroundStyle(Color.token(Palette.textSecondary))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, Spacing.xs)
                .frame(minHeight: Metrics.minHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(isHovered ? Color.token(Palette.hoverFill) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isFocused)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "已展开" : "已折叠")
            .onHover { isHovered = $0 }
            .focusRing(isFocused, cornerRadius: Radius.sm)

            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    content
                }
                .padding(.top, Spacing.xs)
            }
        }
        .animation(.easeOut(duration: Motion.appear), value: isExpanded)
    }
}
