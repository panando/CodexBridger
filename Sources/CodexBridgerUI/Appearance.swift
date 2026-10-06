import AppKit
import SwiftUI

/// Lets QA and the screenshot harness force a light or dark appearance.
///
/// Usage: CODEXBRIDGER_APPEARANCE=dark open build/CodexBridger.app
/// Unset means "follow the system", which is the shipped default.
public enum AppearanceOverride {
    public static let environmentKey = "CODEXBRIDGER_APPEARANCE"

    /// Returns the appearance to apply, or nil to keep following the system.
    public static func requested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NSAppearance? {
        switch environment[environmentKey]?.lowercased() {
        case "dark": return NSAppearance(named: .darkAqua)
        case "light": return NSAppearance(named: .aqua)
        default: return nil
        }
    }

    public static func applyIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let appearance = requested(environment: environment) else { return }
        NSApplication.shared.appearance = appearance
    }

    /// SwiftUI equivalent, applied to the root view so the first paint already uses the
    /// requested appearance (a screenshot of a half-repainted window would be useless).
    public static func requestedColorScheme(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ColorScheme? {
        switch environment[environmentKey]?.lowercased() {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
}
