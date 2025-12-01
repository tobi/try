# Path option tests
# Spec: command_line.md (Global Options)

section "path-option"

# Test: --path overrides default tries directory
# Create a separate test directory
ALT_TRIES="$TEST_ROOT/alt-tries"
mkdir -p "$ALT_TRIES/alt-project"
touch "$ALT_TRIES/alt-project"

# Using --path should show alt-project, not directories from TEST_TRIES
output=$(try_run --path="$ALT_TRIES" --and-keys=$'\r' exec 2>/dev/null)
if echo "$output" | grep -q "alt-project"; then
    pass
else
    fail "--path should override default directory" "path contains 'alt-project'" "$output" "command_line.md#global-options"
fi

# Test: --path= form works the same
output=$(try_run --path="$ALT_TRIES" --and-exit exec 2>&1)
if echo "$output" | grep -q "alt-project"; then
    pass
else
    fail "--path= form should work" "output contains 'alt-project'" "$output" "command_line.md#global-options"
fi

# Test: Empty tries directory should still work (show [new] or empty)
EMPTY_TRIES="$TEST_ROOT/empty-tries"
mkdir -p "$EMPTY_TRIES"
try_run --path="$EMPTY_TRIES" --and-exit exec >/dev/null 2>&1
exit_code=$?
# Should not crash (exit code 0 or 1 are valid)
if [ $exit_code -eq 0 ] || [ $exit_code -eq 1 ]; then
    pass
else
    fail "empty tries directory should not crash" "exit code 0 or 1" "exit code $exit_code" "command_line.md#global-options"
fi
