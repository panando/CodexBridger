import SwiftUI
import CodexBridgerCore

// MARK: - Surfaces and feedback

/// Titled rounded container.
public struct Card<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: Content

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Color.token(Palette.textPrimary))
                if let subtitle {
                    HelpText(subtitle, lineLimit: 2)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                content
            }
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.token(Palette.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.token(Palette.border), lineWidth: Metrics.borderWidth)
        )
    }
}

/// Small status pill.
public struct Pill: View {
    private let text: String
    private let tone: Tone

    public enum Tone { case accent, success, danger, neutral }

    public init(_ text: String, tone: Tone = .accent) {
        self.text = text
        self.tone = tone
    }

    private var color: NSColor {
        switch tone {
        case .accent: return Palette.accentText
        case .success: return Palette.success
        case .danger: return Palette.danger
        case .neutral: return Palette.textSecondary
        }
    }

    public var body: some View {
        Text(text)
            .font(Typography.pill)
            .foregroundStyle(Color.token(color))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .frame(minHeight: Metrics.minDenseHitTarget)
            .background(Capsule().fill(Color.token(color).opacity(0.14)))
    }
}

/// Banner reporting the outcome of the last action. The icon is baseline aligned with
/// the first line of the message so multi-line messages stay level.
public struct StatusBanner: View {
    public enum Kind: Equatable { case info, success, warning, failure }

    private let kind: Kind
    private let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    private var color: NSColor {
        switch kind {
        case .info: return Palette.textSecondary
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .failure: return Palette.danger
        }
    }

    private var symbol: String {
        switch kind {
        case .info: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(Typography.help)
                .foregroundStyle(Color.token(color))
            Text(message)
                .font(Typography.help)
                .foregroundStyle(Color.token(Palette.textPrimary))
                .lineSpacing(Typography.helpLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Color.token(color).opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

/// Empty state used when no provider is selected.
public struct EmptyStateView: View {
    private let title: String
    private let message: String
    private let actionTitle: String
    private let action: () -> Void

    public init(title: String, message: String, actionTitle: String, action: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "shippingbox")
                .iconFont(.hero)
                .foregroundStyle(Color.token(Palette.textSecondary))
            Text(title)
                .font(Typography.titleFont)
                .foregroundStyle(Color.token(Palette.textPrimary))
            Text(message)
                .font(Typography.help)
                .foregroundStyle(Color.token(Palette.textHelp))
                .multilineTextAlignment(.center)
                .lineSpacing(Typography.helpLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .hitTarget()
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Edits a string map as one "key = value" line per line.
///
/// Uses a vertical TextField rather than a TextEditor so the placeholder is the
/// platform placeholder: the previous overlay needed hand-tuned offsets to line up and
/// still drifted from the text baseline.
public struct KeyValueLinesEditor: View {
    @Binding private var dictionary: [String: String]
    private let placeholder: String
    private let accessibilityLabel: String
    @State private var buffer: String = ""
    @State private var isLoaded = false

    public init(
        dictionary: Binding<[String: String]>,
        placeholder: String,
        accessibilityLabel: String
    ) {
        self._dictionary = dictionary
        self.placeholder = placeholder
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        ValueTextField(
            text: Binding(
                get: { buffer },
                set: { newValue in
                    buffer = newValue
                    let parsed = KeyValueLinesEditor.parse(newValue)
                    if parsed != dictionary { dictionary = parsed }
                }
            ),
            prompt: placeholder,
            monospaced: true,
            accessibilityLabel: accessibilityLabel,
            lineRange: 3...8
        )
        .onAppear {
            guard !isLoaded else { return }
            isLoaded = true
            buffer = KeyValueLinesEditor.render(dictionary)
        }
        .onChange(of: dictionary) { _, newValue in
            let rendered = KeyValueLinesEditor.render(newValue)
            if rendered != buffer { buffer = rendered }
        }
    }

    public static func render(_ dictionary: [String: String]) -> String {
        dictionary.keys.sorted()
            .map { $0 + " = " + (dictionary[$0] ?? "") }
            .joined(separator: TOMLDocument.newline)
    }

    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(separator: Character(TOMLDocument.newline)) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }
}
