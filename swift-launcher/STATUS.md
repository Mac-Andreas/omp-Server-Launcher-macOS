# open.mp Server Launcher — Swift rewrite STATUS

Ground-up native **Swift / SwiftUI** rebuild of the Qt/C++ launcher, living in
`swift-launcher/` beside the original. The C++ app in `../src` is the behavior
spec; this folder is independent and ships on its own.

- **Target:** macOS 14+ (built on macOS 26 / Swift 6.3 / Xcode 26)
- **Build:** Swift Package Manager executable → bundled into a `.app`
- **Release repo:** `Mac-Andreas/open.mp-Server-Launcher-macOS`
- **Version:** v1.0.0

---

## What it does (ported from the C++ app)

Runs the **Windows 32-bit** `omp-server.exe` under **CrossOver's Wine** in a
dedicated 32-bit bottle (`OpenMPServer`). The `.app` is dropped into the
server folder; server files (`omp-server.exe`, `config.json`, `bans.json`,
`log.txt`, `components/`, `gamemodes/`, `filterscripts/`) are the `.app`'s
**siblings** (resolved by walking up 3 from `…/Contents/MacOS`).

## Telemetry — key never ships in the app

The C++ app posted directly to Supabase with a publishable key read from env
vars (so it never fired for real users, and any baked key is `strings`-able).

This rewrite routes telemetry through a **Supabase Edge Function** proxy:

```
app  ──POST event──▶  Edge Function (holds service key server-side)  ──insert──▶  telemetry_events
```

- The app embeds only the **public Edge Function URL** — no DB key at all.
- The function validates/limits the payload and inserts with a key that never
  leaves Supabase. Leak surface = zero key in the client.
- RLS on `telemetry_events` still denies anon writes; only the function's
  service role inserts. Defense in depth.

Edge function source: `supabase/functions/telemetry/`.

---

## Module map (`Sources/ServerLauncher/`)

| File | Role | Ported from |
|------|------|-------------|
| `App.swift`            | `@main`, window, cwd setup, dock-reopen | `main.cpp` |
| `Core/CrossOver.swift` | Wine paths, bottle create/delete, serverDir, kill | `CrossOver.cpp` |
| `Core/ServerController.swift` | start/stop/restart, live log stream | `LauncherWindow.cpp` |
| `Core/ConfigStore.swift` | `config.json` read/write, preserve unknown keys | `LauncherWindow.cpp` |
| `Core/BansStore.swift` | `bans.json` array model | `LauncherWindow.cpp` |
| `Core/Telemetry.swift` | event POST → Edge Function | `TelemetryManager.cpp` |
| `Core/Updater.swift`   | GitHub releases-latest + semver compare | `Updater.cpp` |
| `Core/AppInfo.swift`   | version, update repo, endpoint URL | `AppInfo.h` |
| `Views/…`              | tabbed UI: Server / Config / Bans / Logs / License | `LauncherWindow.cpp` |

---

## Progress

- [ ] STATUS.md
- [ ] Package.swift + scaffold
- [ ] CrossOver.swift
- [ ] ServerController.swift
- [ ] ConfigStore.swift + BansStore.swift
- [ ] Telemetry.swift
- [ ] Updater.swift
- [ ] Edge Function (telemetry proxy)
- [ ] SwiftUI views + footer version pill
- [ ] build script → .app
- [ ] builds + runs clean
- [ ] pushed to release repo
- [ ] v1.0 .app release

## TODO backlog (from ../To-Do.md) — v1.0 vs deferred

**In v1.0 (core):**
- Server start / stop / restart / open folder / launch open.mp multiplayer
- Config editor modernized: sliders (max_players, capped), dropdowns
  (gamemode/filterscript from `*.amx`), guardrails (no negatives, no
  scroll-to-change on number fields), "Server Password" label, config-missing
  state when no `config.json`
- Bans view
- Log viewer: smaller timestamps, Cmd +/-/0 font size, server-log title icon
- Footer: "made with ♥ (no emoji) by Mac Andreas Team | <gh> repository … |
  v1.0 (Update Available …)"
- Update **check** + button next to version pill (open release page)
- Telemetry via Edge Function

**Deferred (later sessions):**
- In-app auto-**install** updater (download + replace + restart + post-update
  start-server toggle, hold-to-confirm)
- Log snapshots saved to `.server_launcher/` + Application Support, "View logs"
  tab listing snapshots
- Cron-jobs tab (hosting-provider presets + custom cron)
- Daily GMT update ticker

## Notes / gotchas
- Server files are the `.app`'s **siblings**, not inside it (see serverDir).
- 32-bit bottle required (64-bit fails "cannot execute").
- Start preflight: kill any running `omp-server.exe` + `wineserver` first.
- Close ≠ quit: window hides, app + server keep running; quit via Cmd-Q / tray.
- Number fields: disable scroll-wheel increment (explicit TODO guardrail).
