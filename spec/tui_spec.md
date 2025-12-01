# TUI (Terminal User Interface) Specification

## Overview

The TUI provides an interactive directory selector featuring fuzzy search, keyboard navigation, and responsive layout that adapts to terminal window size changes.

## Terminal Size

### Detection Priority

1. Query terminal for current dimensions (rows × columns)
2. Fall back to environment variables if available
3. Default to 80 columns × 24 rows if detection fails

### Dynamic Layout

Layout dimensions are recalculated on every render:

- **Header**: 3 lines (title + separator + search input)
- **Footer**: 2 lines (separator + help text)
- **List area**: Remaining vertical space

## Resize Handling

When terminal is resized:

1. Interrupt any blocking input read
2. Query new terminal dimensions
3. Re-render UI with updated layout
4. Preserve selection index and scroll position

## Display Layout

### Two-Layer Entry Display

Each directory entry has two display components:

**Primary Layer (left-aligned):**
- Selection indicator (`→` for selected, space for others)
- Directory icon (📁)
- Directory name with fuzzy match highlighting
- Truncated with ellipsis (`…`) if too long

**Secondary Layer (right-aligned):**
- Relative timestamp ("just now", "2h ago", "3d ago")
- Fuzzy match score (e.g., "3.2")
- Only shown when sufficient space exists

### Layout Rules

```
[→] [📁] [directory-name.............] [timestamp, score]
     ^                                  ^
     left-aligned                       right-aligned
```

- Metadata is anchored to terminal right edge
- Path expands to fill available space
- If path would overlap metadata, metadata is hidden
- If path is truncated, metadata is hidden

## Path Truncation

When paths exceed available space:

1. Calculate maximum visible characters
2. Preserve formatting tokens (don't split `{b}...{/b}`)
3. Truncate at character boundary
4. Append ellipsis character (`…`)

Example:
```
Full:      "2025-11-29-very-long-project-name"
Truncated: "2025-11-29-very-long-pro…"
```

## Metadata Display

### Relative Timestamps

| Age | Display |
|-----|---------|
| < 1 minute | "just now" |
| < 1 hour | "Xm ago" |
| < 24 hours | "Xh ago" |
| < 7 days | "Xd ago" |
| ≥ 7 days | "Xw ago" |

### Score Format

- Single decimal precision: "3.2", "10.5"
- Displayed after timestamp, separated by comma

### Metadata Positioning

Metadata is always anchored to the right edge of the terminal. The display algorithm:

1. Calculate positions:
   - `path_end_pos` = prefix (5 chars) + directory name length
   - `meta_end_pos` = terminal width - 1
   - `meta_start_pos` = meta_end_pos - metadata length
   - `available_space` = meta_start_pos - path_end_pos

2. Display rules based on `available_space`:
   - **> 2 chars**: Full metadata with padding between name and metadata
   - **-metadata_len+3 to 2**: Truncate metadata from left (show rightmost portion)
   - **< -metadata_len+3**: Hide metadata entirely

### Line Layout Examples

All examples assume 80-column terminal width.

**Example 1: Short name, full metadata**
```
→ 📁 2025-11-29-project                                      just now, 5.2
│    │                                                       │            │
│    └─ path_end_pos = 24                                    │            └─ col 79 (end)
│                                                            └─ meta_start_pos = 66
└─ prefix (5 chars)

available_space = 66 - 24 = 42 chars (> 2, show full metadata)
```

**Example 2: Long name, partial metadata**
```
→ 📁 2025-11-30-this-is-a-very-long-directory-name-for-testing    ow, 3.0
│    │                                                        │   │      │
│    └─ path_end_pos = 55                                     │   │      └─ col 79
│                                                             │   └─ truncated from left
└─ prefix (5 chars)                                           └─ meta_start_pos = 72

available_space = 72 - 55 = 17 chars
Full metadata = "just now, 3.0" (13 chars)
Since 17 > 2, show full. But if name were longer...
```

**Example 3: Very long name, metadata truncated from left**
```
→ 📁 2025-11-30-extremely-long-directory-name-that-takes-up-space  w, 3.0
│    │                                                            ││     │
│    └─ path_end_pos = 66                                         │└─────┴─ rightmost portion
└─ prefix (5 chars)                                               └─ only 13 chars available

Full metadata = "just now, 3.0" (13 chars)
available_space = 72 - 66 = 6 chars
chars_to_skip = 1 - 6 = negative, but name extends into metadata zone
Result: truncate "just no" from left, show "w, 3.0"
```

**Example 4: Name too long, metadata hidden**
```
→ 📁 2025-11-30-this-is-an-incredibly-long-name-that-fills-the-entire…
│    │                                                                │
│    └─ path_end_pos extends past where metadata would start         └─ truncation ellipsis

available_space < -metadata_len + 3, metadata completely hidden
```

### Truncation Algorithm

When the directory name is too long for the available width:

1. Calculate max visible characters (terminal width - prefix - 1)
2. Walk through rendered string character by character
3. Skip formatting tokens (`{b}`, `{/b}`, etc.) - don't count them
4. Count visible characters until limit reached
5. Append ellipsis (`…`)

```
Input:  "2025-11-29-{b}very{/b}-long-project-name" (29 visible chars)
Max:    20 chars
Output: "2025-11-29-{b}very{/b}-lon…" (19 visible + ellipsis)
```

Tokens are preserved intact - never split a `{b}...{/b}` pair.

## Visual Layout

### Header (lines 1-3)

```
┌─────────────────────────────────────────────────┐
│ 📁 Try Selector                                  │
├─────────────────────────────────────────────────┤
│ > user query here                                │
└─────────────────────────────────────────────────┘
```

### List Section (dynamic height)

```
→ 📁 2025-11-29-project                  just now, 5.2
  📁 2025-11-28-another-project             2h ago, 3.1
  📁 2025-11-27-old-thing                   3d ago, 2.4
```

### Footer (bottom 2 lines)

```
┌──────────────────────────────────────────────────────────────┐
│ ↑↓: Navigate  Enter: Select  Ctrl-D: Delete  Esc: Cancel      │
└──────────────────────────────────────────────────────────────┘
```

## Keyboard Input

### Navigation
| Key | Action |
|-----|--------|
| ↑ / Ctrl-P | Move selection up |
| ↓ / Ctrl-N | Move selection down |
| Enter | Select current entry |
| Esc / Ctrl-C | Cancel selection |
| Ctrl-D | Delete selected directory |

### Line Editing (in search input)
| Key | Action |
|-----|--------|
| Ctrl-A | Move cursor to beginning of line |
| Ctrl-E | Move cursor to end of line |
| Ctrl-B | Move cursor backward one character |
| Ctrl-F | Move cursor forward one character |
| Backspace / Ctrl-H | Delete character before cursor |
| Ctrl-K | Delete from cursor to end of line |
| Ctrl-W | Delete word before cursor (alphanumeric boundaries) |
| Any printable | Append to query, re-filter |

## Scrolling

- List scrolls to keep selection visible
- Selection clamped to valid range (0 to entry_count - 1)
- Scroll offset adjusts when selection moves outside visible area

## Actions

Selection can result in three action types:

| Action | Trigger | Result |
|--------|---------|--------|
| CD | Select existing directory | Navigate to directory |
| MKDIR | Select "[new]" entry | Create and navigate to new directory |
| DELETE | Press Ctrl-D on entry | Show delete confirmation dialog |
| CANCEL | Press Esc | Exit without action |

## New Directory Creation

When query doesn't match any existing directory:

- Show "[new] query-text" as first option
- Selecting creates `YYYY-MM-DD-query-text` directory
- New directory is created in tries base path

## Directory Deletion

Pressing Ctrl-D on a selected directory triggers the delete flow:

### Confirmation Dialog

```
Delete Directory

Are you sure you want to delete: directory-name
  in /full/path/to/directory
  files: X files
  size: Y MB

[YES] [NO]
```

### Confirmation Input

| Key | Action |
|-----|--------|
| Y / y | Confirm deletion |
| N / n / Esc | Cancel deletion |
| Arrow keys | Navigate between YES/NO |
| Enter | Select highlighted option |

### Delete Behavior

- Directory is removed recursively (`rm -rf`)
- On success: Shows "Deleted: directory-name" status
- On cancel: Shows "Delete cancelled" status
- On error: Shows "Error: message" status
- After deletion, returns to main selector with refreshed list
- Cannot delete the "[new]" entry

### Delete Mode

Delete is a multi-step batch operation:

**Step 1: Mark items**
- Press `Ctrl-D` on any entry to mark it for deletion
- Marked entries display with `{strike}` (dark red background)
- Footer shows: `DELETE MODE | X marked | Ctrl-D: Toggle | Enter: Confirm | Esc: Cancel`
- Can continue navigating and marking multiple items

**Step 2: Confirm or cancel**
- Press `Enter` to show confirmation dialog for all marked items
- Press `Esc` to exit delete mode (clears all marks)

**Step 3: Type YES**
- Confirmation dialog lists all marked directories
- Must type `YES` to proceed with deletion
- Any other input cancels

### Delete Script Output

In exec mode, delete outputs a shell script (like all other actions). The script is evaluated by the shell wrapper, not executed directly by try.

**Script structure (per item):**
```sh
/usr/bin/env sh -c '
  target=$(realpath "/path/to/dir");
  base=$(realpath "/tries/base");
  case "$target" in "$base/"*) ;; *) exit 1;; esac;
  case "$(pwd)/" in "$target/"*) cd "$base";; esac;
  rm -rf "$target"
'
```

Multiple marked items emit multiple delete commands chained with `&&`.

### Delete Safety

**Path validation (CRITICAL):**
- Resolve target to realpath before deletion
- Verify realpath starts with tries base directory + "/"
- Reject if target is outside tries directory

**PWD handling:**
- Check if `$(pwd)/` starts with `$target/`
- If inside, `cd` to tries base first
- Then `rm -rf` the resolved path

This order prevents:
1. Deleting directories outside the tries folder (symlink attacks)
2. Leaving the shell in an invalid state (deleted PWD)
