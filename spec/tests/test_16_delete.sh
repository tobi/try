# Delete mode tests
# Spec: delete_spec.md

section "delete"

# Setup: Create test directories for deletion tests
DEL_TEST_DIR=$(mktemp -d)
mkdir -p "$DEL_TEST_DIR/2025-11-01-first"
mkdir -p "$DEL_TEST_DIR/2025-11-02-second"
mkdir -p "$DEL_TEST_DIR/2025-11-03-third"

# Test: Esc exits without action (no delete started)
output=$(try_run --path="$DEL_TEST_DIR" --and-keys='ESC' exec 2>/dev/null)
if [ -z "$output" ] || ! echo "$output" | grep -q "rm -rf"; then
    pass
else
    fail "Plain Esc should exit without delete" "no output" "$output" "tui_spec.md#keyboard-input"
fi

# Test: Ctrl-D then Esc exits delete mode without deleting
output=$(try_run --path="$DEL_TEST_DIR" --and-keys='CTRL-D,ESC' exec 2>/dev/null)
if echo "$output" | grep -q "rm -rf"; then
    fail "Ctrl-D then Esc should cancel delete" "no rm -rf" "$output" "delete_spec.md#step-3-confirm-or-cancel"
else
    pass
fi

# Test: Single delete - Ctrl-D + Enter + YES generates delete script
output=$(try_run --path="$DEL_TEST_DIR" --and-keys='CTRL-D,ENTER,Y,E,S,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "rm -rf"; then
    pass
else
    fail "Ctrl-D + Enter + YES should generate delete script" "rm -rf command" "$output" "delete_spec.md#script-output-format"
fi

# Test: Delete script has cd to base dir
if echo "$output" | grep -q "cd '.*' &&"; then
    pass
else
    fail "Delete script should cd to base dir" "cd 'path' &&" "$output" "delete_spec.md#script-components"
fi

# Test: Delete script uses test -d 'name' check (POSIX-compatible)
if echo "$output" | grep -q 'test -d '; then
    pass
else
    fail "Delete script should check directory exists" "test -d 'name'" "$output" "delete_spec.md#script-components"
fi

# Test: Delete script ends with PWD restoration
if echo "$output" | grep -qE 'cd .* \|\| cd "\$HOME"'; then
    pass
else
    fail "Delete script should restore PWD" "cd ... || cd \$HOME" "$output" "delete_spec.md#script-components"
fi

# Test: Ctrl-D + Enter with NO cancels
output=$(try_run --path="$DEL_TEST_DIR" --and-keys='CTRL-D,ENTER,n,o,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "rm -rf"; then
    fail "Confirming with 'no' should cancel delete" "no rm -rf" "$output" "delete_spec.md#step-4-type-yes-to-delete"
else
    pass
fi

# Test: Multi-delete - mark two items with Ctrl-D, down, Ctrl-D, Enter, YES
output=$(try_run --path="$DEL_TEST_DIR" --and-keys='CTRL-D,DOWN,CTRL-D,ENTER,Y,E,S,ENTER' exec 2>/dev/null)
# Count occurrences of rm -rf (may be on same line now)
count=$(echo "$output" | grep -o "rm -rf" | wc -l)
if [ "$count" -ge 2 ]; then
    pass
else
    fail "Multi-delete should generate multiple rm -rf" "2+ rm -rf commands" "$output (count: $count)" "delete_spec.md#script-structure"
fi

# Test: Toggle - Ctrl-D twice on same item should unmark, Esc exits
output=$(try_run --path="$DEL_TEST_DIR" --and-keys='CTRL-D,CTRL-D,ESC' exec 2>/dev/null)
if echo "$output" | grep -q "rm -rf"; then
    fail "Double Ctrl-D should toggle (unmark)" "no rm -rf" "$output" "delete_spec.md#step-1-mark-items"
else
    pass
fi

# Test: Delete uses basename not full path in rm command
output=$(try_run --path="$DEL_TEST_DIR" --and-keys='CTRL-D,ENTER,Y,E,S,ENTER' exec 2>/dev/null)
if echo "$output" | grep "rm -rf" | grep -q "rm -rf '2025-"; then
    pass
else
    fail "Delete should use basename in rm -rf" "rm -rf 'name'" "$output" "delete_spec.md#per-item-delete-commands"
fi

# Cleanup
rm -rf "$DEL_TEST_DIR"
