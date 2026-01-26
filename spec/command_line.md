# Command Line Specification

## Synopsis

```
try [options] [command] [args...]
try exec [options] [command] [args...]
```

## Description

`try` is an ephemeral workspace manager that helps organize project directories with date-prefixed naming. It provides an interactive selector for navigating between workspaces and commands for creating new ones.

## Global Options

| Option | Description |
|--------|-------------|
| `--help`, `-h` | Show help text |
| `--version`, `-v` | Show version number |
| `--path <dir>` | Override tries directory (default: `~/src/tries`) |
| `--no-colors` | Disable ANSI color codes in output |

## Commands

### cd (default)

Interactive directory selector with fuzzy search.

```
try cd [query]
try exec cd [query]
try exec [query]        # equivalent to: try exec cd [query]
```

**Arguments:**
- `query` (optional): Initial filter text for fuzzy search

**Behavior:**
- Opens interactive TUI for directory selection
- Filters directories by query if provided
- Returns shell script to cd into selected directory

**Actions:**
- Select existing directory → touch and cd
- Select "[new]" entry → mkdir and cd (creates `YYYY-MM-DD-query`)
- Press Esc → cancel (exit 1)

### clone

Clone a git repository into a dated directory.

```
try clone <url> [name]
try exec clone <url> [name]
try <url> [name]            # URL shorthand (same as clone)
```

**Arguments:**
- `url` (required): Git repository URL
- `name` (optional): Custom name suffix (default: extracted from URL)

**Behavior:**
- Creates directory named `YYYY-MM-DD-<user>-<repo>` (extracted from URL)
- Clones repository into that directory
- Returns shell script to cd into cloned directory

**Examples:**
```
try clone https://github.com/tobi/try.git
# Creates: 2025-11-30-tobi-try

try clone https://github.com/user/repo myproject
# Creates: 2025-11-30-myproject (custom name overrides)

try https://github.com/tobi/try.git
# URL shorthand (same as first example)

try clone git@github.com:tobi/try.git
# SSH URL also works: 2025-11-30-tobi-try
```

### worktree

Create a git worktree in a dated directory.

```
try worktree <name>
try exec worktree <name>
try . <name>              # Shorthand (requires name)
```

**Arguments:**
- `name` (required): Branch or worktree name

**Behavior:**
- Must be run from within a git repository
- Creates worktree in `YYYY-MM-DD-<name>`
- Returns shell script to cd into worktree
- `try .` without a name is NOT supported (too easy to invoke accidentally)

### do

Move a try directory to a permanent work location.

```
try do
try exec do
```

**Arguments:**
- None. Operates on the current working directory.

**Behavior:**
- Must be run from inside a try directory (or subdirectory of one)
- Extracts the immediate child directory of the tries path
- Strips date prefix (`YYYY-MM-DD-`) to propose a clean name
- Prompts for name confirmation (enter to accept, or type a new name)
- Checks destination doesn't already exist
- Leaves a symlink at the original location pointing to the new path
- Graduated entries appear with ⭐ instead of 📁 in the TUI
- Returns shell script to move directory and ensure git is initialized
- Errors if the entry is already a symlink (already graduated)

**Examples:**
```
$ cd ~/src/tries/2025-08-17-redis-pool
$ try do
Name [redis-pool]:
# Moves to ~/Work/redis-pool, ensures git init

$ try do
Name [redis-pool]: my-pool
# Moves to ~/Work/my-pool instead
```

**Error cases:**
- Not inside tries directory → error + exit 1
- At tries root (not in a specific try) → "cd into a try directory first"
- Destination already exists → error + exit 1

### init

Output shell function definition for shell integration.

```
try init [path]
```

**Arguments:**
- `path` (optional): Override default tries directory

**Behavior:**
- Detects current shell (bash/zsh or fish)
- Outputs appropriate function definition to stdout
- Function wraps `try exec` and evals output

**Usage:**
```bash
# bash/zsh
eval "$(try init ~/src/tries)"

# fish
eval (try init ~/src/tries | string collect)
```

## Execution Modes

### Direct Mode

When `try` is invoked without `exec`:

- Commands execute immediately
- Cannot change parent shell's directory
- Prints cd hint for user to copy/paste

```
$ try clone https://github.com/user/repo
Cloning into '/home/user/src/tries/2025-11-30-repo'...
cd '/home/user/src/tries/2025-11-30-repo'
```

### Exec Mode

When `try exec` is used (typically via shell alias):

- Returns shell script to stdout
- Exit code 0: alias evals output (performs cd)
- Exit code 1: alias prints output (error/cancel message)

```
$ try exec clone https://github.com/user/repo
# if you can read this, you didn't launch try from an alias. run try --help.
git clone 'https://github.com/user/repo' '/home/user/src/tries/2025-11-30-repo' && \
  cd '/home/user/src/tries/2025-11-30-repo'
```

## Script Output Format

All exec mode commands output shell scripts with each command on its own line:

```bash
# if you can read this, you didn't launch try from an alias. run try --help.
<command> && \
  cd '<path>'
```

Commands are chained with `&& \` for readability, with 2-space indent on continuation lines. The warning comment helps users who accidentally run `try exec` directly.

## Exit Codes

| Code | Meaning | Alias Action |
|------|---------|--------------|
| 0 | Success | Eval output |
| 1 | Error or cancelled | Print output |

## Environment

| Variable | Description |
|----------|-------------|
| `HOME` | Used to resolve default tries path (`$HOME/src/tries`) |
| `SHELL` | Used by `init` to detect shell type |
| `NO_COLOR` | If set, disables colors (equivalent to `--no-colors`) |
| `TRY_DO_PATH` | Override destination for `try do` (default: `~/Work`) |

## Defaults

- **Tries directory**: `~/src/tries`
- **Date format**: `YYYY-MM-DD`
- **Directory naming**: `YYYY-MM-DD-<name>`

## Color Output

By default, `try` uses ANSI color codes for syntax highlighting and visual formatting in the TUI and help output.

### Disabling Colors

Colors can be disabled in two ways:

1. **Command-line flag**: `--no-colors`
2. **Environment variable**: `NO_COLOR=1` (any non-empty value)

The `NO_COLOR` environment variable follows the [no-color.org](https://no-color.org/) standard, which is supported by many command-line tools.

**Examples:**
```bash
# Using the flag
try --no-colors --help

# Using the environment variable
NO_COLOR=1 try --help

# Set globally in shell config
export NO_COLOR=1
```

**Behavior:**
- Styling codes (bold, colors, dim, reset) are suppressed
- Cursor control sequences for the TUI still function normally
- Useful for piping output, accessibility, or terminals without color support

---

## Testing

For test framework documentation including `--and-exit`, `--and-keys`, and test writing guidelines, see [test_spec.md](test_spec.md).

---

## Examples

```bash
# Set up shell integration
eval "$(try init)"

# Interactive selector
try

# Selector with initial filter
try project

# Clone a repository
try clone https://github.com/user/repo

# Clone with custom name
try clone https://github.com/user/repo my-fork

# Create git worktree (from within a repo)
try worktree feature-branch

# Graduate a try to a permanent project
cd ~/src/tries/2025-08-17-redis-pool
try do

# Show version
try --version

# Show help
try --help
```
