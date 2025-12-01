# Performance Specification

## Overview

The `try` tool should feel instant even with hundreds of directories. This document specifies performance requirements and design patterns.

## Directory Scanning

### Single Pass Loading

- Directory list is loaded **once** at startup
- Subsequent operations (filtering, sorting) work on the cached list
- List is only reloaded after mutations (delete, create)

### Efficient Metadata Retrieval

- Use single syscall per directory to get modification time
- Prefer `stat()` over `readdir()` + `stat()` when possible
- Cache modification times in memory

### Platform-Specific Optimizations

On systems that support it:
- Use `getdents64` for batch directory reading (Linux)
- Use `getattrlistbulk` for bulk metadata (macOS)

## Fuzzy Matching

### Forward-Only Algorithm

The fuzzy matcher must be **O(n×m)** where:
- n = length of query
- m = length of directory name

**Requirements:**
- Single forward pass through both strings
- No backtracking or recursion
- Early termination on mismatch

### Scoring Algorithm

```
For each character in query:
  Scan forward in target for match
  If found:
    score += base_points
    score += proximity_bonus / sqrt(gap + 1)
  Else:
    return 0 (no match)
```

The proximity bonus rewards consecutive matches without requiring backtracking.

## Rendering

### Double Buffering

- Build complete frame in memory buffer
- Flush entire buffer at once
- Avoids visible screen tearing

### Incremental Updates

When only the selection changes:
- Clear and redraw only affected lines (old selection, new selection)
- Avoid full screen redraws when possible

### Token Expansion

- Token map should be a simple hash lookup: **O(1)**
- Token expansion is single-pass string substitution
- No regex or complex parsing

## Memory Usage

### String Handling

- Avoid unnecessary string copies
- Use string slices/views where language supports them
- Pre-allocate buffers for rendering

### Data Structures

- Directory list: simple array (cache-friendly iteration)
- Token map: hash table with pre-computed ANSI sequences
- No complex tree structures for small datasets

## Benchmarks

Target performance (rough guidelines):

| Operation | Target |
|-----------|--------|
| Startup + first render | < 50ms |
| Keystroke to screen update | < 16ms (60fps) |
| Fuzzy filter 1000 entries | < 10ms |
| Directory scan 1000 entries | < 100ms |

## Anti-Patterns to Avoid

1. **Multiple directory scans** - Never re-read filesystem during filtering
2. **Backtracking matchers** - No recursive fuzzy matching
3. **Regex for tokens** - Use simple string replacement
4. **Per-character rendering** - Always batch screen updates
5. **Sorting during filter** - Sort once, filter in-place
6. **String concatenation in loops** - Use builders/buffers
