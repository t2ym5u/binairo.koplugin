# Changelog

All notable changes to this project will be documented in this file.

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
