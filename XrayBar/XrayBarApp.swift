import SwiftUI

@main
struct XrayBarApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.isConnected ? "paperplane.fill" : "paperplane")
        }
    }
}
