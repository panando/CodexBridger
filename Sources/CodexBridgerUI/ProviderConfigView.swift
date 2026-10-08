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

    /// Whether this provider is the one ChatGPT is using.
    private var isAlreadyActive: Bool {
        model.configuration.activeProviderID == draft.original.id
    }

    /// Whether the files already hold exactly this provider.
    ///
    /// Compared against what the last activation recorded, with the model list and the id
    /// included (both reach the files) and `category` ignored (it never leaves this app). Saving
    /// a change makes this false again, which is what brings the button back.
    private var isAlreadyPublished: Bool {
        guard let published = model.configuration.publishedProvider else { return false }
        return published.hasSameAppliedState(as: draft.provider)
    }

    /// Whether the primary action can be used, and what it should say.
    ///
    /// The rule lives in `ActivationAction` so it can be tested directly; see the contract there.
    private var activationAvailability: ActivationAction.Availability {
        ActivationAction.availability(
            hasModels: !provider.models.isEmpty,
            isDirty: draft.isDirty,
            hasErrors: !draft.errors.isEmpty,
            isAlreadyActive: isAlreadyActive,
            isAlreadyPublished: isAlreadyPublished
        )
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
                // The activation result. Without this the button rewrote config.toml and the
                // model parameter file and said nothing, which reads as a dead button.
                if !model.status.isEmpty, model.status.kind != .idle {
                    StatusBanner(kind: model.status.bannerKind, message: model.status.message)
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
                Button(model.t(activationAvailability.title)) {
                    model.requestActivation(
                        providerID: draft.original.id,
                        modelID: provider.models.first?.id ?? UUID()
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!activationAvailability.isEnabled)
                .help(model.t(activationAvailability.help))
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Metrics.actionBarVerticalPadding)
            .frame(height: Metrics.actionBarHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.token(Palette.surface))
    }
}
