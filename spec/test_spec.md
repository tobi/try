# Test Framework Specification

This document specifies the test infrastructure for `try`, including test-only command-line options and requirements for writing tests.

## Critical Requirement: Tests Must Terminate

**All tests in the `spec/tests/` directory MUST terminate deterministically.**

The TUI is an interactive blocking loop. Without explicit termination, tests will hang indefinitely waiting for user input. Every test MUST use one of these approaches:

1. **`--and-exit`** - Render once and exit immediately
2. **`--and-keys=<sequence>`** - Inject keys that reach a conclusion (Enter, Escape, Ctrl-C)

A test that launches the TUI without either option will block forever.

## Test Options

These options are for automated testing only. They are not part of the public interface and may change without notice.

| Option | Description |
|--------|-------------|
| `--and-exit` | Render TUI once and exit (exit code 1) |
| `--and-keys=<keys>` | Inject key sequence, then exit |
| `--no-expand-tokens` | Output raw tokens (`{b}`, `{dim}`) instead of ANSI codes |
| `--no-colors` | Disable all ANSI color/style codes |

## `--and-exit`

Renders the TUI exactly once without waiting for input, then exits with code 1 (cancelled).

**Use cases:**
- Testing initial render output
- Verifying display formatting
- Checking that directories appear in list

**Example:**
```bash
# Capture TUI render to check display
output=$(./try --path=/tmp/test --and-exit exec 2>&1)

# Verify score format is shown
echo "$output" | grep -qE "[0-9]+\.[0-9]"
```

**Behavior:**
- Exit code is always 1 (treated as cancelled)
- stdout is empty (no script emitted)
- stderr contains the rendered TUI frame
- No terminal mode changes (no raw mode)

## `--and-keys=<sequence>`

Injects a sequence of keystrokes as if typed by the user. The TUI processes these keys and exits when the sequence is exhausted or a terminating action occurs.

**The sequence MUST end in a terminating key** (Enter, Escape, or Ctrl-C) to produce a deterministic result.

### Key Encoding

Keys can be specified in two formats. Both can be mixed in the same sequence.

#### Symbolic Format (Recommended)

Comma-separated symbolic key names. More readable and portable:

| Key | Symbol | Notes |
|-----|--------|-------|
| Enter | `ENTER` or `RETURN` | |
| Escape | `ESC` or `ESCAPE` | |
| Up Arrow | `UP` | |
| Down Arrow | `DOWN` | |
| Left Arrow | `LEFT` | |
| Right Arrow | `RIGHT` | |
| Backspace | `BACKSPACE` or `BS` | |
| Tab | `TAB` | |
| Space | `SPACE` | |
| Ctrl-X | `CTRL-X` | Where X is A-Z |

**Examples:**
```bash
# Navigate down, then up, then select
--and-keys='CTRL-J,CTRL-K,ENTER'

# Type text then select
--and-keys='beta,ENTER'

# Cancel with escape
--and-keys='ESC'
```

**Note:** Printable text between commas is typed as literal characters. `BETA,ENTER` types "BETA" then Enter. Use lowercase for literal text to avoid confusion with symbolic names.

#### Raw Escape Sequence Format (Legacy)

Special keys can also be specified using raw escape sequences:

| Key | Encoding | Bash Syntax |
|-----|----------|-------------|
| Enter | `\r` | `$'\r'` |
| Escape | `\x1b` | `$'\x1b'` |
| Ctrl-A through Ctrl-Z | `\x01` - `\x1a` | `$'\x01'` etc. |
| Backspace | `\x7f` | `$'\x7f'` |
| Up Arrow | `\x1b[A` | `$'\x1b[A'` |
| Down Arrow | `\x1b[B` | `$'\x1b[B'` |
| Left Arrow | `\x1b[D` | `$'\x1b[D'` |
| Right Arrow | `\x1b[C` | `$'\x1b[C'` |

Printable characters are passed literally.

### Examples

```bash
# Type "beta" then press Enter to select matching entry
output=$(./try --path=/tmp/test --and-keys="beta"$'\r' exec 2>/dev/null)

# Press Escape to cancel
output=$(./try --path=/tmp/test --and-keys=$'\x1b' exec 2>/dev/null)

# Navigate down twice, then up once, then select
output=$(./try --path=/tmp/test --and-keys=$'\x1b[B\x1b[B\x1b[A\r' exec 2>/dev/null)

# Type and delete with backspace
output=$(./try --path=/tmp/test --and-keys="xyz"$'\x7f\x7f\x7f'"abc"$'\r' exec 2>/dev/null)

# Use vim-style navigation (Ctrl-J down, Ctrl-K up)
output=$(./try --path=/tmp/test --and-keys=$'\x0a\x0b\r' exec 2>/dev/null)
```

### Behavior by Terminating Key

| Terminating Key | Exit Code | stdout | Result |
|-----------------|-----------|--------|--------|
| Enter (on entry) | 0 | cd script | Selection made |
| Enter (on [new]) | 0 | mkdir script | New directory |
| Escape | 1 | "Cancelled." | Cancelled |
| Ctrl-C | 1 | "Cancelled." | Cancelled |
| End of sequence | 1 | "Cancelled." | Sequence exhausted |

## `--no-expand-tokens`

Outputs formatting tokens as literal text instead of expanding them to ANSI codes.

**Use case:** Testing that tokens are placed correctly in output.

```bash
./try --no-expand-tokens --and-exit exec 2>&1 | grep "{b}"
# Should find {b} tokens in output
```

## `--no-colors`

Disables all ANSI styling codes (colors, bold, dim, reset). Cursor control sequences still function.

**Use case:** Testing output in colorless environments.

```bash
output_colors=$(./try --and-exit exec 2>&1)
output_plain=$(./try --no-colors --and-exit exec 2>&1)

# output_colors should have ANSI codes, output_plain should not
```

## Combining Options

Options can be combined:

```bash
# Render with filter, capture output
./try --path=/tmp/test --and-exit --and-keys="beta" exec 2>&1

# Both inject keys AND render once (keys processed, then render, then exit)
./try --and-exit --and-keys="query" exec
```

When both `--and-exit` and `--and-keys` are used:
1. Keys are injected and processed
2. One frame is rendered
3. Exit with code 1

## Writing Tests

### Test File Structure

Test files in `spec/tests/` are sourced by the runner. They have access to:

- `try_run` - Function that runs try with proper command expansion
- `pass` - Mark test as passed
- `fail "description" "expected" "got" "spec_ref"` - Mark test as failed
- `section "name"` - Start a new test section
- `$TEST_TRIES` - Path to test tries directory with sample entries

### Test Patterns

**Pattern 1: Check TUI renders correctly**
```bash
output=$(try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
if echo "$output" | grep -q "expected text"; then
    pass
else
    fail "description" "expected text" "$output" "spec.md#section"
fi
```

**Pattern 2: Check selection produces correct script**
```bash
output=$(try_run --path="$TEST_TRIES" --and-keys="query"$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "description" "cd command" "$output" "spec.md#section"
fi
```

**Pattern 3: Check exit code**
```bash
try_run --path="$TEST_TRIES" --and-keys=$'\x1b' exec >/dev/null 2>&1
if [ $? -eq 1 ]; then
    pass
else
    fail "ESC should exit with code 1" "exit 1" "exit $?" "spec.md#section"
fi
```

### Common Mistakes

**WRONG: No terminating key**
```bash
# This will HANG - no Enter or Escape!
output=$(try_run --path="$TEST_TRIES" --and-keys="beta" exec)
```

**RIGHT: Include terminating key**
```bash
# Ends with Enter
output=$(try_run --path="$TEST_TRIES" --and-keys="beta"$'\r' exec)

# Or use --and-exit for render-only tests
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="beta" exec 2>&1)
```

**WRONG: Expecting stdout from --and-exit**
```bash
# --and-exit always exits with code 1 (cancelled), stdout is empty
output=$(try_run --and-exit exec)  # output will be empty!
```

**RIGHT: Capture stderr for rendered output**
```bash
output=$(try_run --and-exit exec 2>&1)  # Redirect stderr to capture TUI
```

## Environment Variables

Implementations must support these environment variables for testing:

| Variable | Description |
|----------|-------------|
| `TRY_WIDTH` | Override terminal width (columns) |
| `TRY_HEIGHT` | Override terminal height (rows) |

These allow testing layout and truncation behavior without needing an actual terminal of that size:

```bash
# Test with 400-character wide terminal
TRY_WIDTH=400 ./try --path="$TEST_TRIES" --and-exit exec 2>&1

# Test narrow terminal
TRY_WIDTH=40 TRY_HEIGHT=10 ./try --and-exit exec 2>&1
```

## Test Environment

The runner creates a test environment with sample directories:

```
$TEST_TRIES/
├── 2025-11-01-alpha      (oldest)
├── 2025-11-15-beta
├── 2025-11-20-gamma
├── 2025-11-25-project-with-long-name
└── no-date-prefix        (most recent by mtime)
```

These directories have different mtimes to test sorting by recency.
