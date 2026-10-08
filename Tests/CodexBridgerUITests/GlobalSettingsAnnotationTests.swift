import XCTest
import SwiftUI
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: the ⓘ annotation the global configuration screen draws for every row.
///
/// The info badge only shows its text once it is clicked, and Accessibility permission is not
/// granted, so a script cannot open it in the running app. This sheet is the review artefact.
///
/// The caption that used to sit under every control is gone (2026-10-08, eighth review: the
/// explanation is read once, in a popover, and a second copy on the page doubled its height), so
/// this sheet now draws one annotation per row.
///
/// It draws the real `InfoPopoverContent` rather than a stand-in. The stand-in existed because
/// that view reported a single line's height when stacked in a column; it no longer does — its
/// width is decided before the text is laid out — and drawing the real thing is what makes this
/// artifact evidence about the screen rather than about a lookalike.
@MainActor
final class GlobalSettingsAnnotationTests: XCTestCase {

    /// The ⓘ text as the popover draws it, boxed so the sheet reads like the screen.
    private struct InfoText: View {
        let text: String

        var body: some View {
            InfoPopoverContent(text: text)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.token(Palette.surface))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(Color.token(Palette.border), lineWidth: Metrics.borderWidth)
                )
        }
    }

    private struct AnnotationSheet: View {
        let language: InterfaceLanguage

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(GlobalSettingsCatalog.settings, id: \.key) { setting in
                    HStack(alignment: .top, spacing: Spacing.lg) {
                        Text(setting.key)
                            .font(Typography.label)
                            .foregroundStyle(Color.token(Palette.textPrimary))
                            .frame(width: 200, alignment: .leading)
                        InfoText(text: Localization.text(setting.detail, language: language))
                    }
                }
            }
            .padding(Spacing.xl)
            .background(Color.token(Palette.windowBackground))
        }
    }

    /// Both sheets are written as review artefacts.
    func testBothLanguageSheetsAreWrittenForReview() throws {
        XCTAssertEqual(GlobalSettingsCatalog.settings.count, 6, "non-vacuity: six rows are drawn")
        let chinese = try Snapshot.writeArtifact(
            AnnotationSheet(language: .chinese), named: "global-settings-annotations", width: 700
        )
        let english = try Snapshot.writeArtifact(
            AnnotationSheet(language: .english), named: "global-settings-annotations-en", width: 700
        )
        XCTAssertGreaterThan(chinese.height, 200, "the sheet must hold every annotation")
        XCTAssertGreaterThan(english.height, 200, "the English sheet must hold every annotation")
    }

    /// The screen hands the badge `model.t(setting.detail)`, so the two languages have to render
    /// different text. If they did not, the language setting would make no difference to this page.
    func testEveryAnnotationDiffersBetweenTheTwoLanguages() {
        for setting in GlobalSettingsCatalog.settings {
            XCTAssertNotEqual(
                Localization.text(setting.detail, language: .chinese),
                Localization.text(setting.detail, language: .english),
                setting.key + " renders the same info text in both languages"
            )
        }
    }
}
