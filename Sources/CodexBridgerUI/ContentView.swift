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
        .sheet(isPresented: $model.isShowingPresetPicker) {
            PresetPickerSheet(
                onPick: { preset in model.createProvider(from: preset) },
                onPickBlank: { model.createBlankProvider() },
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

    private var pendingActivationBinding: Binding<Bool> {
        Binding(
            get: { model.pendingActivation != nil },
            set: { if !$0 { model.cancelPendingActivation() } }
        )
    }

    @ViewBuilder
    private var detail: some View {
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

    var body: some View {
        VStack(spacing: 0) {
            // Separates the title bar from the body, matching the rule in the detail pane so the
            // line reads as one edge across the window.
            Divider()
            Text(model.t("模型提供商"))
                .font(Typography.sectionTitle)
                .foregroundStyle(Color.token(Palette.textPrimary))
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
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
                                isSelected: model.selectedProviderID == provider.id,
                                inUseLabel: model.t("使用中"),
                                missingAddressLabel: model.t("还没填地址")
                            )
                            .onTapGesture { model.selectedProviderID = provider.id }
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

            Divider()

            HStack(spacing: Spacing.sm) {
                Button(model.t("添加")) { model.isShowingPresetPicker = true }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button(model.t("删除")) {
                    if let id = model.selectedProviderID { model.deleteProvider(id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.selectedProviderID == nil)
                .help("删除当前选中的提供商（会先备份再改文件）")
                Spacer(minLength: 0)
                Text(String(model.configuration.providers.count) + " 个")
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
