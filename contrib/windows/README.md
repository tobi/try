# Windows Support for `try`

Alternative shell implementations for Windows users who encounter Ruby compatibility issues.

## Installation

### Git Bash / MSYS2 / Cygwin

**Option A: Download from GitHub**
```bash
mkdir -p ~/.local
curl -o ~/.local/try.sh https://raw.githubusercontent.com/tobi/try/main/contrib/windows/try.sh
```

**Option B: Copy from local clone**
```bash
mkdir -p ~/.local
cp /path/to/try/contrib/windows/try.sh ~/.local/try.sh
```

**Then add to profile:**
```bash
echo 'source ~/.local/try.sh' >> ~/.bashrc
source ~/.bashrc
```

### PowerShell

> **Note:** `try` is a reserved keyword in PowerShell. Use `& try` to invoke.

**Option A: Download from GitHub**
```powershell
New-Item -ItemType Directory -Force -Path "$HOME\Documents\WindowsPowerShell" | Out-Null
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tobi/try/main/contrib/windows/try.ps1" `
  -OutFile "$HOME\Documents\WindowsPowerShell\try.ps1"
```

**Option B: Copy from local clone**
```powershell
New-Item -ItemType Directory -Force -Path "$HOME\Documents\WindowsPowerShell" | Out-Null
Copy-Item "C:\path\to\try\contrib\windows\try.ps1" "$HOME\Documents\WindowsPowerShell\try.ps1"
```

**Then add to profile:**
```powershell
if (!(Test-Path $PROFILE)) { New-Item -Path $PROFILE -Force | Out-Null }
Add-Content $PROFILE '. "$HOME\Documents\WindowsPowerShell\try.ps1"'
. $PROFILE
```

**Profile paths by version:**
- PowerShell 5.x: `$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`
- PowerShell 7.x: `$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`

The script is stored in `WindowsPowerShell` folder but loaded from your active `$PROFILE`.

## Usage

| Command | Description |
|---------|-------------|
| `try` | List recent experiment directories |
| `try <name>` | Create dated directory and enter it |
| `try <git-url>` | Clone repo into dated directory |
| `try clone <url> [name]` | Clone with optional custom name |
| `try . <name>` | Create worktree from current repo |
| `try ./path [name]` | Create worktree from specified repo |
| `try worktree <name>` | Create worktree (explicit form) |
| `try --help` | Show help |

### PowerShell Examples

```powershell
& try my-experiment
& try https://github.com/user/repo.git
& try . feature-branch
& try .\other-repo experiment
```

### Bash Examples

```bash
try my-experiment
try https://github.com/user/repo.git
try . feature-branch
try ./other-repo experiment
```

## Storage

All directories are created in `~/src/tries` with date prefix (e.g., `2025-12-11-my-experiment`).
