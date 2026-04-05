# XrayBar

A lightweight macOS menu bar app for managing [Xray](https://github.com/XTLS/Xray-core) proxy profiles. It provides a simple interface to connect/disconnect Xray and toggle system proxy settings — without requiring a full GUI client like V2rayU.

## Features

- **One-click connect/disconnect** — starts Xray and enables system proxy together
- **Profile switching** — pick from multiple Xray JSON configs; hot-swap while connected
- **System proxy management** — automatically configures macOS HTTP and SOCKS proxy (Wi-Fi)
- **No password prompts** — installs a small setuid helper on first run; subsequent toggles are instant
- **Menu bar only** — no Dock icon, no windows; lives entirely in the menu bar
- **Edit configs** — opens your selected config in your default text editor
- **Launch at Login** — optional auto-start via macOS login items

## Prerequisites

```bash
brew install xray
```

## Configuration

XrayBar reads Xray JSON config files from:

```
~/.xray/configs/
```

Place your Xray configuration files there as `.json` files. Each file appears as a selectable profile in the menu.

Example:

```
~/.xray/configs/
├── my-server.json
├── us-west.json
└── backup.json
```

These are standard [Xray JSON configuration files](https://xtls.github.io/en/config/) — XrayBar passes them directly to `xray run -c <file>` with no modification or validation, so any valid Xray config works (including advanced features like `dialerProxy` chaining, custom routing rules, etc.).

### Proxy ports

XrayBar enables system proxy on Wi-Fi with these defaults (matching the standard Xray config convention):

| Protocol | Address       | Port |
|----------|---------------|------|
| HTTP     | 127.0.0.1     | 1087 |
| SOCKS5   | 127.0.0.1     | 1080 |

Make sure your Xray config has matching inbound listeners. For example:

```json
{
  "inbounds": [
    {
      "port": "1080",
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": { "auth": "noauth", "udp": false }
    },
    {
      "port": "1087",
      "listen": "127.0.0.1",
      "protocol": "http",
      "settings": { "timeout": 360 }
    }
  ]
}
```

## Building from source

Requires Xcode 16+ and macOS 14+.

```bash
brew install xcodegen
cd XrayBar
xcodegen generate
xcodebuild -scheme XrayBar -configuration Release build
```

The built app is at:

```
~/Library/Developer/Xcode/DerivedData/XrayBar-*/Build/Products/Release/XrayBar.app
```

Copy it to `/Applications/` to install.

## First run

On first connect, XrayBar will prompt for your admin password **once** to install a small helper tool (`XrayBarHelper`) to `/usr/local/bin/`. This helper is set as setuid root so that subsequent proxy toggles don't require a password. You will not be prompted again.

## How it works

1. **Connect** — launches `xray run -c <selected-config>` as a child process, then enables system HTTP + SOCKS proxy on Wi-Fi via `networksetup`
2. **Disconnect** — terminates the Xray process and disables system proxy
3. **Profile switch** — if connected, seamlessly stops the current Xray process and starts a new one with the selected config
4. **Quit** — automatically disconnects (stops Xray + disables proxy) before exiting

## License

MIT
