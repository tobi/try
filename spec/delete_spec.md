# Delete Mode Specification

## Overview

Delete mode allows batch deletion of directories with visual feedback and confirmation. This is a multi-step operation designed to prevent accidental deletions.

## Workflow

### Step 1: Mark Items

- Press `Ctrl-D` on any directory entry to mark it for deletion
- Marked entries display with `{strike}` token (dark red background)
- Selection indicator changes to show marked state
- Can continue navigating and marking multiple items
- Pressing `Ctrl-D` on an already-marked item unmarks it (toggle)
- Cannot mark the `[new]` entry

### Step 2: Delete Mode UI

When one or more items are marked:

- Footer changes to show delete mode status
- Format: `DELETE MODE | X marked | Ctrl-D: Toggle | Enter: Confirm | Esc: Cancel`
- Marked items remain visible with strikethrough styling

### Step 3: Confirm or Cancel

| Key | Action |
|-----|--------|
| Enter | Show confirmation dialog |
| Esc | Exit delete mode, clear all marks |
| Ctrl-D | Toggle mark on current item |
| Arrow keys | Continue navigating |

### Step 4: Type YES to Delete

Confirmation dialog shows:

```
Delete X directories?

  - directory-1
  - directory-2
  - ...

Type YES to confirm:
```

- Must type exactly `YES` (case-sensitive) to proceed
- Any other input cancels the operation
- After typing, press Enter to submit

## Script Output Format

In exec mode, delete outputs a shell script that is evaluated by the shell wrapper.

### Script Structure

```sh
[[ -d '/full/path/to/dir-name-1' ]] && rm -rf '/full/path/to/dir-name-1' && \
  [[ -d '/full/path/to/dir-name-2' ]] && rm -rf '/full/path/to/dir-name-2' && \
  ( cd '/original/pwd' 2>/dev/null || cd "$HOME" )
```

Each command is on its own line, chained with `&& \` for readability, with 2-space indent on continuation lines.

### Script Components

1. **Per-item delete commands**
   ```sh
   [[ -d '/full/path/to/name' ]] && rm -rf '/full/path/to/name' && \
   ```
   - Check directory exists before deletion
   - Use absolute paths (supports both tries and GitHub sources)
   - Each on its own line with continuation
   - Paths are validated before script generation to ensure they're within allowed roots

2. **PWD restoration**
   ```sh
   ( cd '/original/pwd' 2>/dev/null || cd "$HOME" )
   ```
   - Attempt to return to original working directory
   - Fall back to $HOME if original no longer exists
   - Subshell prevents cd failure from stopping script

### Quote Escaping

All paths use single quotes with proper escaping:
- Single quotes in names: `'` becomes `'"'"'`
- Example: `it's-a-test` becomes `'it'"'"'s-a-test'`

### Example Output

For deleting two directories from `/home/user/tries`:

```sh
# if you can read this, you didn't launch try from an alias. run try --help.
[[ -d '/home/user/tries/2025-11-29-old-project' ]] && rm -rf '/home/user/tries/2025-11-29-old-project' && \
  [[ -d '/home/user/tries/2025-11-28-abandoned' ]] && rm -rf '/home/user/tries/2025-11-28-abandoned' && \
  ( cd '/home/user/code' 2>/dev/null || cd "$HOME" )
```

For deleting a GitHub repository (when `GH_PATH` is set):

```sh
# if you can read this, you didn't launch try from an alias. run try --help.
[[ -d '/home/user/github/owner/repo' ]] && rm -rf '/home/user/github/owner/repo' && \
  ( cd '/home/user/code' 2>/dev/null || cd "$HOME" )
```

## Safety Guarantees

### Path Containment

- Deletions only happen within allowed root directories:
  - Items from tries source must be within `TRY_PATH`
  - Items from GitHub source must be within `GH_PATH` (when enabled)
- Path validation occurs before script generation using `File.realpath` to resolve symlinks
- Each item is validated against its appropriate root based on its source
- No symlink traversal outside allowed directories

### PWD Handling

- If shell's PWD is inside a directory being deleted:
  - Script performs deletion using absolute paths
  - Attempts to restore PWD (which will fail gracefully if PWD was deleted)
  - Falls back to $HOME

### Existence Check

- `[[ -d 'name' ]]` prevents errors on already-deleted directories
- Safe for concurrent operations

## Visual Tokens

| Token | Effect | Usage |
|-------|--------|-------|
| `{strike}` | Dark red background (#5f0000) | Marked for deletion |
| `{/strike}` | Reset background | End deletion marking |

## Keyboard Reference

| Context | Key | Action |
|---------|-----|--------|
| Normal mode | Ctrl-D | Mark item, enter delete mode |
| Delete mode | Ctrl-D | Toggle mark on current item |
| Delete mode | Enter | Show confirmation dialog |
| Delete mode | Esc | Exit delete mode, clear marks |
| Confirmation | YES + Enter | Execute deletion |
| Confirmation | Other + Enter | Cancel deletion |
