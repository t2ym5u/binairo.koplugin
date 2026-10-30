# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2026-10-30

### Changed
- Redesigned play screen: the grid fills the room the controls leave, framed
  by one thick border of its own, with a full-width Undo/Check/Hint/Reveal
  bar.
- The menu is the regular title-bar menu shared by every game, instead of a
  separate pop-up: New game, "Size: 8×8" (was "Grid: 8×8"), "Difficulty:
  Medium", Rules.
- The status line reads "8×8 · Medium · Empty: 32" and wraps in landscape
  instead of being cut off.
- Once the grid is solved (or revealed), the action bar shows "New game" in
  place of its buttons.

### Fixed
- The size picker opened empty: it was passed option names the shared menu
  helper does not read.
- An applied Hint no longer wipes the saved game (game-common saved it as
  nil). When a hint fills the last cell, the status now shows the win message.

## [1.1.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.1.0] - 2026-09-30

### Added
- **Hint** button. Two taps, not one: the first says which cell is about to
  give, the second acts on it -- a player who is told where to look usually
  finds the rest themselves, and only pays for the full reveal if they want
  it. A cell that contradicts the solution is always reported before a fresh
  one is revealed, and on a mistake the hint empties the cell rather than
  solving it.

## [1.0.12] - 2026-07-31

### Fixed
- `board_widget.lua` referenced Blitbuffer color constants that don't
  exist (COLOR_GRAY_A), which evaluated to `nil` and crashed the
  color-comparison in `paintTo()` as soon as the corresponding
  highlight was drawn. Now uses the correct constant name(s)
  (COLOR_GRAY).

## [1.0.9] - 2026-07-29

### Fixed
- Generated puzzles had no uniqueness verification at all — the clue set
  was a flat random fraction of the solution, with no check for other
  valid completions. Added a backtracking uniqueness solver and reworked
  generation to dig cells one at a time, verifying after each removal
  that exactly one solution remains, so every puzzle now ships with a
  provably unique solution.
- The generator's fill routine also never enforced that all rows and all
  columns of the completed grid be pairwise distinct (a core Binairo
  rule), so the stored solution itself could occasionally break that
  rule. The fill routine now rejects any placement that would make two
  rows or two columns identical.
