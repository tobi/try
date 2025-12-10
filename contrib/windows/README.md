# Windows Support for 'try'

This directory contains alternative implementations of `try` for Windows users who may encounter compatibility issues with the Ruby version (especially regarding SIGWINCH, IO.select, or encoding issues).

## Installation

### For Git Bash / MSYS2 / Cygwin (`try.sh`)

1. Copy `try.sh` to a safe location (e.g., `~/.local/try.sh`).
2. Add the following line to your `~/.bashrc`:
   ```bash
   source ~/.local/try.sh
   ```

### For PowerShell (`try.ps1`)

**Important Note:** In PowerShell, `try` is a reserved keyword. Therefore, you must invoke the function using the call operator `&`, like this: `& try <command>`.

1. Copy `try.ps1` to a safe location (e.g., `~/Documents/WindowsPowerShell/try.ps1`).
2. Add the following line to your PowerShell profile (check path with `$PROFILE`):
   ```powershell
   . "$HOME\Documents\WindowsPowerShell\try.ps1"
   ```

## Usage

### Bash (`try.sh`)
- `try <name>`: Create and enter a new dated experiment directory.
- `try <git-url>`: Clone and enter a repo.
- `try clone <url> [name]`: Clone with custom name.
- `try worktree <name>`: Create a worktree from current repo.
- `try`: List recent experiments.

### PowerShell (`try.ps1`)
**Must use `&` prefix:**
- `& try <name>`
- `& try <git-url>`
- `& try clone <url> [name]`
- `& try worktree <name>`
- `& try`