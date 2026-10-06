import SwiftUI
import CodexBridgerCore

/// The empty state shown when no provider is configured.
///
/// Follows the reference screen: app glyph, a "what can it do" headline, a single column of
/// icon + title + subtitle capability rows, and one primary call to action at the bottom.
/// Every capability listed is something this app actually does.
public struct OnboardingView: View {
    @ObservedObject private var model: AppModel
    private let onCreate: () -> Void

    public init(model: AppModel, onCreate: @escaping () -> Void) {
        self.model = model
        self.onCreate = onCreate
    }

    private func t(_ source: String) -> String { model.t(source) }

    private struct Capability: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let subtitle: String
    }

    /// Every capability listed here is one the app actually performs.
    ///
    /// The list previously claimed that local services (Ollama, llama.cpp, LM Studio) could be
    /// connected directly without a key. That is not true of this build — there are no presets
    /// for them and no handling specific to them, and the words appeared nowhere else in the
    /// sources. Describing a feature nobody implemented is worse than omitting it, because the
    /// user goes looking for it and concludes the app is broken.
    private let capabilities: [Capability] = [
        Capability(
            id: "write",
            symbol: "doc.badge.gearshape",
            title: "写入 ChatGPT 配置",
            subtitle: "生成 config.toml、auth.json 与模型目录文件，打开 ChatGPT 即可使用"
        ),
        Capability(
            id: "documented",
            symbol: "checkmark.seal",
            title: "仅写入官方支持的字段",
            subtitle: "每个参数都对照 ChatGPT 官方配置参考，不写入未经支持的字段"
        ),
        Capability(
            id: "presets",
            symbol: "square.grid.2x2",
            title: "内置常见服务商预设",
            subtitle: "DeepSeek、Moonshot、MiniMax、智谱 GLM、OpenRouter 可直接选择，也可自定义"
        ),
        Capability(
            id: "models",
            symbol: "slider.horizontal.3",
            title: "每个模型独立设置",
            subtitle: "上下文窗口、最大上下文、推理强度与显示状态，均可逐模型配置"
        ),
        Capability(
            id: "backup",
            symbol: "clock.arrow.circlepath",
            title: "修改前自动备份",
            subtitle: "改动 config.toml 或 auth.json 之前，先保存原文件副本"
        ),
    ]

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                appGlyph
                    .padding(.top, Spacing.xxl)
                    .padding(.bottom, Spacing.lg)

                Text(t("CodexBridger 能做什么？"))
                    .font(Typography.titleFont)
                    .foregroundStyle(Color.token(Palette.textPrimary))
                    .padding(.bottom, Spacing.xxl)

                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(capabilities) { capability in
                        HStack(alignment: .top, spacing: Spacing.lg) {
                            Image(systemName: capability.symbol)
                                .iconFont(.l)
                                .foregroundStyle(Color.token(Palette.accentText))
                                .frame(width: 30, alignment: .center)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(t(capability.title))
                                    .font(Typography.sectionTitle)
                                    .foregroundStyle(Color.token(Palette.textPrimary))
                                Text(t(capability.subtitle))
                                    .font(Typography.help)
                                    .foregroundStyle(Color.token(Palette.textHelp))
                                    .lineSpacing(Typography.helpLineSpacing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)

                Button(action: onCreate) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "plus.circle.fill")
                        Text(t("新建提供商")).font(Typography.control)
                    }
                    .frame(minWidth: 200)
                    .padding(.horizontal, Spacing.xl)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, Spacing.xxl)
                .padding(.bottom, Spacing.xxl)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.token(Palette.surface))
    }

    /// The application's own icon, the same image the About pane and the Finder show.
    ///
    /// This used to be a hand-drawn stand-in: a dark rounded square with a
    /// `chevron.left.forwardslash.chevron.right` glyph on it. It looked deliberate but it was a
    /// placeholder, and on the very first screen a user sees it advertised the wrong icon.
    /// The real icon is already in the bundle, so there is nothing to draw.
    private var appGlyph: some View {
        Group {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                // Outside a running app (a test rendering the view, say) there is no icon to
                // read. Showing nothing would silently look like a layout bug, so keep a mark.
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(Color.token(Palette.textHelp))
            }
        }
        .frame(width: Metrics.appGlyphSize, height: Metrics.appGlyphSize)
        .accessibilityHidden(true)
    }
}
