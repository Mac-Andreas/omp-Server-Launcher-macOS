# open.mp Server Launcher (macOS)

A native **Swift / SwiftUI** app for running the Windows **open.mp** server on
macOS (Apple Silicon). It downloads and manages its own 32-bit-capable Wine
runtime — **no CrossOver required**.

## Features

- **Overview** — download + install the Wine runtime, check the Wine prefix and
  server files at a glance.
- **Server** — Start / Stop / Restart / Launch open.mp, with an embedded live
  log (small timestamps, colourised errors/warnings).
- **Config** — modern `config.json` editor: sliders, gamemode/filterscript
  dropdowns, input guardrails; preserves keys it doesn't surface.
- **Bans** — view and remove entries from `bans.json`.
- **Logs** — one snapshot per server session, auto-saved on stop; view inline,
  export, or delete.
- **Settings** — optional anonymous telemetry (off by default), update check.
- Close hides the window; the server keeps running until you Quit.

## How it works

The `.app` is dropped **into** the open.mp server folder, so `omp-server.exe`,
`config.json`, `bans.json`, `components/`, `gamemodes/`, `filterscripts/` sit
beside it. The launcher runs the server under a downloaded Wine build
(wine32on64-capable) in a prefix under
`~/Library/Application Support/open.mp Server Launcher`.

## Build

Requires Xcode 16+ / Swift 6 on macOS 14+.

```sh
swift build                 # debug build
scripts/build-app.sh        # release build -> dist/open.mp Server Launcher.app
```

## Install

Download the latest `.app` from
[Releases](https://github.com/Mac-Andreas/open.mp-Server-Launcher-macOS/releases),
drop it into your server folder, open it, then **Overview → Download** the Wine
runtime and **Server → Start**.

The build is ad-hoc signed (not notarized): on first launch, right-click → Open
(or System Settings → Privacy & Security → Open Anyway).

## Telemetry

Optional, off by default. When enabled, anonymous usage events are sent through
a server-side proxy — **the app ships no database credentials**. No personal
data, servers, or configs are ever sent.

## Credits

- Wine runtime: [Gcenx / macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)
- [WineHQ](https://www.winehq.org) · [open.mp](https://open.mp)

Made by the **Mac Andreas Team**. Free software under the **GNU GPL v3** or later.
