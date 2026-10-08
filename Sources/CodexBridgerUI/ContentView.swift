import SwiftUI
import CodexBridgerCore

/// Two-pane window: providers on the left, the selected provider on the right.
public struct ContentView: View {
    @ObservedObject private var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.openSettings) private var openSettings

    public init(model: AppModel) {
        self.model = model
    }

    /// Sidebar visibility, deliberately unanimated.
    ///
    /// Measured with a 60fps screen recording: showing the sidebar again ran the expansion to
    /// about 83% and then jumped the remaining 17% in a single frame, because the detail pane
    /// re-laid out on the final frame. (Hiding was smooth, which is why the problem only showed up
    /// on the way back.) Rather than chase the re-layout, the visibility change is committed in a
    /// transaction with animations disabled, so the sidebar simply appears.
    ///
    /// The suppression is scoped to this one state change. Hover fades, the popover and the sheet
    /// are untouched, which a blanket `.transaction { $0.disablesAnimations = true }` on the
    /// split view would have killed.
    /// Whether the sidebar is taking up width beside the detail column.
    private var sidebarIsVisible: Bool {
        columnVisibility != .detailOnly
    }

    private var columnVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { columnVisibility },
            set: { newValue in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { columnVisibility = newValue }
            }
        )
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: columnVisibilityBinding) {
            SidebarView(model: model)
                // A single fixed width, deliberately not a min/ideal/max range. With a range,
                // AppKit re-resolves the width when the column is shown again, so the sidebar
                // expands to a different width than the one it collapsed from and the animation
                // visibly jumps part-way through.
                .navigationSplitViewColumnWidth(Metrics.sidebarWidth)
        } detail: {
            detail
        }
        .frame(minWidth: 1_040, minHeight: 660)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(Color.token(Palette.windowBackground), for: .windowToolbar)
        // The title is a principal toolbar item, not `.navigationTitle`.
        //
        // Measured from a screenshot: `.navigationTitle` on a NavigationSplitView draws at the
        // leading edge of the content area — the title sat about 215pt left of the window centre,
        // just clear of the sidebar. A `.principal` item is the placement that actually centres
        // in the toolbar, which spans the whole window.
        // Empty so the window stops drawing its own bold title; the principal item below is the
        // only title on screen. Without this the title bar showed two of them.
        .navigationTitle("")
        .toolbar {
            // One principal item spanning the title bar: the title centred inside it and the
            // Settings button pushed to its trailing edge.
            //
            // Two separate items cannot both be satisfied here. Measured from screenshots: with
            // `.navigationTitle` the gear sits 28pt from the corner but the title lands 214pt left
            // of centre; adding a `.principal` title centres it but drags the neighbouring action
            // item into the same centred group, leaving the gear about 340pt short of the corner.
            // A single item that spans the bar gets both.
            ToolbarItem(placement: .principal) {
                Text("CodexBridger")
                    .font(Typography.control)
                    .foregroundStyle(Color.token(Palette.textPrimary))
                    .offset(x: sidebarIsVisible ? -Metrics.sidebarWidth / 2 : 0)
            }
        }
        .background(
            // Invisible anchor that installs the trailing title-bar accessory.
            TitlebarAccessory(content: titlebarSettingsButton)
                .frame(width: 0, height: 0)
        )
        // The initial draft is established by AppModel.load(), before the first render, so that
        // the first frame matches every frame after it. Only later switches need handling here.
        .task {
            // Opens the import sheet on launch when asked for from the environment.
            //
            // Same reason as the Settings trigger below: Accessibility permission is not granted,
            // so a script cannot click "从文件导入" and the sheet would be uninspectable. The value
            // is the file to preload, or 1 to open the sheet empty. It does nothing on a normal
            // launch.
            let requested = ProcessInfo.processInfo.environment["CODEXBRIDGER_OPEN_CATALOG_IMPORT"]
            if let requested, !requested.isEmpty {
                let file = requested == "1" ? nil : URL(fileURLWithPath: requested)
                // Presented a beat after launch: a sheet asked for while the window is still being
                // installed is dropped silently, so the trigger waits for the window to settle.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    model.beginCatalogImport(
                        model.draft == nil ? .newProvider : .draftProvider,
                        initialFile: file
                    )
                }
            }
            // Opens the global settings screen on launch. Same reason as the trigger below:
            // a script cannot click, so this is how the screen gets inspected.
            if ProcessInfo.processInfo.environment["CODEXBRIDGER_OPEN_GLOBAL_SETTINGS"] == "1" {
                model.selectedSection = .globalSettings
                model.loadGlobalSettings()
            }
            // Opens the Settings window on launch when asked for from the environment, the same
            // way CODEXBRIDGER_APPEARANCE forces an appearance. There is no way to click the gear
            // from a script — Accessibility permission is not granted — so this is how the window
            // gets inspected. It does nothing in a normal launch.
            guard ProcessInfo.processInfo.environment["CODEXBRIDGER_OPEN_SETTINGS"] == "1" else {
                return
            }
            openSettings()
        }
        .onChange(of: model.selectedProviderID) { _, newValue in
            guard let newValue else { model.draft = nil; return }
            model.beginEditing(providerID: newValue)
        }
        // Importing models from an existing catalog file. One sheet serves both entry points:
        // adding to the provider being edited, and starting a new provider from a file.
        .sheet(item: $model.catalogImportRequest) { request in
            let target = request.target
            ModelCatalogImportSheet(
                title: target == .newProvider
                    ? "从模型参数文件新建提供商"
                    : "从模型参数文件导入模型",
                catalogsDirectory: model.paths.modelCatalogsDirectory,
                existingSlugs: existingSlugs(for: target),
                initialFile: request.initialFile,
                onConfirm: { confirmation in
                    model.applyCatalogImport(confirmation.outcome, slugs: confirmation.slugs)
                },
                onCancel: { model.catalogImportRequest = nil }
            )
        }
        .sheet(isPresented: $model.isShowingPresetPicker) {
            PresetPickerSheet(
                onPick: { preset in model.createProvider(from: preset) },
                onPickBlank: { model.createBlankProvider() },
                onPickCatalogFile: { model.beginCatalogImport(.newProvider) },
                onCancel: { model.isShowingPresetPicker = false }
            )
        }

        // Confirmation when activating would replace a provider this app did not write.
        //
        // This was the whole reason activation appeared to do nothing: `requestActivation` set
        // `pendingActivation` and stopped, but nothing in the UI ever read it, so the prompt
        // never appeared and the write never happened. Switching between two providers this app
        // manages does not prompt; a foreign config does.
        .alert(
            model.pendingActivation?.assessment.title ?? "",
            isPresented: pendingActivationBinding
        ) {
            Button(model.pendingActivation?.assessment.confirmTitle ?? "切换并写入",
                   role: .destructive) { model.confirmPendingActivation() }
            Button("取消", role: .cancel) { model.cancelPendingActivation() }
        } message: {
            Text(model.pendingActivation?.assessment.message ?? "")
        }
    }

    /// The Settings control, hosted in the title bar by `TitlebarAccessory`.
    private var titlebarSettingsButton: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(Typography.control)
                .foregroundStyle(Color.token(Palette.textSecondary))
        }
        .buttonStyle(.plain)
        .help(model.t("设置"))
        .accessibilityLabel(model.t("设置"))
        .frame(width: 28, height: 24)
    }

    /// Which slugs the target already has, so the sheet can mark them as "will be overwritten".
    private func existingSlugs(for target: AppModel.CatalogImportRequest.Target) -> Set<String> {
        switch target {
        case .draftProvider:
            return Set(model.draft?.provider.models.map(\.slug) ?? [])
        case .newProvider:
            return []
        }
    }

    private var pendingActivationBinding: Binding<Bool> {
        Binding(
            get: { model.pendingActivation != nil },
            set: { if !$0 { model.cancelPendingActivation() } }
        )
    }

    @ViewBuilder
    private var detail: some View {
        if model.selectedSection == .globalSettings {
            GlobalSettingsView(model: model)
        } else {
            providerDetail
        }
    }

    @ViewBuilder
    private var providerDetail: some View {
        VStack(spacing: 0) {
            // A config file that failed to load must never look like an empty install.
            if let error = model.loadErrorMessage {
                StatusBanner(
                    kind: .failure,
                    message: "读取已保存的配置失败，本次以空白配置启动，原文件没有被改动。"
                        + " 详情：" + error
                )
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)
            }

            if let draftBinding = draftBinding {
                ProviderConfigView(model: model, draft: draftBinding)
            } else {
                OnboardingView(model: model, onCreate: { model.isShowingPresetPicker = true })
            }
        }
    }

    private var draftBinding: Binding<ProviderDraft>? {
        guard model.draft != nil else { return nil }
        return Binding(
            get: {
                model.draft ?? ProviderDraft(provider: ProviderConfiguration(id: "", name: "", baseURL: ""))
            },
            set: { model.draft = $0 }
        )
    }
}

// MARK: - Sidebar

/// Provider list, grouped by family, with the add/remove footer.
struct SidebarView: View {
    @ObservedObject var model: AppModel

    /// The count beside the Add/Delete buttons.
    ///
    /// Chinese says "0 个" and needs no plural; English says "1 provider" and "3 providers",
    /// which one template cannot do. The count picks the phrase: `1 个` has its own entry and
    /// every other count shares ` 个`. The Chinese interface reads exactly as it did before —
    /// the translation was simply missing, so an English interface showed a bare Chinese
    /// measure word.
    private var providerCount: String {
        let count = model.configuration.providers.count
        return count == 1 ? model.t("1 个") : String(count) + model.t(" 个")
    }

    /// Providers grouped by their stored category, in first-appearance order.
    private var groups: [(category: String, providers: [ProviderConfiguration])] {
        var order: [String] = []
        var buckets: [String: [ProviderConfiguration]] = [:]
        for provider in model.configuration.providers {
            let category = provider.category.isEmpty ? ProviderPreset.customCategory : provider.category
            if buckets[category] == nil {
                order.append(category)
                buckets[category] = []
            }
            buckets[category]?.append(provider)
        }
        return order.compactMap { category in
            guard let providers = buckets[category] else { return nil }
            return (category, providers)
        }
    }

    /// A section heading inside the sidebar, styled like the provider family captions so the
    /// two levels of heading read as the same kind of thing.
    private func sectionCaption(_ title: String, topPadding: CGFloat) -> some View {
        Text(title)
            .font(Typography.sectionCaption)
            .foregroundStyle(Color.token(Palette.textHelp))
            .padding(.horizontal, Spacing.md)
            .padding(.top, topPadding)
            .padding(.bottom, Spacing.xxs)
    }

    /// The entry above the provider list. Selecting it swaps the detail pane.
    private var globalSettingsRow: some View {
        let isSelected = model.selectedSection == .globalSettings
        return Button {
            model.selectedSection = .globalSettings
            model.loadGlobalSettings()
        } label: {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(isSelected
                          ? Color.token(Palette.selectionGlyphFill)
                          : Color.token(Palette.accentText).opacity(0.14))
                    .frame(width: Metrics.sidebarGlyph, height: Metrics.sidebarGlyph)
                    .overlay(
                        Image(systemName: "slider.horizontal.3")
                            .iconFont(.s, weight: .semibold)
                            .foregroundStyle(isSelected
                                             ? Color.token(Palette.textOnAccent)
                                             : Color.token(Palette.accentText))
                    )
                    .accessibilityHidden(true)
                Text(model.t("全局配置"))
                    .font(Typography.control)
                    // Same rule as the provider rows: on the selection fill the label has to
                    // take the on-accent colour. This used to be textPrimary in both branches,
                    // which drew a black label on the blue fill.
                    .foregroundStyle(isSelected
                                     ? Color.token(Palette.textOnAccent)
                                     : Color.token(Palette.textPrimary))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: Metrics.minHitTarget, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isSelected ? Color.token(Palette.selectionFill) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.sm)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Separates the title bar from the body, matching the rule in the detail pane so the
            // line reads as one edge across the window.
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    sectionCaption(model.t("模型提供商"), topPadding: Spacing.md)
                    if groups.isEmpty {
                        Text(model.t("还没有提供商"))
                            .font(Typography.help)
                            .foregroundStyle(Color.token(Palette.textHelp))
                            .padding(Spacing.lg)
                    }
                    ForEach(groups, id: \.category) { group in
                        // The stored category is the source string; look it up so the built-in
                        // group names read in the interface language.
                        Text(model.t(group.category))
                            .font(Typography.sectionCaption)
                            .foregroundStyle(Color.token(Palette.textHelp))
                            .padding(.horizontal, Spacing.md)
                            .padding(.top, Spacing.md)
                            .padding(.bottom, Spacing.xxs)
                        ForEach(group.providers) { provider in
                            ProviderRow(
                                provider: provider,
                                isActive: model.configuration.activeProviderID == provider.id,
                                // Selection is about which screen is open, so a provider row is
                                // only selected while the provider screen is showing.
                                isSelected: model.selectedSection == .providers
                                    && model.selectedProviderID == provider.id,
                                inUseLabel: model.t("使用中"),
                                missingAddressLabel: model.t("还没填地址")
                            )
                            .onTapGesture {
                                model.selectedSection = .providers
                                model.selectedProviderID = provider.id
                            }
                            .contextMenu {
                                Button("复制提供商") { model.duplicateProvider(provider.id) }
                                Button("删除提供商", role: .destructive) {
                                    model.deleteProvider(provider.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.md)
            }

            // The app-wide settings sit at the bottom, next to the action bar, so the whole upper
            // area belongs to the provider list. At the top the row read as one more heading in
            // the provider section.
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                sectionCaption(model.t("其他配置"), topPadding: Spacing.sm)
                globalSettingsRow
            }
            .padding(.bottom, Spacing.sm)

            Divider()

            // These two act on the provider list, so while the settings screen is showing they
            // are not just useless but misleading: they look like they belong to whatever is on
            // screen. Disabled, with the reason on hover.
            HStack(spacing: Spacing.sm) {
                Button(model.t("添加")) { model.isShowingPresetPicker = true }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.selectedSection == .globalSettings)
                    .help(model.selectedSection == .globalSettings
                          ? "添加提供商；先点左侧「模型提供商」下的条目回到提供商界面"
                          : "新建一个提供商")
                Button(model.t("删除")) {
                    if let id = model.selectedProviderID { model.deleteProvider(id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(
                    model.selectedProviderID == nil
                        || model.selectedSection == .globalSettings
                )
                // Deleting only edits this app's own settings: no backup, and nothing ChatGPT
                // reads is touched. The tooltip used to promise a backup, which was not true.
                .help("从软件里删掉这个提供商（不会动 ChatGPT 正在用的配置文件）")
                Spacer(minLength: 0)
                Text(providerCount)
                    .font(Typography.help)
                    .foregroundStyle(Color.token(Palette.textHelp))
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Metrics.actionBarVerticalPadding)
            .frame(height: Metrics.actionBarHeight)
        }
        .background(Color.token(Palette.surface))
    }
}

/// One provider row: glyph, name, and the endpoint it points at.
struct ProviderRow: View {
    let provider: ProviderConfiguration
    let isActive: Bool
    let isSelected: Bool
    /// Localised here so the row does not need the model just to say two words.
    let inUseLabel: String
    let missingAddressLabel: String

    @State private var isHovered = false

    private var title: String { provider.name.isEmpty ? provider.id : provider.name }

    /// The reference shows the bare host; a full URL with a path is too long for the row.
    private var subtitle: String {
        guard let url = URL(string: provider.baseURL), let host = url.host else {
            return provider.baseURL.isEmpty ? missingAddressLabel : provider.baseURL
        }
        return host
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(isSelected ? Color.token(Palette.selectionGlyphFill) : Color.token(Palette.accentText).opacity(0.14))
                .frame(width: Metrics.sidebarGlyph, height: Metrics.sidebarGlyph)
                .overlay(
                    Image(systemName: "square.stack.3d.up")
                        .iconFont(.s, weight: .semibold)
                        .foregroundStyle(isSelected ? Color.token(Palette.textOnAccent) : Color.token(Palette.accentText))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.control)
                    .foregroundStyle(isSelected ? Color.token(Palette.textOnAccent) : Color.token(Palette.textPrimary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(Typography.help)
                    .foregroundStyle(isSelected ? Color.token(Palette.textOnSelectionSecondary) : Color.token(Palette.textHelp))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Spacing.xs)
            if isActive {
                // A bare tick was too easy to miss next to the selection highlight, and the two
                // mean different things: selection is where you are editing, this is what Codex
                // is actually pointed at. A word is unambiguous where an icon is not.
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "checkmark")
                        .iconFont(.xs, weight: .bold)
                    Text(inUseLabel)
                        .font(Typography.help)
                        .fixedSize()
                }
                .foregroundStyle(isSelected ? Color.token(Palette.textOnAccent) : Color.token(Palette.success))
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(isSelected ? Color.token(Palette.textOnAccent).opacity(0.22)
                                          : Color.token(Palette.success).opacity(0.14))
                )
                .accessibilityLabel("ChatGPT 正在使用这个提供商")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: Metrics.minHitTarget, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(background)
                // Scoped to the fill on purpose. On the whole row this animation also covered the
                // layout that is recomputed on every frame while the sidebar column animates
                // open, so the two fought each other and the expansion came out uneven.
                .animation(.easeOut(duration: Motion.hover), value: isHovered)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(title + "  " + (provider.baseURL.isEmpty ? "" : provider.baseURL))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var background: Color {
        if isSelected { return Color.token(Palette.selectionFill) }
        if isHovered { return Color.token(Palette.hoverFill) }
        return .clear
    }
}
