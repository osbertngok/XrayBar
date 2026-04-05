import Foundation

// XrayBarHelper — a small setuid helper to toggle system proxy without password prompts.
// Install once: sudo cp XrayBarHelper /usr/local/bin/ && sudo chown root:admin /usr/local/bin/XrayBarHelper && sudo chmod 4755 /usr/local/bin/XrayBarHelper

func run(_ args: [String]) -> Int32 {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    proc.arguments = args
    try? proc.run()
    proc.waitUntilExit()
    return proc.terminationStatus
}

func enableProxy(service: String, httpPort: String, socksPort: String) -> Int32 {
    var status: Int32 = 0
    status = run(["-setwebproxy", service, "127.0.0.1", httpPort])
    guard status == 0 else { return status }
    status = run(["-setsocksfirewallproxy", service, "127.0.0.1", socksPort])
    guard status == 0 else { return status }
    status = run(["-setwebproxystate", service, "on"])
    guard status == 0 else { return status }
    status = run(["-setsocksfirewallproxystate", service, "on"])
    return status
}

func disableProxy(service: String) -> Int32 {
    var status: Int32 = 0
    status = run(["-setwebproxystate", service, "off"])
    guard status == 0 else { return status }
    status = run(["-setsocksfirewallproxystate", service, "off"])
    return status
}

// Parse args: XrayBarHelper <on|off> [--service Wi-Fi] [--http-port 1087] [--socks-port 1080]
let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: XrayBarHelper <on|off> [--service <name>] [--http-port <port>] [--socks-port <port>]\n", stderr)
    exit(1)
}

let command = args[1]
var service = "Wi-Fi"
var httpPort = "1087"
var socksPort = "1080"

var i = 2
while i < args.count {
    switch args[i] {
    case "--service" where i + 1 < args.count:
        service = args[i + 1]; i += 2
    case "--http-port" where i + 1 < args.count:
        httpPort = args[i + 1]; i += 2
    case "--socks-port" where i + 1 < args.count:
        socksPort = args[i + 1]; i += 2
    default:
        fputs("Unknown argument: \(args[i])\n", stderr)
        exit(1)
    }
}

switch command {
case "on":
    exit(enableProxy(service: service, httpPort: httpPort, socksPort: socksPort))
case "off":
    exit(disableProxy(service: service))
default:
    fputs("Unknown command: \(command). Use 'on' or 'off'.\n", stderr)
    exit(1)
}
