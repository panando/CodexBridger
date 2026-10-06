import AppKit
import XCTest
@testable import CodexBridgerUI

/// Seam: the design token layer.
///
/// These tests are what make "consistent spacing" and "accessible contrast"
/// checkable claims rather than opinions.
@MainActor
final class DesignTokenTests: XCTestCase {

    private let appearances: [(String, NSAppearance)] = [
        ("light", NSAppearance(named: .aqua)!),
        ("dark", NSAppearance(named: .darkAqua)!)
    ]

    // MARK: - Scale

    func testSpacingScaleIsStrictlyIncreasing() {
        let scale = Spacing.scale
        XCTAssertEqual(scale, scale.sorted())
        for (previous, next) in zip(scale, scale.dropFirst()) {
            XCTAssertLessThan(previous, next, "spacing scale must not contain duplicates")
        }
        XCTAssertEqual(scale.first, Spacing.xxs)
        XCTAssertEqual(scale.last, Spacing.xxl)
    }

    func testMinimumHitTargetMeetsTheAccessibilityFloor() {
        XCTAssertGreaterThanOrEqual(Metrics.minHitTarget, 44)
        XCTAssertGreaterThanOrEqual(Metrics.minDenseHitTarget, 24)
    }

    func testControlChromeFitsInsideTheHitTarget() {
        XCTAssertLessThan(Metrics.controlHeight, Metrics.minHitTarget)
        XCTAssertLessThan(Metrics.iconChrome, Metrics.minHitTarget)
    }

    // MARK: - Contrast

    func testBodyAndHelpTextMeetWCAGAAOnEverySurface() {
        for (name, appearance) in appearances {
            let surfaces = [
                ("card surface", Palette.surface),
                ("window", Palette.windowBackground)
            ]
            for (surfaceName, surface) in surfaces {
                for (label, foreground) in [
                    ("textPrimary", Palette.textPrimary),
                    ("textSecondary", Palette.textSecondary),
                    ("textHelp", Palette.textHelp)
                ] {
                    let ratio = ContrastRatio.ratio(
                        foreground: foreground,
                        background: surface,
                        appearance: appearance
                    )
                    XCTAssertGreaterThanOrEqual(
                        ratio, 4.5,
                        label + " on " + surfaceName + " in " + name
                            + " is " + String(format: "%.2f", ratio) + ":1, below WCAG AA 4.5:1"
                    )
                }
            }
        }
    }

    func testStatusColoursMeetWCAGAAOnTheCardSurface() {
        for (name, appearance) in appearances {
            for (label, color) in [
                ("danger", Palette.danger),
                ("success", Palette.success),
                ("warning", Palette.warning)
            ] {
                let ratio = ContrastRatio.ratio(
                    foreground: color,
                    background: Palette.surface,
                    appearance: appearance
                )
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    label + " in " + name + " is " + String(format: "%.2f", ratio) + ":1"
                )
            }
        }
    }

    func testPillTextStaysReadableOnItsOwnTint() {
        for (name, appearance) in appearances {
            for (label, color) in [
                ("accent", Palette.accentText),
                ("success", Palette.success),
                ("danger", Palette.danger),
                ("neutral", Palette.textSecondary)
            ] {
                // The pill paints the tone at 14% over the card surface.
                let ratio = ContrastRatio.ratio(
                    foreground: color,
                    background: surfaceOverTinted(with: color, alpha: 0.14, base: Palette.surface,
                                                  appearance: appearance),
                    appearance: appearance
                )
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "pill " + label + " in " + name + " is "
                        + String(format: "%.2f", ratio) + ":1"
                )
            }
        }
    }

    /// WCAG 2.1 requires 3:1 for non-text UI components, which is what the focus ring
    /// and the field borders are.
    func testFocusRingAndBordersMeetTheNonTextContrastFloor() {
        for (name, appearance) in appearances {
            let ring = ContrastRatio.ratio(
                foreground: Palette.accent,
                background: Palette.surface,
                appearance: appearance
            )
            XCTAssertGreaterThanOrEqual(
                ring, 3.0,
                "focus ring in " + name + " is " + String(format: "%.2f", ring) + ":1"
            )
            let border = ContrastRatio.ratio(
                foreground: Palette.borderStrong,
                background: Palette.surfaceSunken,
                appearance: appearance
            )
            XCTAssertGreaterThanOrEqual(
                border, 3.0,
                "hover border in " + name + " is " + String(format: "%.2f", border) + ":1"
            )
        }
    }

    func testContrastHelperRejectsIdenticalColours() {
        let appearance = appearances[0].1
        let ratio = ContrastRatio.ratio(
            foreground: NSColor.white, background: NSColor.white, appearance: appearance
        )
        XCTAssertEqual(ratio, 1.0, accuracy: 0.01)
        let black = ContrastRatio.ratio(
            foreground: NSColor.black, background: NSColor.white, appearance: appearance
        )
        XCTAssertEqual(black, 21.0, accuracy: 0.2)
    }

    // MARK: - Helpers

    private func surfaceOverTinted(
        with tint: NSColor,
        alpha: CGFloat,
        base: NSColor,
        appearance: NSAppearance
    ) -> NSColor {
        let tinted = Palette.resolve(tint, appearance: appearance)
        let background = Palette.resolve(base, appearance: appearance)
        let a = alpha
        return NSColor(
            srgbRed: tinted.redComponent * a + background.redComponent * (1 - a),
            green: tinted.greenComponent * a + background.greenComponent * (1 - a),
            blue: tinted.blueComponent * a + background.blueComponent * (1 - a),
            alpha: 1
        )
    }
}

/// WCAG 2.1 relative luminance and contrast ratio.
enum ContrastRatio {
    static func ratio(
        foreground: NSColor,
        background: NSColor,
        appearance: NSAppearance
    ) -> Double {
        let fg = luminance(of: Palette.resolve(foreground, appearance: appearance))
        let bg = luminance(of: Palette.resolve(background, appearance: appearance))
        let lighter = max(fg, bg)
        let darker = min(fg, bg)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func luminance(of color: NSColor) -> Double {
        guard let srgb = color.usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(srgb.redComponent)
            + 0.7152 * channel(srgb.greenComponent)
            + 0.0722 * channel(srgb.blueComponent)
    }
}
