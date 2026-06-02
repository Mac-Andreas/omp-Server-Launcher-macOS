# open.mp — Server Manager (macOS)

A native **Swift / SwiftUI** app for installing, configuring and running
**open.mp** servers on macOS (Apple Silicon). It manages **native macOS** servers
and **Windows-32 servers via Wine** — downloading and managing its own 32-bit
capable Wine runtime, so **no CrossOver is required**.

## Features

- **Server** — install official builds or import existing servers, then
  Start / Stop / Restart each one independently. Every server has live CPU/RAM
  stats, an inline colourised log, in-place engine updates (with one-click
  revert), and a lock indicator. macOS and Windows-32 (via Wine) servers are
  managed side by side.
- **Setup** — check the native macOS runtime and the Wine runtime; download or
  re-fetch the 32-bit Wine build used for Windows servers.
- **Config** — a modern `config.json` editor: name, passwords, port, max players,
  open.mp listing, single-select gamemode, and live filterscript / plugin
  toggles. Input guardrails throughout; keys it doesn't surface are preserved.
- **Bans** — view and remove entries from a server's `bans.json`.
- **Snapshots** — one log snapshot per server session, auto-saved on stop; view
  inline, export, or delete, filtered per server.
- **Settings** — Storage maintenance (clear Wine downloads, uninstall Wine, clear
  app cache, bulk-delete servers), privacy/telemetry toggle, update check, and
  about.

The whole UI shares one consistent layout: every tab has the same header, scope
picker and footer-action bands.

## How it works

Servers live in their own folders under
`~/Documents/omp-server-manager/` (installed builds) or wherever you imported
them from. Windows-32 servers run under a downloaded Wine build
(wine32on64-capable) in a prefix under
`~/Library/Application Support/Server Manager`. Closing the window hides it; your
servers keep running until you Quit.

## Build

Requires Xcode 16+ / Swift 6 on macOS 14+.

```sh
swift build                 # debug build
scripts/build-app.sh        # release build + DMG -> dist/
```

## Install

Download the latest DMG from
[Releases](https://github.com/Mac-Andreas/omp-Server-Manager-macOS/releases),
open it, and drag the app to **Applications**. Launch it, then add a server from
the **Server** tab (Install or Import).

The build is ad-hoc signed (not notarized): on first launch, right-click → Open
(or System Settings → Privacy & Security → Open Anyway). Run it from Applications,
not from the mounted DMG.

## Telemetry

Optional, **off by default**. When enabled, anonymous usage is sent through a
server-side proxy — **the app ships no database credentials**. No personal data,
servers, or configs are ever sent.

## Credits

- Wine runtime: [Gcenx / macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)
- [WineHQ](https://www.winehq.org) · [open.mp](https://open.mp)

Made by the **Mac Andreas Team**. Free software under the **GNU GPL v3** or later.
