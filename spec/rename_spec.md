# Rename Mode Specification

## Overview

Rename mode lets the user change the basename of an existing try directory without leaving the selector. The flow mirrors delete mode: a dedicated dialog appears, the list view freezes in the background, and the user completes the rename by following the inline instructions. Rename mode never applies to the `[new]` row; only real directories can be renamed.

## Workflow

### Step 1: Enter Rename Mode

- Highlight a directory entry (any row that maps to an existing path).
- Press `Ctrl-R`.
- The selector switches into rename mode:
  - A pencil-emoji header (`📝 Rename`) and the dialog frame render beneath the list.
  - The footer help text switches to `Enter: Confirm  Esc: Cancel`.
  - Normal list navigation and typing into the search field are suspended until the dialog exits.

Pressing `Ctrl-R` while the “Create new” row is selected does nothing.

### Step 2: Dialog Layout

```
──────────────────────────────────────────────
📝 Rename
Current: 2025-12-31-some-project
New name: 2025-12-31-some-proj▉
──────────────────────────────────────────────
Enter: Confirm  Esc: Cancel
```

- The top and bottom lines use the standard separator of repeated `─` characters the width of the terminal.
- The header uses `{h2}` styling with the `📝` emoji: `"{h2}📝 Rename{reset}"`.
- `Current:` shows the original basename verbatim (including any date prefix).
- `New name:` shows the editable buffer. The cursor is rendered inline via `{cursor}` (reverse video space), so the user can see insertion point even in non-tty logs.
- Error messages render directly under the input in bold (`{b}...{/b}`) without leaving the dialog.

### Step 3: Editing Behavior

- The buffer is pre-filled with the current basename.
- Editing keys reuse the search-input bindings:
  - `Ctrl-A` / `Ctrl-E` move to start/end.
  - `Ctrl-B` / `Ctrl-F` move backward/forward.
  - `Backspace` / `Ctrl-H` delete previous char.
  - `Ctrl-K` deletes to end.
  - `Ctrl-W` deletes the previous word (alphanumeric).
  - Printable ASCII (`[a-zA-Z0-9-_ .]`) insert at the cursor.
- `Ctrl-C` or `Esc` exits rename mode immediately with no changes.
- The buffer cannot grow negative; cursor clamps between `0..length`.

### Step 4: Validation & Feedback

Validation runs on every confirm attempt (`Enter`):

| Condition | Result |
|-----------|--------|
| Buffer (after trim and whitespace collapsing to `-`) is empty | Show `Name cannot be empty` |
| Buffer contains `/` | Show `Name cannot contain /` |
| Buffer matches an existing directory in the tries root | Show `Directory exists: <name>` |
| Buffer equals the original name | Rename is treated as cancel; dialog closes silently |

- Errors appear in bold beneath the input and keep the dialog open until corrected.
- Whitespace sequences collapse to `-` to preserve the `YYYY-MM-DD-name` slug style.

### Step 5: Confirm or Cancel

| Key | Action |
|-----|--------|
| Enter | Validate input; if valid and changed, emit rename script and exit |
| Esc / Ctrl-C | Cancel rename mode, no script |
| Ctrl-R (while dialog open) | Ignored (already in rename mode) |

When rename completes successfully, the selector emits a shell script (see below) and exits so the wrapper can apply the change.

## Script Output Format

Rename emits the standard try script preamble followed by three commands. Each command is on its own line, joined with `&& \` for readability.

### Structure

```sh
# if you can read this, you didn't launch try from an alias. run try --help.
cd '/tries/base/path' && \
  mv 'old-name' 'new-name' && \
  cd '/tries/base/path/new-name'
```

### Components

1. **Change to tries root**
   ```sh
   cd '/tries/base/path'
   ```
   Ensures `mv` runs relative to the managed directory.

2. **Rename command**
   ```sh
     mv 'old-name' 'new-name'
   ```
   - Uses simple basenames, not absolute paths.
   - Names are single-quoted with `'` escaped as `'"'"'`.

3. **Enter renamed directory**
   ```sh
     cd '/tries/base/path/new-name'
   ```
   Puts the caller’s shell inside the new directory once evaluation finishes.

### Safety Notes

- Because the script starts with `cd` into the tries root, the `mv` command cannot traverse outside that tree.
- The final `cd` uses the absolute path to the renamed directory to guarantee the shell lands in the correct location even if the caller started elsewhere.

## Status Messaging

- Successful rename does not print additional status text; the dialog simply closes and the script is emitted.
- Validation errors remain visible until corrected or the dialog is cancelled.
- Cancelling emits nothing (same behavior as pressing Esc in the selector).

## Footer Hint

Outside of delete/rename mode, the footer help line always lists `Ctrl-R: Rename` so users learn the shortcut without reading the docs. When rename mode is active, the footer within the dialog only shows `Enter: Confirm  Esc: Cancel`.
