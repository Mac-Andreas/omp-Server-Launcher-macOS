# Server Launcher — developer / Claude notes

Context for working on this subproject. (User-facing docs live in `README.md`.)

## What this is

A standalone native macOS Qt app that runs the **Windows** open.mp server
(`omp-server.exe`) under **CrossOver's Wine** in a dedicated 32-bit bottle
(`OpenMPServer`). It is a **separate project** from the parent `qawno` app —
own CMake, own `main`, own copy of the `CrossOver` helper — deliberately
self-contained so the whole `Server Launcher/` folder can be moved out and
shipped on its own. Do **not** assume it shares build state with qawno.

Relationship to qawno: qawno *compiles* Pawn (in the `Qawno` bottle); this
*runs* the server (in the `OpenMPServer` bottle). Two different bottles on
purpose.

## Why CrossOver / Wine

open.mp ships only a **32-bit Windows** server — no native macOS build. So the
server runs through CrossOver. It **must** be a 32-bit bottle; a 64-bit bottle
fails with "cannot execute". (Parallel to qawno's reason for running the
Windows `pawncc.exe`: the native macOS pawncc emits AMX magic `0xF1E1`, which
the server rejects — see the parent project.)

## Layout

```
Server Launcher/
  CMakeLists.txt          # Qt Core/Widgets/Network; macOS bundle; builds .icns
  build-macos.sh          # build -> build/, then copies .app into dist/
  launcher.qrc            # embeds assets/icon.png as :/icon.png
  LICENSE.txt             # GPLv3, bundled into Contents/Resources
  assets/                 # icon PNGs (16..1024) + server-icon.svg source
  scripts/
    run-omp-server-wine.sh  # ships INSIDE the bundle, next to the executable
  src/
    main.cpp              # entry; sets cwd; dock-reopen filter; window icon
    AppInfo.h             # version + GitHub update repo (PLACEHOLDER repo!)
    CrossOver.{h,cpp}     # CrossOver/Wine detection, bottle create/delete,
                          #   server-files check, kill running servers
    Updater.{h,cpp}       # async GitHub releases-latest check
    LauncherWindow.{h,cpp}# the whole UI (tabbed): Server/Config/Bans/License
```

## Key paths & how files are found

- The `.app` is **dropped into the open.mp server folder** by the user. So the
  server files (`omp-server.exe`, `config.json`, `bans.json`, `log.txt`,
  `components/`, `gamemodes/`, `filterscripts/`) are the **`.app`'s siblings**,
  not inside it.
- `CrossOver::serverDir()` = the folder containing the `.app` (it walks up from
  `applicationDirPath()` = `.app/Contents/MacOS` → up 3). All config/bans/log
  reads use this, **not** `applicationDirPath()`.
- The Wine wrapper `run-omp-server-wine.sh` is bundled **inside**
  `Contents/MacOS/` (CMake POST_BUILD copy). The server runs with cwd =
  `serverDir()` and `OMP_SERVER_DIR` set, so `omp-server.exe` finds its config.
- `LICENSE.txt` is copied into `Contents/Resources/`; the License tab reads it
  from `applicationDirPath()/../Resources/LICENSE.txt`.

## config.json mapping (verified against a real open.mp config)

The Config tab edits a known subset and **preserves all other keys**:

| Form field    | JSON path             |
| ------------- | --------------------- |
| Server name   | `name`                |
| Password      | `password`            |
| Max players   | `max_players`         |
| Port          | `network.port`        |
| RCON password | `rcon.password`       |
| Gamemode      | `pawn.main_scripts[]` (array of names) |
| Filterscript  | `pawn.side_scripts[]` |

Gamemode/filterscript dropdowns are filled from `*.amx` in
`serverDir()/gamemodes` and `/filterscripts`. NOTE: open.mp's `main_scripts`
entries are often `"name 1"` (script + RCON-arg); the editor currently writes
the bare name. `bans.json` is a JSON array of `{address, player, reason, time}`
objects (can be empty `[]`).

## Behaviours worth remembering

- **Start preflight**: if any `omp-server.exe` is already running (this app or
  external), it's killed first (`CrossOver::killRunningServers()` uses
  `pkill -f omp-server.exe` + `wineserver`) so the port isn't double-bound.
- **Close ≠ quit**: `closeEvent` hides the window unless `quitting_` is set.
  The app keeps running (server too). Quit via dock/Cmd-Q or the tray "Quit".
  Dock-icon click reshows via the `ReopenFilter` in `main.cpp`.
- **Bottle create/delete**: deliberately blocks the main thread (no
  `processEvents`) so macOS shows its native spinning-beachball cursor.
- **Settings menu**: Run-at-login uses `osascript` System Events login items
  (no extra entitlements); Show-in-menu-bar toggles a `QSystemTrayIcon`.
- **Updates**: `Updater` hits
  `api.github.com/repos/<owner>/<repo>/releases/latest`. The owner/repo in
  `AppInfo.h` is a **PLACEHOLDER** (`xyranaut/openmp-server-launcher`) — must be
  set to the real published repo before release. Shows an `⬆ Update vX` button
  left of the version pill when a newer tag exists.

## Build / verify

```sh
brew install qt cmake
./build-macos.sh          # -> dist/open.mp Server Launcher.app
```

No screenshots to verify UI (user preference) — build must pass, then the user
checks visually. The IDE shows include-path errors for Qt headers because the
subproject isn't in the IDE's compile DB; ignore those — only the CMake build
result matters.

## Gotchas (inherited from the parent project)

- Don't `--deploy` then rebuild without `--clean`: a leftover bundled
  `Contents/Frameworks` + Homebrew Qt both load → "two sets of Qt" → SIGABRT.
- The throwaway SVG→PNG renderer used to make the icon was compiled ad hoc with
  the Homebrew Qt frameworks; it's not committed. Regenerate icons from
  `assets/server-icon.svg` if needed.
