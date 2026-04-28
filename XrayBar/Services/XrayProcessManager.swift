import Foundation

enum XrayLaunchError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let detail):
            return "xray failed to start:\n\(detail)"
        }
    }
}

final class XrayProcessManager {
    private static let xrayPath = "/opt/homebrew/bin/xray"
    private static let startupProbeInterval: TimeInterval = 0.3

    private var process: Process?
    private var outputPipe: Pipe?
    private var expectingRestart = false

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    private(set) var lastOutput: String = ""

    func start(configURL: URL, onUnexpectedTermination: @escaping () -> Void) throws {
        stop()

        Self.ensureLogDirectories(configURL: configURL)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.xrayPath)
        proc.arguments = ["run", "-c", configURL.path]

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
