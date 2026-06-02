# Changelog

All notable changes to the open.mp Server Manager are documented here.

## [2.0.0] — 2026-06-02

A large layout and consistency overhaul: every page now shares the same chrome,
and the destructive-action and storage flows were reworked.

### Added
- **Unified page scaffold.** Every tab is now built from one shared block
  (`PageScaffold`) with opt-in header / scope / footer bands, so headers and
  footers line up edge-to-edge across the whole app. Pages just declare what
  goes in each band.
- **Global footer tiles.** Page actions live in a single full-width footer tile
  (`PageFooterBar`): Server's Install/Import, Config's Open in Finder · Refresh ·
  Save, Bans' Reload, Snapshots' Delete all — all one consistent look.
- **Storage settings, expanded.** The Storage tab now offers Clear Wine
  downloads, Uninstall Wine, and Clear app cache, plus a **Danger zone** to
  delete all macOS or all Windows servers.
- **Guarded destructive actions.** "Delete all …" is gated behind a confirmation
  that counts down (10s) before unlocking a press-and-hold-to-confirm button, so
  nothing irreversible happens on a stray click.
- **Server lock indicator.** A server's locked/unlocked state now shows as a
  compact icon right next to its name.

### Changed
- **Consistent scrollbars.** All scrolling areas use overlay scrollbars, so
  switching between a short page and a scrolling one no longer shifts the content
  left/right.
- **Snapshots server filter** now matches the Bans/Config server picker exactly —
  same rows (name + created date, version pill, status) and uniform row height,
  with an "All servers" option.
- **Dark action colors everywhere.** Red/green action buttons (Cancel, Save,
  Install, Delete, the Storage cleanup buttons, and the List-on-open.mp No/Yes
  toggle) now use the darker red/green shades for a consistent theme.
- **Install dialog usability.** The RCON field shows the text-select cursor like
  the name field, and pressing Return installs when the form is valid.

### Fixed
- Snapshots dropdown could let a same-colored card bleed through the open menu;
  the menu is now fully opaque over content beneath it.
- Page content no longer jumps horizontally when moving between tabs.

## [1.x] — earlier

Native macOS (SwiftUI) launcher for open.mp servers: install/import/run macOS
and Windows-32 (via Wine) servers, edit config.json, manage bans, view session
snapshots, and in-place engine updates.
