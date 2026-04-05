import Foundation

enum ProxyError: LocalizedError {
    case commandFailed(Int32)
    case installFailed

    var errorDescription: String? {
        switch self {
        case .commandFailed(let code):
            return "Proxy command failed with exit code \(code)"
        case .installFailed:
            return "Failed to install XrayBarHelper"
        }
    }
}

final class ProxyManager {
    private static let installedHelperPath = "/usr/local/bin/XrayBarHelper"

    /// Path to the helper bundled with the app
    private var bundledHelperPath: String? {
        // xcodegen copies it into Contents/Resources/
        if let p = Bundle.main.path(forResource: "XrayBarHelper", ofType: nil),
           FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        // Fallback: sibling in the same build products directory
        guard let appPath = Bundle.main.executablePath else { return nil }
        let dir = (appPath as NSString).deletingLastPathComponent
        let candidate = (dir as NSString).appendingPathComponent("XrayBarHelper")
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    var isHelperInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Self.installedHelperPath)
    }

    /// Install the helper as setuid root (one-time, prompts for admin password via osascript)
    func installHelper() throws {
        guard let src = bundledHelperPath else {
            throw ProxyError.installFailed
        }

        let commands = [
            "cp '\(src)' '\(Self.installedHelperPath)'",
            "chown root:admin '\(Self.installedHelperPath)'",
            "chmod 4755 '\(Self.installedHelperPath)'",
        ]
        let joined = commands.joined(separator: " && ")
        let script = "do shell script \"\(joined)\" with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw ProxyError.installFailed
        }
    }

    func enableProxy() throws {
        try runHelper(["on"])
    }

    func disableProxy() throws {
        try runHelper(["off"])
    }

    func checkProxyEnabled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        proc.arguments = ["-getwebproxy", "Wi-Fi"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("Enabled: Yes")
    }

    private func runHelper(_ arguments: [String]) throws {
        if !isHelperInstalled {
            try installHelper()
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.installedHelperPath)
        proc.arguments = arguments
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw ProxyError.commandFailed(proc.terminationStatus)
        }
    }
}
