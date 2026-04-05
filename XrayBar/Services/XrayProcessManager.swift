import Foundation

final class XrayProcessManager {
    private static let xrayPath = "/opt/homebrew/bin/xray"

    private var process: Process?
    private var outputPipe: Pipe?
    private var expectingRestart = false

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    private(set) var lastOutput: String = ""

    func start(configURL: URL, onUnexpectedTermination: @escaping () -> Void) throws {
        stop()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.xrayPath)
        proc.arguments = ["run", "-c", configURL.path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.outputPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.lastOutput = str
            }
        }

        expectingRestart = false

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                // Only notify if this was an unexpected termination (crash, etc.)
                // Not when we explicitly stopped it for restart/shutdown
                if self?.expectingRestart == false {
                    onUnexpectedTermination()
                }
            }
        }

        try proc.run()
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
}
