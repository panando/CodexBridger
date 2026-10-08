import SwiftUI

/// The caption strip that opens and closes a card on the global configuration screen.
///
/// The whole strip is the control, not just the words and the chevron.
///
/// Reported from the running app on 2026-10-08 (seventh review round): clicking the empty part of
/// the row did nothing. The strip used to be a `Button` whose label was the caption itself, so the
/// hit area was the words plus the chevron and nothing else. Two things make the whole strip the
/// target here: the horizontal padding lives INSIDE the button's label, so the label already spans
/// the card, and `contentShape` is applied AFTER the frame that widens it — `contentShape` covers
/// the frame it is attached to, so applied before that frame it would still only cover the words.
///
/// The hover fill is the affordance: it shows how far the target reaches, matching
/// `DisclosureSection`, which is the same control used elsewhere in the app.
public struct CollapsibleCardHeader: View {
    private let title: String
    private let isExpanded: Bool
    /// Localised "expanded"/"collapsed", supplied by the caller so this view needs no language.
    private let accessibilityValue: String
    private let horizontalPadding: CGFloat
    private let onToggle: () -> Void

    @State private var isHovered = false

    public init(
        title: String,
        isExpanded: Bool,
        accessibilityValue: String,
        horizontalPadding: CGFloat = Metrics.cardPadding,
        onToggle: @escaping () -> Void
    ) {
        self.title = title
        self.isExpanded = isExpanded
        self.accessibilityValue = accessibilityValue
        self.horizontalPadding = horizontalPadding
        self.onToggle = onToggle
    }

    public var body: some View {
        Button(action: onToggle) {
            SectionCaption(title) {
                Image(systemName: "chevron.right")
                    .iconFont(.xs, weight: .semibold)
                    .foregroundStyle(Color.token(Palette.textSecondary))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, horizontalPadding)
            // The vertical padding is the card's own top padding plus the gap that used to sit
            // between the caption and the first row, so opening a group does not move the caption.
            .padding(.top, Metrics.cardPadding)
            .padding(.bottom, Metrics.sectionInnerSpacing)
            // Padding alone left the strip two points short of the app's own minimum pointer
            // target, so the height is pinned to it.
            .frame(maxWidth: .infinity, minHeight: Metrics.minHitTarget, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.sectionCardRadius)
                    .fill(isHovered ? Color.token(Palette.hoverFill) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }
}
