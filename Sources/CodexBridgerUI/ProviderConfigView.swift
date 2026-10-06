import SwiftUI
import CodexBridgerCore

/// The provider configuration screen.
///
/// Layout follows the reference screen: small grey section captions, a narrow right-aligned
/// label column, full-width controls, the interface-type row occupying the slot it does in the
/// reference, and model mappings as bordered cards. The reference applies changes immediately;
/// this screen cannot, because the change ends up in the file Codex reads, so it edits a draft
/// and exposes Save and Reset.
public struct ProviderConfigView: View {
    @ObservedObject private var model: AppModel
    @Binding private var draft: ProviderDraft

    public init(model: AppModel, draft: Binding<ProviderDraft>) {
        self.model = model
        self._draft = draft
    }

    private var provider: ProviderConfiguration { draft.provider }

    /// Saving is available when there is something to save, and only then.
    ///
    /// This was inverted once: with `!draft.isDirty` the button read as available exactly when
    /// there was nothing to write, so an untouched provider showed a live Save and the button
    /// greyed out as soon as you actually changed something. Both halves are wrong-looking states
    /// on their own, which is why it is asserted directly below rather than left to inspection.
    var canSave: Bool {
        draft.isDirty && draft.canSave && model.editorPhase != .saving
    }

    /// Once this provider and model are what Codex already points at, the button stays disabled
    /// and says so, rather than offering a no-op that rewrites the same files and looks like
    /// nothing happened.
    private var isAlreadyActive: Bool {
        model.configuration.activeProviderID == draft.original.id
    }

    private var canActivate: Bool {
        !provider.models.isEmpty && !draft.isDirty && draft.errors.isEmpty && !isAlreadyActive
    }

    /// The primary button only earns its emphasis while it can be used.
    ///
    /// macOS draws a disabled `.borderedProminent` as a solid grey block, noticeably heavier
    /// than the outlined buttons beside it, so an idle action bar had one button that looked
    /// louder than the rest while doing nothing. A primary that is unavailable drops back to the
    /// plain bordered style, which keeps all three disabled buttons reading as one row.
    private struct ProminentWhileAvailable: ViewModifier {
        let isAvailable: Bool

        func body(content: Content) -> some View {
            if isAvailable {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }

    /// Says why the button is unavailable, instead of one message for every reason.
    private var activateHelpText: String {
        if isAlreadyActive { return "ChatGPT 已经在用这个提供商了" }
        if provider.models.isEmpty { return "需要至少一个模型" }
        if !draft.errors.isEmpty { return "先解决表单里的错误" }
        if draft.isDirty { return "需要先保存" }
        return "把这份配置写进 ChatGPT"
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                ProviderFormBody(model: model, draft: $draft)
            }
            actionBar
        }
        .background(Color.token(Palette.windowBackground))
        .sheet(item: Binding(
            get: { model.editingModelID.flatMap { id in
                draft.provider.models.first { $0.id == id }
            } },
            set: { model.editingModelID = $0?.id }
        )) { entry in
            ModelEditorSheet(model: entry) { updated in
                if let index = draft.provider.models.firstIndex(where: { $0.id == updated.id }) {
                    draft.provider.models[index] = updated
                }
                model.editingModelID = nil
            } onCancel: {
                model.editingModelID = nil
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Spacing.md) {
                // Only feedback that follows an action belongs here. Standing hints were
                // removed: every validation problem is already shown against its own field, and
                // the Save button's own state already says whether there is unsaved work.
                if model.editorPhase.isError {
                    StatusBanner(kind: .failure, message: model.editorPhase.message)
                } else if model.editorPhase.isSuccess {
                    StatusBanner(kind: .success, message: model.editorPhase.message)
                }
                Spacer(minLength: Spacing.md)
                Button(draft.isNew ? model.t("取消") : model.t("重置")) { model.resetDraft() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!draft.isDirty)
                    .help("放弃未保存的修改，回到磁盘上的内容")
                Button(model.editorPhase == .saving ? model.t("保存中…") : model.t("保存")) { model.saveDraft() }
                    .controlSize(.large)
                    .modifier(ProminentWhileAvailable(isAvailable: canSave))
                    .disabled(!canSave)
                Button(model.t("启用")) {
                    model.requestActivation(
                        providerID: draft.original.id,
                        modelID: provider.models.first?.id ?? UUID()
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!canActivate)
                .help(activateHelpText)
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Metrics.actionBarVerticalPadding)
            .frame(height: Metrics.actionBarHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.token(Palette.surface))
    }
}
