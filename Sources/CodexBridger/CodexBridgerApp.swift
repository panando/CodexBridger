import SwiftUI
import CodexBridgerUI

@main
struct CodexBridgerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("CodexBridger") {
            ContentView(model: model)
                .preferredColorScheme(AppearanceOverride.requestedColorScheme())
        }
        .defaultSize(width: 1_080, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("添加提供商") { model.addProvider() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("刷新 ChatGPT 状态") { model.refreshCodexState() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(model: model)
                .preferredColorScheme(AppearanceOverride.requestedColorScheme())
        }
    }
}
