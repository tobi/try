# Rename validation edge case tests
# Tests: finalize_rename validation paths via TUI

section "rename-validation"

# Setup: Create test directories for rename validation
RVAL_DIR=$(mktemp -d)
mkdir -p "$RVAL_DIR/2025-11-01-existing"
mkdir -p "$RVAL_DIR/2025-11-02-target"
touch -t 202511010000 "$RVAL_DIR/2025-11-01-existing"
touch -t 202511020000 "$RVAL_DIR/2025-11-02-target"

# Test: Ctrl-A,Ctrl-K clears name, Enter stays in dialog (no mv output)
# Ctrl-A moves cursor to start, Ctrl-K kills to end = clears entire buffer
output=$(try_run --path="$RVAL_DIR" --and-keys='CTRL-R,CTRL-A,CTRL-K,ENTER,ESC' exec 2>/dev/null)
if [ -z "$output" ] || ! echo "$output" | grep -q "mv"; then
    pass
else
    fail "Empty name after Ctrl-A,Ctrl-K should not produce mv" "no mv" "$output" "rename_validation"
fi

# Test: Whitespace-only name rejected
output=$(try_run --path="$RVAL_DIR" --and-keys='CTRL-R,CTRL-A,CTRL-K, , , ,ENTER,ESC' exec 2>/dev/null)
if [ -z "$output" ] || ! echo "$output" | grep -q "mv"; then
    pass
else
    fail "Whitespace-only name should not produce mv" "no mv" "$output" "rename_validation"
fi

# Test: Collision with existing directory name
output=$(try_run --path="$RVAL_DIR" --and-keys='CTRL-R,CTRL-A,CTRL-K,TYPE=2025-11-01-existing,ENTER,ESC' exec 2>/dev/null)
if [ -z "$output" ] || ! echo "$output" | grep -q "mv"; then
    pass
else
    fail "Collision with existing dir should not produce mv" "no mv" "$output" "rename_validation"
fi

# Test: Spaces normalized to dashes in rename
# Note: TYPE= values are uppercased by the token parser, so we check for uppercase
output=$(try_run --path="$RVAL_DIR" --and-keys='CTRL-R,CTRL-A,CTRL-K,TYPE=new name here,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "NEW-NAME-HERE"; then
    pass
else
    fail "Spaces should be normalized to dashes" "NEW-NAME-HERE" "$output" "rename_validation"
fi

# Test: Rename no-op (same name) exits cleanly
output=$(try_run --path="$RVAL_DIR" --and-keys='CTRL-R,ENTER' exec 2>/dev/null)
if [ -z "$output" ] || ! echo "$output" | grep -q "mv"; then
    pass
else
    fail "Same-name rename should exit without mv" "no mv" "$output" "rename_validation"
fi

# Test: Slash in name rejected
output=$(try_run --path="$RVAL_DIR" --and-keys='CTRL-R,/,ENTER,ESC' exec 2>/dev/null)
if [ -z "$output" ] || ! echo "$output" | grep -q "mv"; then
    pass
else
    fail "Slash in rename should not produce mv" "no mv" "$output" "rename_validation"
fi

# Cleanup
rm -rf "$RVAL_DIR"
