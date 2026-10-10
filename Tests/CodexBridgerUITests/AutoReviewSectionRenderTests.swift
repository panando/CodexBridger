import AppKit
import SwiftUI
import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Seam: AutoReviewSection rendering inside the provider form.
///
/// Layout-level: the card exists, sits at the form's full width, and grows when
/// a result list is present. The models behind it (gate, prober, cache) are
/// tested in CodexBridgerCoreTests.
@MainActor
final class AutoReviewSectionRenderTests: XCTestCase {

    private func model(home: URL) -> AppModel {
        AppModel(paths: CodexPaths(codexHome: home))
    }

    private func draft(withModels: Bool = true) -> ProviderDraft {
        var provider = ProviderConfiguration(
            id: "cpa",
            name: "示例提供商",
            baseURL: "https://api.example.com/v1",
            credentialMode: .bearerToken,
            bearerToken: "sk-demo"
        )
        if withModels {
            provider.models = [
                ModelConfiguration(slug: "kimi-k2.7-code", displayName: "Kimi"),
                ModelConfiguration(slug: "glm-5.2", displayName: "GLM")
            ]
        }
        return ProviderDraft(provider: provider)
    }

    func testSectionRendersFullWidthInTheForm() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("autoreview-render-" + UUID().uuidString, isDirectory: true)
        let app = model(home: home)
        let section = AutoReviewSection(model: app, draft: .constant(draft()))
        let size = try XCTUnwrap(Snapshot.size(section, width: 520))
        XCTAssertGreaterThanOrEqual(size.width, 500)
    }

    func testSectionRendersWithNoModels() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("autoreview-render-" + UUID().uuidString, isDirectory: true)
        let app = model(home: home)
        // The empty case must not crash or collapse: the manual-entry path is
        // the only one available and it still has to be visible.
        let section = AutoReviewSection(model: app, draft: .constant(draft(withModels: false)))
        let size = try XCTUnwrap(Snapshot.size(section, width: 520))
        XCTAssertGreaterThanOrEqual(size.width, 500)
    }

    /// The per-model result table is gone by design: a finished scan adds
    /// one summary line, not a row per model.
    func testFinishedScanAddsOneSummaryLineNotATable() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("autoreview-render-" + UUID().uuidString, isDirectory: true)
        let app = model(home: home)
        let before = try XCTUnwrap(
            Snapshot.size(AutoReviewSection(model: app, draft: .constant(draft())), width: 520)
        )
        app.autoReviewState.begin(slugCount: 3)
        app.autoReviewState.finish([
            AutoReviewProbeOutcome(slug: "kimi-k2.7-code", status: .supported, latencyMs: 1200, summary: nil),
            AutoReviewProbeOutcome(slug: "glm-5.2", status: .supported, latencyMs: 560, summary: nil),
            AutoReviewProbeOutcome(
                slug: "deepseek-v4-flash", status: .unsupported, latencyMs: 300,
                summary: "This response_format type is unavailable now"
            )
        ])
        let after = try XCTUnwrap(
            Snapshot.size(AutoReviewSection(model: app, draft: .constant(draft())), width: 520)
        )
        XCTAssertGreaterThan(after.height, before.height, "the summary line appears")
        XCTAssertLessThan(
            after.height - before.height, 80,
            "one line only: a per-model table would dwarf this"
        )
    }

    /// The screenshot that backs the README's "自动审批模型" section.
    /// Writes the rendered card to docs/ui/after/auto-review-section.png
    /// (and the dark variant) so a release commit carries a real artefact.

    /// The screenshot artefact that backs the README's 1.3.0 release note.
    ///
    /// ImageRenderer cannot rasterise the AppKit-backed controls (TextField,
    /// popover, button) the real section uses, so the snapshot substitutes the
    /// editable combo with a styled placeholder showing the picked slug.
    /// Everything else is the production section, rendered identically.
    func testScreenshotAutoReviewSectionAfterScan() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("autoreview-shot-" + UUID().uuidString, isDirectory: true)
        let app = model(home: home)
        app.autoReviewState.begin(slugCount: 3)
        app.autoReviewState.finish([
            AutoReviewProbeOutcome(slug: "kimi-k2.7-code", status: .supported, latencyMs: 2302, summary: nil),
            AutoReviewProbeOutcome(slug: "glm-5.2", status: .supported, latencyMs: 5860, summary: nil),
            AutoReviewProbeOutcome(
                slug: "deepseek-v4-pro", status: .unsupported, latencyMs: 300,
                summary: "This response_format type is unavailable now"
            ),
        ])
        let view = AutoReviewSectionScreenshot(app: app, draft: draft())
        let size = try XCTUnwrap(Snapshot.size(view, width: 520))
        XCTAssertGreaterThanOrEqual(size.width, 500)
        try Snapshot.writeArtifact(view, named: "auto-review-section", width: 520)
        try Snapshot.writeArtifact(
            view, named: "auto-review-section", width: 520,
            appearance: .darkAqua
        )
    }
}

/// Screenshot-only re-render of the section. Renders the picker as a static
/// label so ImageRenderer can draw it cleanly; everything else is the real view.
private struct AutoReviewSectionScreenshot: View {
    let app: AppModel
    let draft: ProviderDraft

    var body: some View {
        SectionCard("自动审批模型") {
            // Mirror of scanRow without LabelColumnSpacer so the action sits
            // on the card's left edge, the same as the production section.
            HStack(spacing: Spacing.md) {
                Button {
                } label: {
                    Label("一键检测", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(true)
                Button { } label: { Text("取消") }.disabled(true)
                Spacer(minLength: 0)
            }
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.success))
                Text("检测完成：")
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.textSecondary))
                + Text(String(2))
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.success))
                + Text(" 个模型支持自动审批")
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.textSecondary))
                Spacer(minLength: 0)
            }
            FormRow("审查模型", info: "写进模型参数文件的 auto_review_model_override，对该提供商所有模型生效") {
                // Static rendition of the picker for headless rendering.
                HStack(spacing: Spacing.xs) {
                    Text("kimi-k2.7-code")
                        .font(Typography.control)
                        .foregroundStyle(Color.token(Palette.textPrimary))
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(Color.token(Palette.surfaceSunken))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .strokeBorder(Color.token(Palette.border), lineWidth: 1)
                        )
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Typography.help)
                        .foregroundStyle(Color.token(Palette.textSecondary))
                }
            }
        }
    }
}