# Changelog

All notable changes to this project will be documented in this file.

## [1.5.1] - 2026-11-12

### Changed
- Picks up game-common 1.16.0: games for two readers (new Two readers
  category) and the shared Start / Join dialog.

## [1.5.0] - 2026-11-05

### Changed
- Difficulty levels now really differ, and no puzzle needs guessing.
  Before, levels only showed fewer cells, and digging only checked that
  the answer stayed unique: some puzzles (12×12 Hard: 30%, 12×12 Medium:
  10%) could only be finished by trial and error, while many Medium and
  Hard ones needed nothing beyond the basic rules. Each puzzle is now
  graded by a human-style solver:
  - Easy: the basic rules only (close a pair, fill a gap, complete a
    line that already has all its 0s or 1s). About half the cells shown.
  - Medium: also needs a few whole-line deductions ("every way to finish
    this row puts a 1 here"). About a third of the cells shown.
  - Hard: fewer cells shown (about a fifth to a quarter) and many more
    whole-line deductions.
- Grids differ from 1.4.x for the same seed (today's Daily Challenge grid
  changes once after updating). Saved games still load.

## [1.4.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.4.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.4.0] - 2026-11-04

### Changed
- Much faster puzzle generation. The solution grid is now built a whole row
  at a time; the old cell-by-cell construction occasionally got stuck
  backtracking (12×12: up to 1.6 s on a desktop, i.e. most of a minute on a
  Kobo). The uniqueness check only has to rule out the other value in the
  cell being removed. 12×12 Hard now takes at most ~35 ms on a desktop
  (about 1 s on a Kobo), 10×10 at most ~20 ms (was 60-135 ms).
- A progress bar appears if generating takes more than a moment.
- Puzzles are now unique even without the "no two identical rows or
  columns" rule, which the in-game rules don't mention.
- Grids differ from 1.3.x for the same seed (today's Daily Challenge grid
  changes once after updating).

## [1.3.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.3.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.3.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.3.0] - 2026-10-30

### Added
- "Daily Challenge" in the menu, right after "New game": today's puzzle at
  your size and difficulty, the same grid for everyone playing it today.
  Needs game-common 1.7.0.

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
