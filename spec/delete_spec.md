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
cd '/path/to/tries' && \
  test -d 'dir-name-1' ]] && rm -rf 'dir-name-1' && \
  test -d 'dir-name-2' ]] && rm -rf 'dir-name-2' && \
  ( cd '/original/pwd' 2>/dev/null || cd "$HOME" )
```

Each command is on its own line, chained with `&& \` for readability, with 2-space indent on continuation lines.

### Script Components

1. **Change to tries base directory**
   ```sh
   cd '/path/to/tries' && \
   ```
   All deletions happen relative to the tries base path.

2. **Per-item delete commands**
   ```sh
     test -d 'name' ]] && rm -rf 'name' && \
   ```
   - Check directory exists before deletion
   - Use basename only (not full path)
   - Each on its own line with continuation

3. **PWD restoration**
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
cd '/home/user/tries' && \
  test -d '2025-11-29-old-project' ]] && rm -rf '2025-11-29-old-project' && \
  test -d '2025-11-28-abandoned' ]] && rm -rf '2025-11-28-abandoned' && \
  ( cd '/home/user/code' 2>/dev/null || cd "$HOME" )
```

## Safety Guarantees

### Path Containment

- Deletions only happen within the tries base directory
- The `cd` to tries base ensures relative paths stay contained
- No symlink traversal outside tries directory

### PWD Handling

- If shell's PWD is inside a directory being deleted:
  - Script changes to tries base first
  - Then performs deletion
  - Attempts to restore PWD (which will fail gracefully)
  - Falls back to $HOME

### Existence Check

- `test -d 'name' ]]` prevents errors on already-deleted directories
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
