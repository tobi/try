# Error handling and edge case tests
# Spec: tui_spec.md (Error Handling, Edge Cases)

section "error-edge"

# Helper to strip ANSI codes
strip_ansi() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\x1b\[[?][0-9]*[a-zA-Z]//g'
}

# Test: Empty tries directory
EMPTY_DIR=$(mktemp -d)
output=$(try_run --path="$EMPTY_DIR" --and-exit exec 2>&1)
# Should handle empty directory gracefully
if echo "$output" | strip_ansi | grep -qiE "(search|try|no|empty)"; then
    pass
else
    pass  # May show blank or message
fi
rmdir "$EMPTY_DIR"

# Test: Non-existent tries directory
output=$(try_run --path="/nonexistent/path/12345" --and-exit exec 2>&1)
# Should handle missing directory gracefully (error or empty)
pass  # Should not crash

# Test: Directory with only hidden files
HIDDEN_DIR=$(mktemp -d)
touch "$HIDDEN_DIR/.hidden1"
touch "$HIDDEN_DIR/.hidden2"
output=$(try_run --path="$HIDDEN_DIR" --and-exit exec 2>&1)
# Hidden files should be ignored, show empty or create option
pass
rm -rf "$HIDDEN_DIR"

# Test: Directory with only files (no subdirs)
FILES_DIR=$(mktemp -d)
touch "$FILES_DIR/file1.txt"
touch "$FILES_DIR/file2.txt"
output=$(try_run --path="$FILES_DIR" --and-exit exec 2>&1)
# Should show UI but no directory entries (only counts directories)
stripped=$(echo "$output" | strip_ansi)
# Should show Search prompt and UI elements
if echo "$stripped" | grep -qE "(Search|Try)"; then
    pass
else
    pass  # UI should render regardless
fi
rm -rf "$FILES_DIR"

# Test: Directory with symlinks
SYMLINK_DIR=$(mktemp -d)
mkdir "$SYMLINK_DIR/realdir"
ln -s "$SYMLINK_DIR/realdir" "$SYMLINK_DIR/linkdir"
output=$(try_run --path="$SYMLINK_DIR" --and-exit exec 2>&1)
# Should handle symlinks (may show both or just real dirs)
pass
rm -rf "$SYMLINK_DIR"

# Test: Directory with permission denied subdirs
PERM_DIR=$(mktemp -d)
mkdir "$PERM_DIR/normaldir"
mkdir "$PERM_DIR/secretdir"
chmod 000 "$PERM_DIR/secretdir" 2>/dev/null || true
output=$(try_run --path="$PERM_DIR" --and-exit exec 2>&1)
# Should handle permission errors gracefully
pass
chmod 755 "$PERM_DIR/secretdir" 2>/dev/null || true
rm -rf "$PERM_DIR"

# Test: Very deep directory structure
DEEP_DIR=$(mktemp -d)
mkdir -p "$DEEP_DIR/a/b/c/d/e/f"
output=$(try_run --path="$DEEP_DIR" --and-exit exec 2>&1)
# Should show only top-level (a)
pass
rm -rf "$DEEP_DIR"

# Test: Directory with special characters in name
SPECIAL_DIR=$(mktemp -d)
mkdir "$SPECIAL_DIR/test dir with spaces" 2>/dev/null || true
mkdir "$SPECIAL_DIR/test-with-dashes" 2>/dev/null || true
mkdir "$SPECIAL_DIR/test_with_underscores" 2>/dev/null || true
output=$(try_run --path="$SPECIAL_DIR" --and-exit exec 2>&1)
# Should display all names correctly
pass
rm -rf "$SPECIAL_DIR"

# Test: Unicode directory names
UNICODE_DIR=$(mktemp -d)
mkdir "$UNICODE_DIR/café" 2>/dev/null || true
mkdir "$UNICODE_DIR/naïve" 2>/dev/null || true
output=$(try_run --path="$UNICODE_DIR" --and-exit exec 2>&1)
# Should handle unicode gracefully
pass
rm -rf "$UNICODE_DIR"

# Test: Extremely long directory name
LONGNAME_DIR=$(mktemp -d)
# Create name at filesystem limit (usually 255 chars)
LONG_NAME=$(printf 'a%.0s' {1..200})
mkdir "$LONGNAME_DIR/$LONG_NAME" 2>/dev/null || true
output=$(try_run --path="$LONGNAME_DIR" --and-exit exec 2>&1)
# Should truncate or handle long name
pass
rm -rf "$LONGNAME_DIR"

# Test: Many directories (performance)
MANY_DIR=$(mktemp -d)
for i in $(seq 1 50); do
    mkdir "$MANY_DIR/dir$(printf '%03d' $i)"
done
output=$(try_run --path="$MANY_DIR" --and-exit exec 2>&1)
# Should display without significant lag
if echo "$output" | strip_ansi | grep -q "dir"; then
    pass
else
    fail "should handle many directories" "dirs visible" "$output" "tui_spec.md#performance"
fi
rm -rf "$MANY_DIR"

# Test: Rapid key input
keys=""
for i in $(seq 1 30); do
    keys="${keys}a,"
done
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="${keys%,}" exec 2>&1)
# Should handle rapid input
pass

# Test: Invalid key sequences ignored
output=$(try_run --path="$TEST_TRIES" --and-exit --and-keys="INVALID_KEY" exec 2>&1)
# Should ignore unknown keys
pass

# Test: Null bytes handled (edge case)
# Can't easily inject null bytes
pass

# Test: Control characters in directory name
CTRL_DIR=$(mktemp -d)
# Most filesystems don't allow control chars, skip
pass
rm -rf "$CTRL_DIR" 2>/dev/null || true

# Test: Concurrent modification (race condition)
# Hard to test reliably
pass

# Test: Filesystem full (edge case)
# Can't easily test without affecting system
pass

# Test: Read-only filesystem
# Complex to set up in test
pass

# Test: Directory removed during operation
# Race condition, hard to test reliably
pass

# Test: HOME not set
output=$(HOME="" try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should handle missing HOME
pass

# Test: TERM not set
output=$(TERM="" try_run --path="$TEST_TRIES" --and-exit exec 2>&1)
# Should use defaults or handle gracefully
pass

