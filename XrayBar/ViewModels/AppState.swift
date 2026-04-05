import AppKit
import ServiceManagement
import Observation

@Observable
final class AppState {
    var isConnected = false
    var selectedProfile: Profile?
    var profiles: [Profile] = []
    var lastError: String?

    private let processManager = XrayProcessManager()
    private let proxyManager = ProxyManager()
    private let profileManager = ProfileManager()

    private let defaults = UserDefaults.standard

    init() {
        loadProfiles()
        // Sync state with reality on launch
        isConnected = proxyManager.checkProxyEnabled()
    }

    func loadProfiles() {
        profiles = profileManager.scan()
        let savedName = defaults.string(forKey: "selectedProfile")
        selectedProfile = profiles.first(where: { $0.id == savedName }) ?? profiles.first
    }

    func selectProfile(_ profile: Profile) {
        selectedProfile = profile
        defaults.set(profile.id, forKey: "selectedProfile")
        if isConnected {
            // Restart with new profile
            disconnect()
            connect()
        }
    }

    /// Connect: start xray + enable system proxy (transactional)
    func connect() {
        guard let profile = selectedProfile else {
            lastError = "No profile selected"
            return
        }
        lastError = nil
        do {
            try processManager.start(configURL: profile.url) { [weak self] in
                // xray crashed unexpectedly — tear down proxy too
                self?.forceDisconnect()
            }
            try proxyManager.enableProxy()
            isConnected = true
        } catch {
            // Rollback: if either fails, clean up both
            lastError = error.localizedDescription
            processManager.stop()
            try? proxyManager.disableProxy()
            isConnected = false
        }
    }

    /// Disconnect: stop xray + disable system proxy (transactional)
    func disconnect() {
        processManager.stop()
        try? proxyManager.disableProxy()
        isConnected = false
    }

    func toggleConnection() {
        if isConnected {
            disconnect()
        } else {
            connect()
        }
    }

    func openConfigInEditor() {
        guard let profile = selectedProfile else { return }
        NSWorkspace.shared.open(profile.url)
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // ignore
        }
    }

    func cleanup() {
        disconnect()
    }

    private func forceDisconnect() {
        try? proxyManager.disableProxy()
        isConnected = false
    }
}
