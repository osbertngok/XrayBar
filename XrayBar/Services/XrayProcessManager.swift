import Foundation

enum XrayLaunchError: LocalizedError {
    case launchFailed(String)
    case missingAssets(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let detail):
            return "xray failed to start:\n\(detail)"
        case .missingAssets(let detail):
            return detail
        }
    }
}

final class XrayProcessManager {
    private static let startupProbeInterval: TimeInterval = 0.3
    private static let assetFiles = ["geosite.dat", "geoip.dat"]
    private static let xrayBarAssets = ("~/.xray/assets/" as NSString).expandingTildeInPath
    private static let assetSearchPaths = [
        "/opt/homebrew/share/xray",
        "/usr/local/share/xray",
        "/usr/share/xray",
        xrayBarAssets,
    ]
    private static let assetDownloadBase = "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"

    private var process: Process?
    private var outputPipe: Pipe?
    private var expectingRestart = false

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    private(set) var lastOutput: String = ""

    private static func resolveXray() -> (executable: String, args: [String]) {
        let homebrewARM = "/opt/homebrew/bin/xray"
        let homebrewIntel = "/usr/local/bin/xray"
        if FileManager.default.isExecutableFile(atPath: homebrewARM) {
            return (homebrewARM, [])
        }
        if FileManager.default.isExecutableFile(atPath: homebrewIntel) {
            return (homebrewIntel, [])
        }
        return ("/usr/bin/env", ["xray"])
    }

    private static func resolveAssetPath() -> String? {
        for dir in assetSearchPaths {
            let allExist = assetFiles.allSatisfy { name in
                let path = (dir as NSString).appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: path)
            }
            if allExist {
                return dir
            }
        }
        return nil
    }

    private static func ensureAssets() throws -> String {
        if let existing = resolveAssetPath() {
            return existing
        }

        try? FileManager.default.createDirectory(atPath: xrayBarAssets, withIntermediateDirectories: true)

        var lastError: Error?
        for name in assetFiles {
            guard let url = URL(string: "\(assetDownloadBase)/\(name)") else { continue }
            let semaphore = DispatchSemaphore(value: 0)
            let dest = (xrayBarAssets as NSString).appendingPathComponent(name)
            var downloadError: Error?

            URLSession.shared.downloadTask(with: url) { tmpURL, _, error in
                defer { semaphore.signal() }
                if let error {
                    downloadError = error
                    return
                }
                guard let tmpURL else {
                    downloadError = NSError(domain: "XrayBar", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to download \(name)"])
                    return
                }
                try? FileManager.default.removeItem(atPath: dest)
                do {
                    try FileManager.default.moveItem(at: tmpURL, to: URL(fileURLWithPath: dest))
                } catch {
                    downloadError = error
                }
            }.resume()
            semaphore.wait()

            if let downloadError {
                lastError = downloadError
            }
        }

        if let lastError {
            throw XrayLaunchError.missingAssets(
                "Missing geo data files (geosite.dat/geoip.dat).\n"
                + "Download failed: \(lastError.localizedDescription)\n\n"
                + "Install manually:\n"
                + "  brew install xray\n"
                + "Or download .dat files to ~/.xray/assets/")
        }

        return xrayBarAssets
    }

    func start(configURL: URL, onUnexpectedTermination: @escaping () -> Void) throws {
        stop()

        Self.ensureLogDirectories(configURL: configURL)

        let assetPath = try Self.ensureAssets()

        let (exec, prefixArgs) = Self.resolveXray()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exec)
        proc.arguments = prefixArgs + ["run", "-c", configURL.path]

        var env = proc.environment ?? [:]
        env["XRAY_LOCATION_ASSET"] = assetPath
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.outputPipe = pipe

        expectingRestart = false

        try proc.run()

        // Probe: xray fails fast on config errors. Block briefly so we can
        // surface its stderr instead of silently leaving the user with a
        // disabled proxy and no clue why.
        Thread.sleep(forTimeInterval: Self.startupProbeInterval)

        if !proc.isRunning {
            let data = pipe.fileHandleForReading.availableData
            let output = String(data: data, encoding: .utf8) ?? ""
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = trimmed.isEmpty
                ? "exited with status \(proc.terminationStatus)"
                : trimmed
            self.outputPipe = nil
            throw XrayLaunchError.launchFailed(detail)
        }

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.lastOutput = str
            }
        }

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                if self?.expectingRestart == false {
                    onUnexpectedTermination()
                }
            }
        }

        self.process = proc
    }

    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil

        guard let proc = process, proc.isRunning else {
            process = nil
            outputPipe = nil
            return
        }

        expectingRestart = true
        proc.terminate()
        proc.waitUntilExit()
        process = nil
        outputPipe = nil
    }

    private static func ensureLogDirectories(configURL: URL) {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let log = json["log"] as? [String: Any] else { return }

        for key in ["access", "error"] {
            guard let raw = log[key] as? String,
                  !raw.isEmpty,
                  raw.lowercased() != "none" else { continue }
            let expanded = (raw as NSString).expandingTildeInPath
            let parent = (expanded as NSString).deletingLastPathComponent
            guard !parent.isEmpty, parent != "/" else { continue }
            try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        }
    }
}
