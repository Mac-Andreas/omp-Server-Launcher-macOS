<div align="center">

# open.mp Server Launcher

**Run your [open.mp](https://open.mp) server on macOS — no Windows, no VM.**

A small native macOS app that launches the Windows open.mp server through
CrossOver, with a built-in config editor, ban manager, and live log viewer.

![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon%20%26%20Intel-blue)
![License](https://img.shields.io/badge/license-GP%20v3-green)

</div>

---

## Why this exists

open.mp ships its server only as a **32-bit Windows** binary — there is no
native macOS build. This launcher runs `omp-server.exe` through
[CrossOver](https://www.codeweavers.com/crossover)'s Wine engine in a dedicated
**32-bit bottle** (`OpenMPServer`), so you can host an open.mp server on a Mac
without a full Windows VM.

It's the server companion to **Qawno** (the open.mp Pawn editor): Qawno compiles
your gamemode, this runs the server.

## Features

- **One-click start / stop / restart** with a live, streaming server log.
- **CrossOver detection** + one-button creation of the 32-bit server bottle.
- **Config editor** — edit the common `config.json` fields (name, gamemode,
  filterscript, port, max players, password, RCON) with gamemode/filterscript
  **dropdowns populated from your server folder**. All other config keys are
  preserved untouched.
- **Ban manager** — view, add, and remove entries in `bans.json`.
- **Log viewer** — stream live output and open `log.txt` in your editor.
- **Stays out of the way** — closing the window keeps the server running;
  optional menu-bar icon and run-at-login.
- **Update notifications** — checks GitHub for new releases.

## Requirements

- macOS (Apple Silicon or Intel)
- [CrossOver](https://www.codeweavers.com/crossover) installed in
  `/Applications`
- The **Windows** open.mp server files (`open.mp-win-x86.zip`)

## Install & use

1. Download the latest **open.mp Server Launcher.app** from
   [Releases](../../releases) (or build it — see below).
2. Get the **Windows** server files and put them in your server folder:
   `omp-server.exe`, `components/*.dll`, `config.json`, `gamemodes/`, …
   (from `open.mp-win-x86.zip`).
3. Drop **open.mp Server Launcher.app** into that **same folder**, beside
   `omp-server.exe`.
4. Open it. On the **Server** tab:
   - **CrossOver** card → click **Set up OpenMPServer bottle** (one time).
   - **Server files** card confirms `omp-server.exe` is found.
   - Click **Start server**.

The Wine wrapper ships inside the app, so you only supply the Windows server
files — nothing else to install.

## Building from source

```sh
brew install qt cmake
./build-macos.sh            # -> build/, then copies the .app into dist/
./build-macos.sh --deploy   # also bundle Qt frameworks (standalone, shippable)
./build-macos.sh --clean    # wipe build/ first
```

The finished app is always copied into [`dist/`](dist/).

## Advanced

Wrapper environment overrides (rarely needed):

| Variable           | Default        | Purpose                          |
| ------------------ | -------------- | -------------------------------- |
| `WINE`             | CrossOver Wine | Path to the `wine` binary        |
| `OMP_WINE_BOTTLE`  | `OpenMPServer` | Bottle name                      |
| `OMP_SERVER_DIR`   | server folder  | Where `omp-server.exe` lives     |

## License

Licensed under the **GNU General Public License v3** — see
[LICENSE.txt](LICENSE.txt). You may use, modify, and distribute it (including
commercially), provided you disclose source, keep the same license, and state
your changes. No warranty.

## Credits

- open.mp server & toolchain — the [open.mp](https://open.mp) team
- macOS launcher — xyranaut
