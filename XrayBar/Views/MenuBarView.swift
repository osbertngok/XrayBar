import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        Button(appState.isConnected ? "⬤ Connected" : "◯ Disconnected") {
            appState.toggleConnection()
        }
        .keyboardShortcut("x")

        if let error = appState.lastError {
            Text("⚠ \(error)")
        }

        Divider()

        // Profile picker
        if let selected = appState.selectedProfile {
            Text("Profile: \(selected.name)")
        }

        ForEach(appState.profiles) { profile in
            Button {
                appState.selectProfile(profile)
            } label: {
                if profile.id == appState.selectedProfile?.id {
                    Text("✓ \(profile.name)")
                } else {
                    Text("   \(profile.name)")
                }
            }
        }

        Divider()

        Button("Edit Config…") {
            appState.openConfigInEditor()
        }
        .disabled(appState.selectedProfile == nil)
        .keyboardShortcut("e")

        Button("Reload Profiles") {
            appState.loadProfiles()
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { appState.launchAtLogin },
            set: { _ in appState.toggleLaunchAtLogin() }
        ))

        Button("Quit XrayBar") {
            appState.cleanup()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
