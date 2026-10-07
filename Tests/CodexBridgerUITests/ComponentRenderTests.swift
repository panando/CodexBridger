import AppKit
import SwiftUI
import XCTest
@testable import CodexBridgerUI
@testable import CodexBridgerCore

/// Renders every component in every state that used to be undefined, asserts the
/// measurable parts, and writes the PNGs that back the review screenshots.
@MainActor
final class ComponentRenderTests: XCTestCase {

    private var scratchHome: URL {
        URL(fileURLWithPath: "/tmp/codexbridger-ui-tests", isDirectory: true)
    }

    private func makeModel() -> AppModel {
        AppModel(paths: CodexPaths(codexHome: scratchHome))
    }

    private func sampleProvider() -> ProviderConfiguration {
        var provider = ProviderConfiguration(
            id: "demo",
            name: "示例提供商",
            baseURL: "https://api.example.com/v1",
            credentialMode: .bearerToken,
            requiresOpenAIAuth: true,
            bearerToken: "sk-demo",
            models: [
                ModelConfiguration(
                    slug: "demo-large",
                    displayName: "Demo Large",
                    modelDescription: "示例大模型",
                    contextWindow: 200_000,
                    maxContextWindow: 200_000,
                    supportedReasoningEfforts: [.low, .medium, .high, .xhigh],
                    defaultReasoningEffort: .high
                ),
                ModelConfiguration(slug: "demo-small", displayName: "Demo Small", contextWindow: 64_000)
            ]
        )
        provider.queryParams = ["api-version": "2025-04-01"]
        return provider
    }

    /// A dropdown long enough that the previous implementation wrapped to two lines.
    private var longOptionField: some View {
        SelectField(
            options: ProviderCredentialMode.allCases.map {
                SelectField<ProviderCredentialMode>.Option(value: $0, title: $0.displayName)
            },
            selection: .constant(.bearerToken),
            accessibilityLabel: "认证方式"
        )
    }

    // MARK: - Sizing

    /// A full-width control is an easy target even when it is shorter than 44pt: WCAG 2.1 AA
    /// sets no minimum target size (that is SC 2.5.5 at AAA). Padding these out to 44pt doubled
    /// the row pitch and made the form read far more loosely than the reference. Small controls
    /// (icon buttons, switches, checkboxes) keep the 44pt floor.
    func testSelectFieldStaysUsableAndFullWidth() throws {
        let size = try XCTUnwrap(Snapshot.size(longOptionField, width: 320))
        XCTAssertGreaterThanOrEqual(size.height, Metrics.minDenseHitTarget)
        XCTAssertGreaterThanOrEqual(size.width, 300, "the control fills the column")
    }

    func testLongSelectedValueStaysOnOneLine() throws {
        let long = try XCTUnwrap(Snapshot.size(longOptionField, width: 320))
        let short = try XCTUnwrap(
            Snapshot.size(
                SelectField(
                    options: [SelectField<Int>.Option(value: 1, title: "低")],
                    selection: .constant(1),
                    accessibilityLabel: "短"
                ),
                width: 320
            )
        )
        XCTAssertEqual(
            long.height, short.height, accuracy: 1,
            "a long selected value must truncate, not wrap the control onto two lines"
        )
    }

    func testValueTextFieldMeetsMinimumHitHeight() throws {
        for state in 0..<3 {
            let field = ValueTextField(
                text: .constant(state == 2 ? "" : "https://api.example.com/v1"),
                prompt: state == 2 ? "占位符" : "",
                isEnabled: state != 1,
                isInvalid: state == 2,
                accessibilityLabel: "字段"
            )
            let size = try XCTUnwrap(Snapshot.size(field, width: 320))
            // See testSelectFieldStaysUsableAndFullWidth for why the dense floor applies here.
            XCTAssertGreaterThanOrEqual(size.height, Metrics.minDenseHitTarget)
        }
    }

    func testCheckboxMeetsMinimumHitSize() throws {
        let checkbox = CheckboxControl(isOn: .constant(true), accessibilityLabel: "开关")
        let size = try XCTUnwrap(Snapshot.size(checkbox, width: 120))
        XCTAssertGreaterThanOrEqual(size.width, Metrics.minHitTarget)
        XCTAssertGreaterThanOrEqual(size.height, Metrics.minHitTarget)
    }

    func testIconButtonMeetsMinimumHitSize() throws {
        let button = IconButton(systemName: "trash", label: "删除", role: .destructive) {}
        let size = try XCTUnwrap(Snapshot.size(button, width: 120))
        XCTAssertGreaterThanOrEqual(size.width, Metrics.minHitTarget)
        XCTAssertGreaterThanOrEqual(size.height, Metrics.minHitTarget)
    }

    // MARK: - Artefacts

    func testWriteFormRowArtefacts() throws {
        let content = VStack(alignment: .leading, spacing: Spacing.md) {
            FormRow("标识符", help: "写入 config.toml 的 [model_providers.标识符]", isRequired: true) {
                ValueTextField(text: .constant("provider"), accessibilityLabel: "标识符")
            }
            FormRow("显示名称", isRequired: true) {
                ValueTextField(text: .constant("新提供商"), accessibilityLabel: "显示名称")
            }
            FormRow("base_url", help: "第三方服务的 API 地址") {
                ValueTextField(text: .constant("http://127.0.0.1:8000/v1"), accessibilityLabel: "base_url")
            }
            FormRow("一个很长的字段名用于验证换行对齐", help: "这一行的说明文字也刻意变长，用来检查对齐是否稳定") {
                ValueTextField(text: .constant("value"), accessibilityLabel: "长字段")
            }
            FormRow("校验失败") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ValueTextField(text: .constant("has.dot"), isInvalid: true, accessibilityLabel: "非法值")
                    InlineError("只能使用字母、数字、下划线和连字符")
                }
            }
            FormRow("禁用状态") {
                ValueTextField(text: .constant("不可编辑"), isEnabled: false, accessibilityLabel: "禁用")
            }
        }
        .padding(Spacing.lg)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let size = try Snapshot.writeArtifact(content, named: "form-rows", appearance: appearance)
            XCTAssertGreaterThanOrEqual(size.height, Metrics.minHitTarget * 4)
        }
    }

    func testWriteSelectionArtefacts() throws {
        let content = VStack(alignment: .leading, spacing: Spacing.md) {
            FormRow("认证方式") { longOptionField }
            FormRow("能力声明") {
                SelectField(
                    options: [
                        SelectField<String?>.Option(value: nil, title: "不写入"),
                        SelectField<String?>.Option(value: "true", title: "true"),
                        SelectField<String?>.Option(value: "false", title: "false")
                    ],
                    selection: .constant("true"),
                    accessibilityLabel: "布尔选项"
                )
                .frame(maxWidth: 220)
            }
            FormRow("不可用") {
                SelectField(
                    options: [SelectField<Int>.Option(value: 1, title: "禁用状态")],
                    selection: .constant(1),
                    isEnabled: false,
                    accessibilityLabel: "禁用下拉框"
                )
                .frame(maxWidth: 220)
            }
            FormRow("状态输入") {
                ValueTextField(text: .constant(""), prompt: "占位符", accessibilityLabel: "空字段")
            }
        }
        .padding(Spacing.lg)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try Snapshot.writeArtifact(content, named: "select-and-fields", appearance: appearance)
        }
    }

    func testWriteControlStateArtefacts() throws {
        let content = VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.lg) {
                CheckboxControl(isOn: .constant(true), accessibilityLabel: "开")
                CheckboxControl(isOn: .constant(false), accessibilityLabel: "关")
                CheckboxControl(isOn: .constant(true), isEnabled: false, accessibilityLabel: "禁用")
            }
            HStack(spacing: Spacing.md) {
                IconButton(systemName: "plus", label: "添加") {}
                IconButton(systemName: "minus", label: "删除", role: .destructive) {}
                IconButton(systemName: "plus", label: "禁用", isEnabled: false) {}
                PrimaryActionButton(title: "激活并写入 Codex") {}
                PrimaryActionButton(title: "处理中", isBusy: true) {}
            }
            HStack(spacing: Spacing.sm) {
                Pill("当前已激活", tone: .success)
                Pill("默认", tone: .neutral)
                Pill("错误", tone: .danger)
            }
        }
        .padding(Spacing.lg)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try Snapshot.writeArtifact(content, named: "control-states", appearance: appearance)
        }
    }

    func testWriteFeedbackArtefacts() throws {
        let longMessage = String(repeating: "这是一条很长的提示信息，用来确认换行后图标仍然与第一行文字对齐。", count: 3)
        let content = VStack(alignment: .leading, spacing: Spacing.md) {
            StatusBanner(kind: .info, message: "正在生成 Codex 配置…")
            StatusBanner(kind: .success, message: "已激活 示例提供商 · demo-large")
            StatusBanner(kind: .failure, message: longMessage)
            Divider()
            DisclosureSection(title: "折叠状态", subtitle: "点击展开", isExpanded: .constant(false)) {
                HelpText("内容")
            }
            DisclosureSection(title: "展开状态", subtitle: "点击折叠", isExpanded: .constant(true)) {
                FormRow("query_params", help: "每行一个 key = value") {
                    KeyValueLinesEditor(
                        dictionary: .constant([:]),
                        placeholder: "api-version = 2025-04-01",
                        accessibilityLabel: "query_params"
                    )
                }
                FormRow("已填写") {
                    KeyValueLinesEditor(
                        dictionary: .constant(["X-Tenant": "acme"]),
                        placeholder: "X-Tenant = acme",
                        accessibilityLabel: "http_headers"
                    )
                }
            }
        }
        .padding(Spacing.lg)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try Snapshot.writeArtifact(content, named: "feedback-and-disclosure", appearance: appearance)
        }
    }

    func testWriteEmptyStateArtefact() throws {
        let view = EmptyStateView(
            title: "还没有配置模型提供商",
            message: "添加一个第三方提供商，配置它的模型，然后点激活即可写入 Codex。",
            actionTitle: "添加提供商",
            action: {}
        )
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try Snapshot.writeArtifact(view, named: "empty-state", width: 640, appearance: appearance)
        }
    }

    /// The main configuration screen, matching the reference layout.
    func testWriteProviderConfigArtefact() throws {
        let model = makeModel()
        let provider = sampleProvider()
        let draft = Binding(
            get: { ProviderDraft(provider: provider, existingIDs: ["other"]) },
            set: { _ in }
        )
        // The form body, not the ScrollView: ImageRenderer gives a ScrollView no intrinsic
        // height, so rendering the whole screen produced a blank body.
        let view = ProviderFormBody(model: model, draft: draft)
            .background(Color.token(Palette.windowBackground))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let size = try Snapshot.writeArtifact(
                view, named: "provider-form", width: 900, appearance: appearance
            )
            XCTAssertGreaterThan(size.height, 500, "the form should render its sections")
        }
    }

    /// The same screen with every field broken, to show the error state.
    func testWriteProviderConfigErrorStateArtefact() throws {
        let model = makeModel()
        var broken = sampleProvider()
        broken.id = ""
        broken.name = "  "
        broken.baseURL = "not-a-url"
        broken.bearerToken = ""
        broken.models[0].maxContextWindow = 1
        let draft = Binding(
            get: { ProviderDraft(provider: broken, existingIDs: ["other"]) },
            set: { _ in }
        )
        let view = ProviderFormBody(model: model, draft: draft)
            .background(Color.token(Palette.windowBackground))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try Snapshot.writeArtifact(
                view, named: "provider-form-errors", width: 900, appearance: appearance
            )
        }
    }

    /// The onboarding screen, matching the reference empty state.
    func testWriteOnboardingArtefact() throws {
        // The onboarding copy is language-dependent, so it needs a model to resolve against.
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("onboarding-" + UUID().uuidString, isDirectory: true)
        let view = OnboardingView(model: AppModel(paths: CodexPaths(codexHome: home)), onCreate: {})
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let size = try Snapshot.writeArtifact(
                view, named: "onboarding", width: 820, appearance: appearance
            )
            XCTAssertGreaterThan(size.height, 500)
        }
    }

    func testWritePresetPickerArtefact() throws {
        let view = PresetPickerSheet(
            onPick: { _ in }, onPickBlank: {}, onPickCatalogFile: {}, onCancel: {}
        )
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let size = try Snapshot.writeArtifact(
                view, named: "preset-picker", width: 560, appearance: appearance
            )
            XCTAssertGreaterThan(size.height, 400)
        }
    }

    func testWriteModelEditorArtefact() throws {
        let view = ModelEditorSheet(
            model: sampleProvider().models[0],
            onSave: { _ in },
            onCancel: {}
        )
        .background(Color.token(Palette.windowBackground))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try Snapshot.writeArtifact(view, named: "model-editor", width: 560, appearance: appearance)
        }
    }

    /// The import sheet, in the state it opens in: no file chosen yet, nothing to select.
    func testWriteModelCatalogImportArtefact() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-sheet-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let view = ModelCatalogImportSheet(
            title: "从模型参数文件导入模型",
            catalogsDirectory: directory,
            existingSlugs: ["demo-large"],
            onConfirm: { _ in },
            onCancel: {}
        )
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let size = try Snapshot.writeArtifact(
                view, named: "model-catalog-import", width: 620, appearance: appearance
            )
            XCTAssertGreaterThan(size.height, 500)
        }
    }

    func testWriteSettingsArtefact() throws {
        let view = DesignSettingsView(model: makeModel())
            .background(Color.token(Palette.windowBackground))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try Snapshot.writeArtifact(view, named: "settings", width: 560, appearance: appearance)
        }
    }

    // MARK: - Stress

    func testProviderListRowRendersLongTextWithoutOverflow() throws {
        let provider = ProviderConfiguration(
            id: "extremely-long-provider-identifier-that-should-truncate",
            name: String(repeating: "很长的提供商名称 ", count: 6),
            baseURL: "https://example.com",
            models: [ModelConfiguration(slug: "m", displayName: "M")]
        )
        let row = ProviderRow(
            provider: provider, isActive: true, isSelected: false,
            inUseLabel: "使用中", missingAddressLabel: "还没填地址"
        )
        let size = try XCTUnwrap(Snapshot.size(row, width: 240))
        XCTAssertLessThanOrEqual(size.width, 241, "row must respect the sidebar width")
        XCTAssertGreaterThanOrEqual(size.height, Metrics.minHitTarget)
    }

    func testMappingCardRendersLongValuesWithoutOverflow() throws {
        let model = ModelConfiguration(
            slug: "an-extremely-long-model-slug-that-must-truncate-in-the-middle",
            displayName: String(repeating: "很长的模型名称 ", count: 4),
            contextWindow: 1_000_000,
            supportedReasoningEfforts: ReasoningEffort.all,
            defaultReasoningEffort: .ultra
        )
        let card = ProviderMappingCard(
            model: model,
            isVisible: .constant(true),
            isExpanded: .constant(false),
            slug: .constant(model.slug),
            displayName: .constant(model.displayName),
            defaultReasoningEffort: .constant(model.defaultReasoningEffort),
            visibility: .constant(model.visibility),
            priority: .constant(String(model.priority)),
            supportedReasoningEfforts: .constant(Set(model.supportedReasoningEfforts)),            contextWindow: .constant(String(model.contextWindow)),
            maxContextWindow: .constant(String(model.maxContextWindow)),
            canMoveUp: false,
            canMoveDown: false,
            onMoveUp: {}, onMoveDown: {}, onEdit: {}, onDelete: {}
        )
        let size = try XCTUnwrap(Snapshot.size(card, width: 620))
        XCTAssertLessThanOrEqual(size.width, 621)
        XCTAssertGreaterThanOrEqual(size.height, Metrics.minHitTarget)
    }

    func testMappingCardShowsItsErrors() throws {
        let model = ModelConfiguration(slug: "m", displayName: "M")
        let card = ProviderMappingCard(
            model: model,
            isVisible: .constant(false),
            issues: [
                FieldIssue(field: .models, severity: .error,
                           message: "max_context_window 不能小于 context_window", subject: "m")
            ],
            isExpanded: .constant(true),
            slug: .constant(model.slug),
            displayName: .constant(model.displayName),
            defaultReasoningEffort: .constant(model.defaultReasoningEffort),
            visibility: .constant(model.visibility),
            priority: .constant(String(model.priority)),
            supportedReasoningEfforts: .constant(Set(model.supportedReasoningEfforts)),            contextWindow: .constant(String(model.contextWindow)),
            maxContextWindow: .constant(String(model.maxContextWindow)),
            canMoveUp: false,
            canMoveDown: false,
            onMoveUp: {}, onMoveDown: {}, onEdit: {}, onDelete: {}
        )
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try Snapshot.writeArtifact(card, named: "mapping-card-expanded", width: 620,
                                       appearance: appearance)
        }
    }
}
