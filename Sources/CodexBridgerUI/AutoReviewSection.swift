import SwiftUI
import CodexBridgerCore

/// The 自动审批模型 card: one provider-level reviewer model for the whole
/// provider, chosen from the models a 一键检测 proved, with manual entry
/// always available.
///
/// Placement is deliberate: between 认证 and 模型配置, because the section both
/// depends on the credential above (probes need it) and reads the model list
/// below (the models it probes are the ones configured there).
public struct AutoReviewSection: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var state: AutoReviewScanState
    @Binding private var draft: ProviderDraft

    public init(model: AppModel, draft: Binding<ProviderDraft>) {
        self.model = model
        self._state = ObservedObject(wrappedValue: model.autoReviewState)
        self._draft = draft
    }

    private var verdict: AutoReviewGate.Verdict {
        model.autoReviewVerdict(
            draft: draft,
            credential: model.autoReviewCredential(for: draft)
        )
    }

    public var body: some View {
        SectionCard(model.t("自动审批模型")) {
            scanRow
            if state.isScanning { progressRow }
            finishNotice
            valueRow
        }
        .sheet(isPresented: oneTimeKeySheet) {
            oneTimeKeySheetContent
        }
    }

/// Left edge of the 审查模型 label inside a FormRow.
///
/// FormRow right-aligns its label in a Metrics.labelColumnWidth cell and
/// follows it with Metrics.labelToControlGap, so a label's own left edge sits
/// at labelColumnWidth minus the label's width (and its info badge). The
/// section's action rows align to that edge rather than to the card's left
/// padding or to the control column, so 一键检测 reads as the label's action.
private static let reviewerLabelLeftEdge: CGFloat =
    Metrics.labelColumnWidth - 51.6 - 18

    // MARK: Scan

    private var scanRow: some View {
        // Left edge aligns with the 审查模型 label below, not with the input
        // column: this row is an action, not a field value.
        HStack(spacing: Spacing.md) {
            Button {
                startScan()
            } label: {
                Label("一键检测", systemImage: "dot.radiowaves.left.and.right")
            }
            .disabled(!verdict.canScan)
            Button {
                model.autoReviewState.cancel()
            } label: {
                Text("取消")
            }
            .disabled(!state.isScanning)
            if !verdict.scanHint.isEmpty {
                HelpText(verdict.scanHint)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, Self.reviewerLabelLeftEdge)
    }

    private func startScan() {
        switch model.autoReviewCredential(for: draft) {
        case .needsOneTimeKey:
            state.oneTimeKeyInput = ""
            state.isOneTimeKeySheetPresented = true
        default:
            model.startAutoReviewScan(draft: draft, oneTimeKey: nil)
        }
    }

    private var progressRow: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView(value: Double(state.progress.count), total: Double(max(state.total, 1)))
                .frame(width: 120)
            HelpText(
                "检测中 " + String(state.progress.count) + "/" + String(state.total)
                    + (state.progress.last.map { " · " + $0.slug } ?? "")
            )
            Spacer(minLength: 0)
        }
        .padding(.leading, Self.reviewerLabelLeftEdge)
    }

    /// One line instead of a per-model table: how many models cleared the
    /// check. The per-model detail is what the 审查模型 dropdown carries.
    @ViewBuilder
    private var finishNotice: some View {
        if !state.isScanning, !state.results.isEmpty {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.success))
                let supported = state.results.filter { $0.status == .supported }.count
                Text("检测完成：")
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.textSecondary))
                + Text(String(supported))
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.success))
                + Text(" 个模型支持自动审批")
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.textSecondary))
                Spacer(minLength: 0)
            }
            .padding(.leading, Self.reviewerLabelLeftEdge)
        }
    }

    // MARK: Value

    private var valueRow: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            FormRow(
                model.t("审查模型"),
                info: "写进模型参数文件的 auto_review_model_override，对该提供商所有模型生效",
                isRequired: false
            ) {
                valueControl
            }
            staleWarning
            manualWarning
        }
    }

    private var valueControl: some View {
        // One control for both paths: it types freely, and the candidates a
        // scan proved appear as a dropdown while it is focused. When no scan
        // has passed anything the list is simply empty and typing is all
        // there is.
        EditableSelectField(
            options: verdict.candidateSlugs,
            text: Binding(
                get: { draft.provider.autoReviewModelOverride ?? "" },
                set: { newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.provider.autoReviewModelOverride = trimmed.isEmpty ? nil : trimmed
                }
            ),
            accessibilityLabel: "自动审批模型"
        )
    }

    @ViewBuilder
    private var staleWarning: some View {
        if verdict.cacheIsStale {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.warning))
                HelpText("模型列表和上次检测时不一样，结果可能过期，建议重新检测")
            }
        }
    }

    @ViewBuilder
    private var manualWarning: some View {
        let value = draft.provider.autoReviewModelOverride ?? ""
        if !value.isEmpty,
           verdict.canPickFromScan,
           !verdict.candidateSlugs.contains(value) {
            HelpText("手动输入的模型名没有通过检测，能不能用来审查要服务商认")
        }
    }

    // MARK: One-time key sheet

    private var oneTimeKeySheet: Binding<Bool> {
        Binding(
            get: { state.isOneTimeKeySheetPresented },
            set: { state.isOneTimeKeySheetPresented = $0 }
        )
    }

    private var oneTimeKeySheetContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("输入一次性 API Key")
                .font(Typography.sectionTitle)
            HelpText("这个认证方式的凭据来自环境变量或外部命令，检测拿不到。"
                        + "在这里粘贴的 Key 只在本次检测的内存里使用，不会写入任何文件。")
            SecretTextField(
                text: $state.oneTimeKeyInput,
                accessibilityLabel: "一次性 API Key"
            )
            HStack(spacing: Spacing.md) {
                Button("开始检测") {
                    let key = state.oneTimeKeyInput
                    state.isOneTimeKeySheetPresented = false
                    model.startAutoReviewScan(draft: draft, oneTimeKey: key)
                }
                .disabled(
                    state.oneTimeKeyInput
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                Button("取消") { state.isOneTimeKeySheetPresented = false }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(width: 420)
    }
}