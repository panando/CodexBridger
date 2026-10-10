import Foundation
import SwiftUI
import CodexBridgerCore

/// Application state for the window.
///
/// The model owns the persisted configuration, mirrors what Codex currently has on
/// disk, and performs activation. Views never touch the filesystem themselves.
@MainActor
public final class AppModel: ObservableObject {

    /// What the last action that writes files had to say, drawn by the provider screen's action
    /// bar.
    ///
    /// Reported 2026-10-08: "pressing 更新配置 leaves the button lit, as if the click was
    /// ignored". The write did happen — this channel was being filled in all along — but no
    /// view read it, so the screen never said so. `persist()` also used to write here ("saved
    /// to <path>", about this app's own settings file), which no view read either and which
    /// would have been noise on the provider screen; that write is gone.
    public struct Status: Equatable {
        public enum Kind { case idle, success, failure }
        public var kind: Kind
        public var message: String

        public init(kind: Kind = .idle, message: String = "") {
            self.kind = kind
            self.message = message
        }

        public static let idle = Status()
        public static func success(_ message: String) -> Status { Status(kind: .success, message: message) }
        public static func failure(_ message: String) -> Status { Status(kind: .failure, message: message) }

        public var isEmpty: Bool { message.isEmpty }

        public var bannerKind: StatusBanner.Kind {
            switch kind {
            case .idle: return .info
            case .success: return .success
            case .failure: return .failure
            }
        }
    }

    /// Which screen the detail pane shows.
    public enum Section: Equatable, CaseIterable {
        case providers
        case globalSettings
    }

    /// The outcome of the last "update configuration" on the global settings screen.
    public struct GlobalSettingsNotice: Equatable {
        public enum Kind: Equatable { case success, warning, failure }
        public var kind: Kind
        public var message: String

        public init(kind: Kind, message: String) {
            self.kind = kind
            self.message = message
        }
    }

    @Published public var configuration: CodexBridgerConfiguration = CodexBridgerConfiguration()
    @Published public var selectedProviderID: String?
    /// Which screen the detail pane is showing.
    @Published public var selectedSection: Section = .providers
    /// What config.toml holds for the keys the global settings screen shows.
    @Published public var globalSettingsStates: [String: GlobalSettingState] = [:]
    /// The pending edits on that screen.
    @Published public var globalSettingsDraft = GlobalSettingsDraft(loaded: [:])
    /// Keys the user changed that somebody else changed too.
    @Published public var globalSettingsConflicts: [GlobalSettingsConflict] = []
    /// The outcome of the last update.
    @Published public var globalSettingsNotice: GlobalSettingsNotice?
    /// The provider screen's action result; see the note on `Status`.
    @Published public var status: Status = .idle
    @Published public var snapshot: CodexConfigSnapshot = CodexConfigSnapshot()
    @Published public var authKeyNames: [String] = []
    @Published public var lastActivation: ActivationResult?
    @Published public var loadErrorMessage: String?
    @Published public var isActivating = false
    /// Set when an activation would replace a different active provider.
    @Published public var pendingActivation: PendingActivation?
    /// Set when a delete is waiting for the user to agree to it; see `PendingDeletion`.
    @Published public var pendingDeletion: PendingDeletion?
    @Published public var templateSourceDescription: String = "内置模板（已用 ChatGPT 校验）"
    /// 一键检测 lifecycle for the 自动审批模型 section.
    @Published public var autoReviewState = AutoReviewScanState()
    /// Builds the prober for one scan run. Production uses the shared session;
    /// tests substitute a stubbed transport so no test touches the network.
    public var autoReviewProberFactory: () -> AutoReviewProbe = {
        AutoReviewProbe(session: .shared, maxConcurrent: 3, timeout: 60)
    }

    /// Bumped on every activation message, so a pending auto-dismiss cannot clear a newer one.
    private var activationNoticeToken = 0

    public let paths: CodexPaths
    private let store: ConfigurationStore

    public init(paths: CodexPaths = CodexPaths()) {
        self.paths = paths
        self.store = ConfigurationStore(paths: paths)
        // Read the stored configuration before the first view is evaluated.
        //
        // This used to run from `.task`, which fires *after* the first render, so the window
        // could be committed showing an empty sidebar and an empty detail pane and then fill
        // itself in on the next pass — a first frame that does not match the final image. The
        // read is a small local JSON file, so doing it here costs nothing and makes the first
        // frame the same as every frame after it.
        load()
    }

    // MARK: - Lifecycle

    public func load() {
        do {
            configuration = try store.load()
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        if selectedProviderID == nil {
            selectedProviderID = configuration.activeProviderID ?? configuration.providers.first?.id
        }
        // Establish the editor draft here too.
        //
        // The view used to do this from `.task`, which runs after the first render, so the very
        // first frame showed the empty state — the "no providers yet" screen the user reported
        // flashing on every launch — and then filled in. Both panes now have their content
        // before any view is evaluated.
        if draft == nil, let id = selectedProviderID {
            beginEditing(providerID: id)
        }
        refreshCodexState()
        resolveTemplateSource()
    }

    /// Resolves a source string in the configured interface language.
    ///
    /// Keyed on the Chinese source text, so anything not yet translated still reads correctly.
    public func t(_ source: String) -> String {
        Localization.text(source, language: configuration.interfaceLanguage)
    }

    /// The language actually in effect, with `system` already resolved.
    public var resolvedLanguage: InterfaceLanguage {
        Localization.resolved(configuration.interfaceLanguage)
    }

    /// Changes the interface language and stores it.
    public func setLanguage(_ language: InterfaceLanguage) {
        guard configuration.interfaceLanguage != language else { return }
        configuration.interfaceLanguage = language
        persist()
    }

    /// Reports which catalog template will be used, without writing anything.
    public func resolveTemplateSource() {
        let slug = configuration.catalogTemplateSlug
        Task.detached(priority: .utility) {
            let description = CatalogTemplateResolver(preferredSlug: slug).sourceDescription
            await MainActor.run { self.templateSourceDescription = description }
        }
    }

    public func refreshCodexState() {
        let reader = CodexConfigReader(paths: paths)
        snapshot = reader.snapshot()
        authKeyNames = reader.authKeyNames()
    }

    /// Writes this app's own settings file.
    ///
    /// It reports nothing to the user on purpose: every caller is a small in-memory change that
    /// rewrites the same file, and "已保存到 …/codexbridger/config.json" is bookkeeping about
    /// this app's storage rather than news about the provider.
    public func persist() {
        try? store.save(configuration)
    }

    // MARK: - Provider CRUD

    public func provider(id: String) -> ProviderConfiguration? {
        configuration.providers.first { $0.id == id }
    }

    public func providerBinding(_ id: String) -> Binding<ProviderConfiguration>? {
        guard let index = configuration.providers.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return Binding(
            get: { [weak self] in
                guard let self, self.configuration.providers.indices.contains(index) else {
                    return ProviderConfiguration(id: id, name: "", baseURL: "")
                }
                return self.configuration.providers[index]
            },
            set: { [weak self] newValue in
                guard let self, self.configuration.providers.indices.contains(index) else { return }
                self.configuration.providers[index] = newValue
            }
        )
    }

    // MARK: - Draft editing

    /// What the form is doing right now, driving the loading/error/success feedback.
    public enum EditorPhase: Equatable {
        case idle
        case editing
        case saving
        case saved(String)
        case failed(String)

        public var message: String {
            switch self {
            case .idle, .editing: return ""
            case .saving: return "正在保存…"
            case let .saved(text), let .failed(text): return text
            }
        }

        public var isError: Bool {
            if case .failed = self { return true }
            return false
        }

        public var isSuccess: Bool {
            if case .saved = self { return true }
            return false
        }
    }

    /// The provider being edited. Nil when nothing is selected.
    @Published public var draft: ProviderDraft?
    @Published public var editorPhase: EditorPhase = .idle

    /// Bumped each time a transient notice is published, so a pending auto-dismiss timer can
    /// tell that it has been superseded and must not clear a newer message.
    private var phaseToken = 0

    /// How long a success notice stays before clearing itself. A success notice is just news:
    /// nothing depends on it, so it should not sit at the bottom of the window indefinitely.
    /// Failure notices are deliberately not timed out — a failed write may be explained nowhere
    /// else, so it stays until the next action replaces it.
    private static let successNoticeSeconds: Double = 3

    /// Publishes a notice that clears itself, unless a newer one arrives first.
    private func publishTransient(_ phase: EditorPhase) {
        editorPhase = phase
        phaseToken += 1
        let token = phaseToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.successNoticeSeconds * 1_000_000_000))
            guard let self, token == self.phaseToken else { return }
            self.editorPhase = .editing
        }
    }
    @Published public var isShowingPresetPicker = false

    /// An import the user has started, and where its models should go.
    ///
    /// Driving the sheet from the model (rather than from local view state) keeps a single sheet
    /// for both entry points: the button beside the model list, and the "new provider" flow.
    public struct CatalogImportRequest: Identifiable, Equatable {
        public enum Target: Equatable {
            /// Add the models to the provider currently open in the form.
            case draftProvider
            /// Create a provider whose model list comes from the file.
            case newProvider
        }

        public let id: UUID
        public var target: Target
        /// A file to read on open. Only the screenshot trigger sets this.
        public var initialFile: URL?

        public init(target: Target, initialFile: URL? = nil) {
            self.id = UUID()
            self.target = target
            self.initialFile = initialFile
        }
    }

    @Published public var catalogImportRequest: CatalogImportRequest?
    @Published public var expandedModelIDs: Set<UUID> = []
    /// Model currently open in the parameter sheet.
    @Published public var editingModelID: UUID?
    /// Blocks a second submission while one is running.
    private var submitGate = SubmitGate()

    /// Ids taken by providers other than the one being edited.
    public func otherProviderIDs(excluding id: String) -> Set<String> {
        Set(configuration.providers.map(\.id).filter { $0 != id })
    }

    /// Loads a provider into the editor. Safe to call repeatedly.
    public func beginEditing(providerID: String) {
        guard let provider = provider(id: providerID) else {
            draft = nil
            return
        }
        if draft?.original.id == providerID, draft?.isDirty == true { return }
        draft = ProviderDraft(
            provider: provider,
            existingIDs: otherProviderIDs(excluding: providerID)
        )
        editorPhase = .editing
        // The action bar's message was about some other provider; do not carry it over.
        status = .idle
    }

    /// Saves the draft into this app's own settings file.
    ///
    /// Invalid drafts are refused before anything touches the disk. By the user's ruling of
    /// 2026-10-08 this writes `codexbridger/config.json` and nothing else: no backup, and no
    /// file ChatGPT reads. Applying a provider to ChatGPT — including the model parameter file —
    /// is 启用's job, and that is the action that backs the previous files up.
    @discardableResult
    public func saveDraft() -> Bool {
        guard var current = draft else { return false }
        guard submitGate.begin() else { return false }
        defer { submitGate.end() }

        let committed: ProviderConfiguration
        do {
            committed = try current.commit()
        } catch let failure as ValidationFailure {
            editorPhase = .failed("还有 " + String(failure.issues.count) + " 处需要修正："
                                  + failure.message)
            return false
        } catch {
            editorPhase = .failed(error.localizedDescription)
            return false
        }

        let originalID = current.original.id
        if let index = configuration.providers.firstIndex(where: { $0.id == originalID }) {
            configuration.providers[index] = committed
        } else {
            configuration.providers.append(committed)
        }
        // A renamed provider must keep its active/selection pointers valid.
        if configuration.activeProviderID == originalID, originalID != committed.id {
            configuration.activeProviderID = committed.id
        }
        if selectedProviderID == originalID {
            selectedProviderID = committed.id
        }

        do {
            try store.save(configuration)
        } catch {
            editorPhase = .failed("保存失败：" + error.localizedDescription)
            return false
        }

        current = ProviderDraft(
            provider: committed,
            existingIDs: otherProviderIDs(excluding: committed.id)
        )
        draft = current
        publishTransient(.saved("已保存 " + committed.name))
        refreshCodexState()
        resolveTemplateSource()
        return true
    }

    /// Throws away unsaved edits.
    ///
    /// A provider that was never saved has nothing to restore, so discarding removes it from
    /// the list instead. That is a different action from reverting an edit to a saved provider.
    public func resetDraft() {
        guard let current = draft else { return }
        if current.isNew {
            configuration.providers.removeAll { $0.id == current.provider.id }
            if selectedProviderID == current.provider.id {
                selectedProviderID = configuration.providers.first?.id
            }
            if let id = selectedProviderID, configuration.provider(id: id) != nil {
                beginEditing(providerID: id)
            } else {
                draft = nil
            }
            editorPhase = .idle
            return
        }
        draft?.reset()
        editorPhase = .editing
    }

    public func addModelToDraft() {
        guard var current = draft else { return }
        let existing = Set(current.provider.models.map { $0.slug })
        var index = current.provider.models.count + 1
        var slug = "model-" + String(index)
        while existing.contains(slug) {
            index += 1
            slug = "model-" + String(index)
        }
        // Give it values that pass validation. A placeholder with no context window could
        // never be saved, which left the Save button permanently disabled.
        let window = ProviderDraft.minimumContextWindow
        current.provider.models.append(
            ModelConfiguration(
                slug: slug,
                displayName: slug,
                contextWindow: window,
                maxContextWindow: window,
                supportedReasoningEfforts: [.medium],
                defaultReasoningEffort: .medium,
                priority: current.provider.models.count + 1
            )
        )
        draft = current
        editorPhase = .editing
    }

    public func removeModelFromDraft(_ modelID: UUID) {
        guard var current = draft else { return }
        current.provider.models.removeAll { $0.id == modelID }
        expandedModelIDs.remove(modelID)
        renumberPriorities(&current)
        draft = current
        editorPhase = .editing
    }

    public func moveModelInDraft(_ modelID: UUID, by offset: Int) {
        guard var current = draft else { return }
        guard let index = current.provider.models.firstIndex(where: { $0.id == modelID }) else {
            return
        }
        let target = index + offset
        guard target >= 0, target < current.provider.models.count else { return }
        current.provider.models.swapAt(index, target)
        renumberPriorities(&current)
        draft = current
        editorPhase = .editing
    }

    private func renumberPriorities(_ current: inout ProviderDraft) {
        for index in current.provider.models.indices {
            current.provider.models[index].priority = index + 1
        }
    }

    /// Creates a provider from a preset and opens it in the editor.
    public func createProvider(from preset: ProviderPreset) {
        let id = uniqueProviderID(base: preset.id)
        let provider = preset.makeProvider(id: id)
        configuration.providers.append(provider)
        selectedProviderID = id
        draft = ProviderDraft(provider: provider, existingIDs: otherProviderIDs(excluding: id), isNew: true)
        editorPhase = .editing
        isShowingPresetPicker = false
    }

    // MARK: - Importing models from a catalog file

    /// Opens the import sheet. The picker is closed if it was the entry point.
    public func beginCatalogImport(
        _ target: CatalogImportRequest.Target,
        initialFile: URL? = nil
    ) {
        isShowingPresetPicker = false
        catalogImportRequest = CatalogImportRequest(target: target, initialFile: initialFile)
    }

    /// Applies a confirmed import.
    ///
    /// Only the draft is touched: nothing reaches the disk until the user saves, which is the same
    /// contract every other edit in the form follows.
    @discardableResult
    public func applyCatalogImport(
        _ outcome: ModelCatalogImporter.ImportOutcome,
        slugs: Set<String>
    ) -> ModelCatalogImporter.MergeResult? {
        let selected = outcome.models.map(\.model).filter { slugs.contains($0.slug) }
        guard !selected.isEmpty else { return nil }
        guard let target = catalogImportRequest?.target else { return nil }
        catalogImportRequest = nil

        let merge: ModelCatalogImporter.MergeResult
        switch target {
        case .draftProvider:
            guard var current = draft else { return nil }
            merge = ModelCatalogImporter.merge(imported: selected, into: current.provider.models)
            current.provider.models = merge.models
            draft = current
        case .newProvider:
            let id = uniqueProviderID(base: "provider")
            var provider = ProviderConfiguration(
                id: id,
                name: "新提供商",
                baseURL: "",
                credentialMode: .bearerToken
            )
            merge = ModelCatalogImporter.merge(imported: selected, into: [])
            provider.models = merge.models
            configuration.providers.append(provider)
            selectedProviderID = id
            draft = ProviderDraft(
                provider: provider,
                existingIDs: otherProviderIDs(excluding: id),
                isNew: true
            )
        }

        editorPhase = .editing
        publishTransient(.saved(importSummary(merge)))
        return merge
    }

    /// A one-line account of what the import did, including what it replaced.
    private func importSummary(_ merge: ModelCatalogImporter.MergeResult) -> String {
        var parts = ["已导入 " + String(merge.added.count) + " 个模型"]
        if !merge.overwritten.isEmpty {
            parts.append("覆盖 " + String(merge.overwritten.count) + " 个同名模型："
                         + merge.overwritten.joined(separator: "、"))
        }
        if merge.added.isEmpty && merge.overwritten.isEmpty {
            return "没有新增模型"
        }
        return parts.joined(separator: "，")
    }

    /// Creates an empty provider for a service that has no preset.
    public func createBlankProvider() {
        let id = uniqueProviderID(base: "provider")
        let provider = ProviderConfiguration(
            id: id,
            name: "新提供商",
            baseURL: "",
            credentialMode: .bearerToken
        )
        configuration.providers.append(provider)
        selectedProviderID = id
        draft = ProviderDraft(provider: provider, existingIDs: otherProviderIDs(excluding: id), isNew: true)
        editorPhase = .editing
        isShowingPresetPicker = false
    }

    /// True when the draft has unsaved edits, so activating must not silently use them.
    public var hasUnsavedEdits: Bool { draft?.isDirty ?? false }

    @discardableResult
    public func addProvider() -> String {
        let id = uniqueProviderID(base: "provider")
        let provider = ProviderConfiguration(
            id: id,
            name: "新提供商",
            baseURL: "http://127.0.0.1:8000/v1",
            credentialMode: .bearerToken,
            bearerToken: "",
            models: [
                ModelConfiguration(slug: "model-1", displayName: "Model 1")
            ]
        )
        configuration.providers.append(provider)
        selectedProviderID = id
        persist()
        return id
    }

    public func duplicateProvider(_ id: String) {
        guard var copy = provider(id: id) else { return }
        let newID = uniqueProviderID(base: id)
        copy.id = newID
        copy.name = copy.name + " 副本"
        copy.models = copy.models.map { model in
            var newModel = model
            newModel.id = UUID()
            return newModel
        }
        configuration.providers.append(copy)
        selectedProviderID = newID
        persist()
    }

    /// Deletes a provider and everything hanging off it, without asking.
    ///
    /// `private` on purpose: a view cannot reach it, so no button can delete a provider by
    /// accident. Reported twice from the running app that a delete happened with no prompt —
    /// the first time the sidebar button and the row's context menu both called this directly,
    /// the second time a build was in circulation with only one of them rewired. Views ask
    /// through `requestDeleteProvider`, and `confirmPendingDeletion` is the only caller here;
    /// rewiring a view back to a raw delete now fails to compile.
    private func applyDeletion(of id: String) {
        configuration.providers.removeAll { $0.id == id }
        if configuration.activeProviderID == id {
            configuration.activeProviderID = nil
            configuration.activeModelSlug = nil
        }
        if selectedProviderID == id {
            selectedProviderID = configuration.providers.first?.id
        }
        // The editor must not keep a provider that no longer exists. The window also reloads
        // the draft when the selection changes, but the model should not depend on a view
        // being there to stay consistent: deleting the provider being edited would otherwise
        // leave its form on screen after it was deleted.
        if draft?.original.id == id || draft?.provider.id == id {
            if let next = selectedProviderID, configuration.provider(id: next) != nil {
                beginEditing(providerID: next)
            } else {
                draft = nil
            }
        }
        persist()
    }

    // MARK: - Deletion confirmation

    /// A delete that is waiting for the user to agree to it.
    ///
    /// Deleting a provider used to happen on the click: the sidebar's 删除 button and the row's
    /// context menu both went straight to `deleteProvider`, so one slip of the mouse lost the
    /// provider and its models with nothing to undo it. The prompt is carried here rather than
    /// drawn from the sidebar because the model menu in the detail pane needs the same one, and
    /// `ContentView` draws a single alert from this value.
    public struct PendingDeletion: Identifiable, Equatable {
        /// What is about to go away. The view reads only the copy; the action is applied here.
        public enum Target: Equatable {
            /// A provider in this app's list. Written as soon as it is confirmed.
            case provider(id: String)
            /// A model on the provider being edited. An unsaved change, so reverting the draft
            /// brings it back.
            case model(id: UUID)
        }

        public let id = UUID()
        public let target: Target
        /// The prompt, already in the interface language, so the view has nothing to look up.
        public let title: String
        public let message: String
        public let confirmTitle: String
    }

    /// Asks before deleting a provider. Every entry point comes through here.
    public func requestDeleteProvider(_ id: String) {
        guard let provider = provider(id: id) else { return }
        let name = provider.name.isEmpty ? id : provider.name
        var message = t("「{name}」下有 {count}。删除只改 CodexBridger 自己的设置，config.toml 和 auth.json 不会被动。")
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{count}", with: modelCountPhrase(provider.models.count))
        // Deleting the provider ChatGPT was switched to is worth spelling out: the app forgets
        // what it activated, but the files keep naming that provider until something else is
        // activated, so the mark and the disk disagree in between.
        if configuration.activeProviderID == id {
            message += " " + t("ChatGPT 正指着它：删掉以后「使用中」的标记也没了，配置文件要等你激活别的提供商时才会改写。")
        }
        pendingDeletion = PendingDeletion(
            target: .provider(id: id),
            title: t("删除这个提供商？"),
            message: message,
            confirmTitle: t("删除")
        )
    }

    /// Asks before removing a model from the provider being edited.
    public func requestRemoveModelFromDraft(_ modelID: UUID) {
        guard let entry = draft?.provider.models.first(where: { $0.id == modelID }) else { return }
        let name = entry.displayName.isEmpty ? entry.slug : entry.displayName
        pendingDeletion = PendingDeletion(
            target: .model(id: modelID),
            title: t("移除这个模型？"),
            message: t("「{name}」会从这个提供商里移除。这是还没保存的改动，点「取消」可以让它回来，保存或更新配置之后才真正生效。")
                .replacingOccurrences(of: "{name}", with: name),
            confirmTitle: t("移除")
        )
    }

    /// Runs the delete the user just agreed to.
    public func confirmPendingDeletion() {
        guard let pending = pendingDeletion else { return }
        // Cleared first: the action below publishes, and the prompt must not be able to fire a
        // second time off one click.
        pendingDeletion = nil
        switch pending.target {
        case .provider(let id):
            applyDeletion(of: id)
        case .model(let id):
            removeModelFromDraft(id)
        }
    }

    /// Drops the pending delete. This is what the prompt's Cancel button does.
    public func cancelPendingDeletion() {
        pendingDeletion = nil
    }

    /// "3 个模型" or "1 个模型", counting models the way the sidebar counts providers.
    ///
    /// Chinese needs no plural and English does, so the one case gets its own line in the table.
    private func modelCountPhrase(_ count: Int) -> String {
        count == 1 ? t("1 个模型") : String(count) + t(" 个模型")
    }


    public func uniqueProviderID(base: String) -> String {
        let sanitized = base
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { $0.append($1) }
        let stem = sanitized.isEmpty ? "provider" : sanitized
        var candidate = stem
        var suffix = 2
        while configuration.providers.contains(where: { $0.id == candidate }) {
            candidate = stem + "-" + String(suffix)
            suffix += 1
        }
        return candidate
    }

    // MARK: - Model CRUD

    public func addModel(to providerID: String) {
        guard let index = configuration.providers.firstIndex(where: { $0.id == providerID }) else {
            return
        }
        let existing = Set(configuration.providers[index].models.map { $0.slug })
        var slug = "model-" + String(existing.count + 1)
        var suffix = 2
        while existing.contains(slug) {
            slug = "model-" + String(existing.count + suffix)
            suffix += 1
        }
        configuration.providers[index].models.append(
            ModelConfiguration(slug: slug, displayName: slug)
        )
        persist()
    }

    public func deleteModel(_ modelID: UUID, from providerID: String) {
        guard let index = configuration.providers.firstIndex(where: { $0.id == providerID }) else {
            return
        }
        configuration.providers[index].models.removeAll { $0.id == modelID }
        persist()
    }

    // MARK: - Activation

    /// An activation waiting for the user to confirm replacing the active provider.
    public struct PendingActivation: Identifiable, Equatable {
        public let id = UUID()
        public let providerID: String
        public let modelID: UUID
        public let assessment: ActivationGuard.Assessment
    }

    /// Entry point for every activate action.
    ///
    /// Re-reads what Codex has on disk first, because the user may have changed it
    /// outside the app. Activating is only destructive when it replaces a *different*
    /// provider, and then it asks.
    public func requestActivation(providerID: String, modelID: UUID) {
        guard let provider = provider(id: providerID) else { return }
        refreshCodexState()
        let assessment = ActivationGuard.assess(
            currentProviderID: snapshot.modelProviderID,
            targetProviderID: providerID,
            targetName: provider.name,
            targetBaseURL: provider.baseURL,
            // Whatever Codex is pointing at now is "ours" only if we manage that id; otherwise it
            // is a config written outside this app and gets backed up before we replace it.
            managedProviderIDs: Set(configuration.providers.map(\.id))
        )
        guard assessment.requiresConfirmation else {
            activate(providerID: providerID, modelID: modelID)
            return
        }
        pendingActivation = PendingActivation(
            providerID: providerID, modelID: modelID, assessment: assessment
        )
    }

    public func confirmPendingActivation() {
        guard let pending = pendingActivation else { return }
        pendingActivation = nil
        activate(providerID: pending.providerID, modelID: pending.modelID)
    }

    public func cancelPendingActivation() {
        pendingActivation = nil
    }

    public func activate(providerID: String, modelID: UUID) {
        guard let provider = provider(id: providerID) else { return }
        guard let model = provider.models.first(where: { $0.id == modelID })
            ?? provider.models.first else {
            status = .failure("该提供商还没有模型，请先添加模型")
            return
        }
        isActivating = true

        // Remember the selection before writing so a restart resumes here.
        configuration.activeProviderID = providerID
        configuration.activeModelSlug = model.slug
        persist()
        status = Status(kind: .idle, message: "正在生成 ChatGPT 配置…")

        let writer = CodexConfigWriter(
            paths: paths,
            templateSource: CatalogTemplateResolver(preferredSlug: configuration.catalogTemplateSlug)
        )
        let current = configuration
        let appModel = self
        Task.detached(priority: .userInitiated) {
            do {
                let result = try writer.activate(
                    provider: provider, model: model, configuration: current
                )
                await appModel.finishActivation(result, provider: provider, model: model)
            } catch {
                await appModel.failActivation(error)
            }
        }
    }

    public func finishActivation(
        _ result: ActivationResult,
        provider: ProviderConfiguration,
        model: ModelConfiguration
    ) {
        lastActivation = result
        templateSourceDescription = result.templateSourceDescription
        isActivating = false
        // Remember what the files were written from, so the button knows whether it still has
        // anything to apply. Stored, not just held: the state has to survive a restart.
        configuration.publishedProvider = provider
        persist()
        if !result.warnings.isEmpty {
            publishActivationStatus(.failure(result.warnings.joined(separator: " ")))
        } else {
            publishActivationStatus(.success("已激活 " + provider.name + " · " + model.slug))
        }
        refreshCodexState()
    }

    public func failActivation(_ error: Error) {
        isActivating = false
        publishActivationStatus(.failure("激活失败: " + error.localizedDescription))
    }

    /// Publishes the action bar's message for an activation.
    ///
    /// A success clears itself; anything that needs the user's attention stays until the next
    /// action replaces it. Reported 2026-10-08 — a successful activation left a red message on
    /// screen for good, because "no backup needed" was being reported as a warning.
    private func publishActivationStatus(_ next: Status) {
        status = next
        activationNoticeToken += 1
        let token = activationNoticeToken
        guard next.kind == .success else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.successNoticeSeconds * 1_000_000_000))
            guard let self, token == self.activationNoticeToken else { return }
            self.status = .idle
        }
    }
}