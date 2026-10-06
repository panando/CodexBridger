import AppKit
import SwiftUI

// MARK: - Design tokens
//
// Every visual constant lives here. Views must not invent their own spacing, radius,
// colour or duration: that is what produced the inconsistent rows and mismatched
// help text in the first place.

/// 4pt spacing scale. All padding and gaps come from here.
public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32

    /// Ordered from smallest to largest; tests assert the scale stays monotonic.
    public static let scale: [CGFloat] = [xxs, xs, sm, md, lg, xl, xxl]
}

public enum Radius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 14
    public static let pill: CGFloat = 999
    /// Mapping card corner, from MappingCardView `.cornerRadius(8)`.
    public static let card: CGFloat = 8
    /// Tight corners: small glyph tiles and inline marks.
    public static let xs: CGFloat = 5
    /// The app mark, matching the platform icon corner ratio.
    public static let xl: CGFloat = 18
}

/// Layout metrics that the acceptance criteria depend on.
public enum Metrics {
    /// Minimum pointer target for any interactive control (WCAG 2.5.5 / touch).
    public static let minHitTarget: CGFloat = 44
    /// Minimum pointer target for dense secondary affordances (WCAG 2.2 AA, 2.5.8).
    public static let minDenseHitTarget: CGFloat = 24
    /// Height of the visible control chrome inside the (larger) hit area.
    /// Not used to size fields. APIBypass renders stock TextField/SecureField/Picker with
    /// no custom height, so fields take the system height. Kept for the few places that need
    /// a deterministic height (read-only rows, the status dot row).
    public static let controlHeight: CGFloat = 28

    /// Height the label is centred against inside a form row.
    ///
    /// Measured from a screen capture at 2x: the drawn input box is about 18pt tall, but the
    /// control reserves `minDenseHitTarget` (24pt) around it, so the box a label has to line up
    /// with is 24pt. Kept separate from `controlHeight`, which is used for the standalone control
    /// chrome and is not the height a row should align to.
    public static let controlVisualHeight: CGFloat = 24
    /// Row pitch for a label plus control line.
    public static let rowHeight: CGFloat = 34
    /// Padding above and below the two bottom bars.
    ///
    /// The sidebar footer and the editor action bar sit side by side, so their top dividers have
    /// to land on the same line. They used different vertical padding, which left the two rules
    /// visibly offset; both now read this one value.
    public static let actionBarVerticalPadding: CGFloat = Spacing.md
    /// Fixed height for the two bottom bars, so their top rules always align.
    public static let actionBarHeight: CGFloat = 52
    /// Height of the icon-only button chrome inside its 44pt hit area.
    public static let iconChrome: CGFloat = 22
    /// Visual size of the small square provider glyph in the sidebar.
    public static let sidebarGlyph: CGFloat = 22
    /// Fixed label column so every row aligns, whatever the label length.
    /// Right-aligned label column. Value taken from the APIBypass source:
    /// `Text(...).frame(width: 100, alignment: .trailing)`.
    public static let labelColumnWidth: CGFloat = 100
    /// Gap between the label column and the control column.
    public static let labelToControlGap: CGFloat = Spacing.md
    /// Card interior padding.
    public static let cardPadding: CGFloat = Spacing.lg
    /// Border width for the visible focus ring.
    public static let focusRingWidth: CGFloat = 3
    /// Sidebar width.
    public static let sidebarWidth: CGFloat = 268
    /// Every hairline border in the app.
    public static let borderWidth: CGFloat = 1
    /// Spacing between form sections. APIBypass: `ScrollView { VStack(spacing: 16) }`.
    public static let sectionSpacing: CGFloat = 16
    /// Spacing inside a section card. APIBypass: `VStack(alignment: .leading, spacing: 12)`.
    public static let sectionInnerSpacing: CGFloat = 12
    /// Spacing between rows inside a section. APIBypass: `VStack(spacing: 8)`.
    public static let rowSpacing: CGFloat = 8
    /// Section card corner. APIBypass: `.cornerRadius(8)` on each section.
    public static let sectionCardRadius: CGFloat = 8
    /// Mapping card header spacing, from MappingCardView `HStack(spacing: 12)`.
    public static let cardHeaderSpacing: CGFloat = 12
    /// Mapping card header padding, from MappingCardView.
    public static let cardPaddingHorizontal: CGFloat = 12
    public static let cardPaddingVertical: CGFloat = 10
    /// The mapping card status dot.
    public static let statusDotSize: CGFloat = 8
    /// The rounded mark at the top of the onboarding screen.
    public static let appGlyphSize: CGFloat = 84
    /// Fixed size of the provider picker sheet.
    public static let sheetWidth: CGFloat = 560
    public static let sheetHeight: CGFloat = 620
    /// The column the capability icons sit in on the onboarding screen.
    public static let capabilityIconColumn: CGFloat = 30
}

/// Semantic colours. Named by role, never by hue, so both appearances stay correct.
public enum Palette {
    public static let textPrimary = NSColor.labelColor
    /// Secondary text and help text use opaque greys rather than the system
    /// secondaryLabelColor.
    ///
    /// secondaryLabelColor is translucent: composited on the light card surface it
    /// lands near 4.0:1, under the 4.5:1 that WCAG 2.1 AA requires for 11pt text.
    /// Opaque greys make the ratio deterministic and verifiable — DesignTokenTests
    /// measures it in both appearances.
    public static let textSecondary = dynamic(
        light: NSColor(srgbRed: 0.33, green: 0.33, blue: 0.34, alpha: 1),
        dark: NSColor(srgbRed: 0.72, green: 0.72, blue: 0.74, alpha: 1)
    )
    public static let textHelp = dynamic(
        light: NSColor(srgbRed: 0.42, green: 0.42, blue: 0.43, alpha: 1),
        dark: NSColor(srgbRed: 0.66, green: 0.66, blue: 0.68, alpha: 1)
    )
    public static let textOnAccent = NSColor.white

    public static let surface = NSColor.controlBackgroundColor
    public static let surfaceSunken = NSColor.textBackgroundColor
    public static let windowBackground = NSColor.windowBackgroundColor
    public static let border = NSColor.separatorColor
    /// Border used for the hover affordance on interactive fields.
    ///
    /// The system gridColor measures about 1.25:1 against the field surface, which is
    /// invisible as a hover cue. WCAG 2.1 asks for 3:1 on non-text indicators, so this is
    /// an explicit token that clears it in both appearances. The plain card outline keeps
    /// using `border`: it is decorative, and the card is identifiable by its fill.
    public static let borderStrong = dynamic(
        light: NSColor(srgbRed: 0.541, green: 0.541, blue: 0.549, alpha: 1),
        dark: NSColor(srgbRed: 0.431, green: 0.431, blue: 0.441, alpha: 1)
    )

    public static let hoverFill = NSColor.unemphasizedSelectedContentBackgroundColor
    public static let pressFill = NSColor.selectedContentBackgroundColor
    public static let selectionFill = NSColor.selectedContentBackgroundColor
    /// Secondary text on a selected row (the endpoint line).
    public static let textOnSelectionSecondary = NSColor.white.withAlphaComponent(0.8)
    /// The tile behind a selected row glyph.
    public static let selectionGlyphFill = NSColor.white.withAlphaComponent(0.22)

    public static let accent = NSColor.controlAccentColor

    /// Accent for text and for text-bearing tints.
    ///
    /// controlAccentColor is tuned for fills and focus rings; as small text on a tint
    /// of itself it measures about 3.35:1 in light mode, below the 4.5:1 requirement.
    /// This variant keeps the accent identity while clearing the ratio (verified by
    /// DesignTokenTests.testPillTextStaysReadableOnItsOwnTint).
    public static let accentText = dynamic(
        light: NSColor(srgbRed: 0.043, green: 0.373, blue: 0.800, alpha: 1),
        dark: NSColor(srgbRed: 0.486, green: 0.753, blue: 1.000, alpha: 1)
    )

    /// Semantic status colours.
    ///
    /// The system red and green are tuned for fills, not for small text: on a light
    /// surface they land near 3.9:1, under the 4.5:1 body-text requirement. These
    /// variants are darkened for light mode and lightened for dark mode so status
    /// text passes the contrast test in both appearances.
    public static let danger = dynamic(
        light: NSColor(srgbRed: 0.69, green: 0.10, blue: 0.15, alpha: 1),
        dark: NSColor(srgbRed: 1.00, green: 0.55, blue: 0.55, alpha: 1)
    )
    public static let success = dynamic(
        light: NSColor(srgbRed: 0.04, green: 0.42, blue: 0.22, alpha: 1),
        dark: NSColor(srgbRed: 0.42, green: 0.87, blue: 0.55, alpha: 1)
    )
    public static let warning = dynamic(
        light: NSColor(srgbRed: 0.55, green: 0.35, blue: 0.00, alpha: 1),
        dark: NSColor(srgbRed: 1.00, green: 0.78, blue: 0.35, alpha: 1)
    )

    /// Builds a colour that resolves differently per appearance.
    public static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        }
    }

    /// Resolves a semantic colour inside a given appearance.
    public static func resolve(_ color: NSColor, appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }
}

/// One type scale for the whole app.
public enum Typography {
    public static let titleFont = Font.system(size: 17, weight: .semibold)
    public static let sectionTitle = Font.system(size: 13, weight: .semibold)
    /// 13pt regular. This is the platform default `.body` on macOS, and it is what
    /// APIBypass uses for every field label and value, so it is the default here too.
    public static let body = Font.system(size: 13, weight: .regular)
    public static let bodyMedium = Font.system(size: 13, weight: .medium)
    public static let bodyStrong = Font.system(size: 13, weight: .semibold)
    /// Help text: 11pt, the single size used for every explanatory string.
    public static let help = Font.system(size: 11, weight: .regular)
    /// The small grey group label above a form section. APIBypass uses `.subheadline`
    /// (11pt regular) with `.secondary`, so this is regular, not medium.
    public static let sectionCaption = Font.system(size: 11, weight: .regular)
    public static let pill = Font.system(size: 10, weight: .semibold)
    /// Machine-readable values: endpoints, identifiers, model slugs.
    public static let mono = Font.system(size: 13, design: .monospaced)
    public static let monoSmall = Font.system(size: 11, design: .monospaced)

    // Aliases. These were previously separate names carrying identical values, which made the
    // scale look twice as large as it is. They are kept for call-site readability but resolve
    // to exactly one value, so there is one place to change a size.
    public static let label = body
    public static let control = body
    public static let caption = help

    public static let helpLineSpacing: CGFloat = 2
    public static let bodyLineSpacing: CGFloat = 3
}

/// The icon scale: four working steps plus two decorative marks.
///
/// Icon sizes had drifted to eight ad-hoc values (9, 10, 11, 12, 15, 19, 30, 36) with no
/// rhythm between them. They collapse onto a 2pt-ish progression; the two large marks are
/// the app glyph and the empty-state illustration.
public enum IconSize: CGFloat {
    case xs = 10
    case s = 12
    case m = 15
    case l = 19
    case glyph = 30
    case hero = 36
}

public extension View {
    /// Sets an icon to one step of the icon scale.
    func iconFont(_ size: IconSize, weight: Font.Weight = .regular) -> some View {
        font(.system(size: size.rawValue, weight: weight))
    }
}

/// Animation durations. Kept short so interaction feedback never feels laggy.
public enum Motion {
    public static let hover: Double = 0.12
    public static let press: Double = 0.08
    public static let appear: Double = 0.18
}

// MARK: - Token helpers used by the components

extension Color {
    /// Wraps a semantic token colour so views keep using SwiftUI.
    static func token(_ color: NSColor) -> Color {
        Color(nsColor: color)
    }
}

/// Guarantees a control is at least as large as the required pointer target while
/// keeping its visible chrome compact.
public struct HitTargetModifier: ViewModifier {
    let minWidth: CGFloat
    let minHeight: CGFloat

    public init(minWidth: CGFloat = Metrics.minHitTarget, minHeight: CGFloat = Metrics.minHitTarget) {
        self.minWidth = minWidth
        self.minHeight = minHeight
    }

    public func body(content: Content) -> some View {
        content
            .frame(minWidth: minWidth, minHeight: minHeight)
            .contentShape(Rectangle())
    }
}

public extension View {
    /// Expands the pointer target to the accessibility minimum.
    func hitTarget(
        minWidth: CGFloat = Metrics.minHitTarget,
        minHeight: CGFloat = Metrics.minHitTarget
    ) -> some View {
        modifier(HitTargetModifier(minWidth: minWidth, minHeight: minHeight))
    }

    /// Draws the shared focus ring when the element owns keyboard focus.
    func focusRing(_ isFocused: Bool, cornerRadius: CGFloat = Radius.sm) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.token(Palette.accent), lineWidth: Metrics.focusRingWidth)
                .opacity(isFocused ? 1 : 0)
        )
        .animation(.easeOut(duration: Motion.hover), value: isFocused)
    }
}
