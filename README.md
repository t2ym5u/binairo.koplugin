# binairo.koplugin

A Binairo (Takuzu) puzzle plugin for [KOReader](https://github.com/koreader/koreader).

## Screenshot

*(Screenshot to be added.)*

## Rules

Fill the grid with 0s and 1s so that every row and column has an equal number of each, no three consecutive cells share the same value, and no two rows (or two columns) are identical.

## Features

- **Multiple grid sizes**
- **Three difficulty levels** — Easy, Medium, Hard
- **Timer** — elapsed time shown, best time recorded on solve
- **Error check** — highlights rule violations without revealing the solution
- **Reveal solution**
- **Undo**
- **Auto-save** — puzzle state saved and restored on next launch

## Controls

| Action | How |
|--------|-----|
| Cycle a cell (blank → 0 → 1 → blank) | Tap it |
| Undo last move | Tap **Undo** |
| Check for errors | Tap **Check** |
| Reveal solution | Tap **Reveal** |
| New game | Tap **New game** |
| Change grid size / difficulty | Tap **Grid** / **Difficulty** |
| Show rules | Tap **Rules** |

## Installation

1. Download `binairo.koplugin.zip` from the [latest release](../../releases/latest).
2. Extract into the `plugins/` folder of your KOReader data directory.
3. Restart KOReader.
4. Open the menu → **Tools** → **Binairo**.

## License

GPL-3.0 — see [LICENSE](LICENSE).
