import SwiftUI
import HidLensCore

@main
struct HidLensApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
