# Repository Guidelines

## Project Structure & Module Organization
- `try.rb`: Single-file Ruby CLI and TUI (no gems).
- `flake.nix`/`flake.lock`: Nix packaging and Home Manager module.
- `README.md`: Usage, installation, and philosophy.
- Tries live outside this repo (default `~/src/tries`, configurable via `TRY_PATH`).

## CLI Interface
- `try init [PATH]`: Emits a shell function for your shell rc. PATH sets the root (absolute path recommended). The function evals the printed script to `cd` into selections.
- `try cd [QUERY]`: Launches the interactive selector. If `QUERY` looks like a Git URL, it performs a clone workflow instead. Prints a shell script to stdout; use via the installed function.
- `try clone <git-uri> [name]`: Clones into the root. Default name is `YYYY-MM-DD-user-repo` (strips `.git`). Optional `name` overrides.
- Flags: `--path PATH` (for `cd`/`clone`) overrides the root for that call; `--help` prints global help.
- Environment: `TRY_PATH` sets the default root when not using `--path`.
- UI keys: `↑/↓` or `Ctrl-P/N` navigate, `Enter` select, `Backspace` delete char, `Ctrl-D` delete dir (requires typing `YES`), `ESC` cancel.

## Build, Test, and Development Commands
- `nix run`: Run the packaged CLI (e.g., `nix run . -- --help`).
- `nix build`: Build the binary derivation; output at `./result/bin/try`.
- `./try.rb init ~/src/tries`: Emit shell function for your shell config.
- `./try.rb cd`: Launch interactive selector; prints `cd` script to stdout.
- `./try.rb clone <git-uri> [name]`: Clone into date-prefixed directory.

## Coding Style & Naming Conventions
- Ruby, 2-space indent, standard library only; keep it single-file unless necessary.
- Prefer small, pure functions; no global state beyond `ENV` reads.
- UI tokens live in `UI::TOKEN_MAP`; add tokens with clear names.
- Directory names: `YYYY-MM-DD-name` (auto-generated); keep lowercase/kebab-case.
- Nix: keep `packages.default` minimal; avoid extra build inputs.

## Testing Guidelines
- No framework is configured; use manual flows:
  - `TRY_PATH=$(mktemp -d) ./try.rb cd` then create/select directories.
  - Validate delete confirmation and scoring by changing `mtime`/`ctime`.
  - Test clone paths: `./try.rb clone https://github.com/user/repo.git`.
- If adding logic, consider lightweight unit tests or scriptable checks; keep them optional and self-contained.

## Commit & Pull Request Guidelines
- Commits: short, imperative subject; optional scope. Examples:
  - `fix: reset token clears colors`
  - `ui: improve selected row highlight`
  - `nix: wire Home Manager module`
- PRs: include a clear description, before/after terminal screenshot or asciinema for UI changes, linked issues, and notes on behavior or config (`TRY_PATH`). Update `README.md` when flags, defaults, or UX change.

## Security & Configuration Tips
- `TRY_PATH` controls the workspace root; avoid pointing at sensitive paths.
- Destructive action (delete) requires typing `YES`; keep this safeguard.
- `clone` shells out to `git`; it writes only under `TRY_PATH`.

## Directory Scoring Algorithm
- Date prefix bonus: Names starting with `YYYY-MM-DD-` get a base `+2.0`.
- Fuzzy match (when searching):
  - Match is subsequence-based, per-char `+1.0`.
  - Word-boundary bonus `+1.0` when a match starts at index 0 or after non-word.
  - Proximity bonus `+1/√(gap+1)` for consecutive matches.
  - If not all query chars match, score is `0`.
  - Density bonus multiplies by `len(query)/(last_match_index+1)`.
  - Length penalty multiplies by `10/(len(name)+10)` to prefer shorter names.
- Time-based bonuses (always applied):
  - Creation time: `+ 2/√(days_since_created+1)`.
  - Last modified/accessed: `+ 3/√(hours_since_access+1)`.
- Sorting: When no query, items are ordered by the time/date-influenced score; with a query, only matches with positive score appear, sorted descending.
