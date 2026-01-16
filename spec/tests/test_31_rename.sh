# Rename mode tests
# Spec: Ctrl-R renames the selected entry

section "rename"

# Helper to strip ANSI codes
strip_ansi() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\x1b\[[?][0-9]*[a-zA-Z]//g'
}

# Setup: Create test directories for rename tests
REN_TEST_DIR=$(mktemp -d)
mkdir -p "$REN_TEST_DIR/2025-11-01-myproject"
mkdir -p "$REN_TEST_DIR/2025-11-02-coolproject"
mkdir -p "$REN_TEST_DIR/nodate-project"
touch -t 202511010000 "$REN_TEST_DIR/2025-11-01-myproject"
touch -t 202511020000 "$REN_TEST_DIR/2025-11-02-coolproject"
touch "$REN_TEST_DIR/nodate-project"

# Test: Ctrl-R opens rename dialog (check via CTRL-R,ESC)
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,ESC' exec 2>&1)
if echo "$output" | strip_ansi | grep -qi "Rename"; then
    pass
else
    fail "Ctrl-R should open rename dialog" "Rename in output" "$output" "rename"
fi

# Test: Rename dialog shows pencil emoji
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,ESC' exec 2>&1)
if echo "$output" | grep -qE "📝|✏️"; then
    pass
else
    fail "Rename dialog should show pencil emoji" "📝 or ✏️" "$output" "rename"
fi

# Test: Rename dialog pre-fills date prefix for dated entry
output=$(try_run --path="$REN_TEST_DIR" --and-keys='DOWN,CTRL-R,ESC' exec 2>&1)
if echo "$output" | grep -q "2025-11-02-"; then
    pass
else
    fail "Rename dialog should pre-fill date" "2025-11-02-" "$output" "rename"
fi

# Test: Rename dialog shows confirm hint
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,ESC' exec 2>&1)
if echo "$output" | strip_ansi | grep -qi "Enter.*Confirm"; then
    pass
else
    fail "Rename dialog should show confirm hint" "Enter: Confirm" "$output" "rename"
fi

# Test: Rename dialog shows cancel hint
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,ESC' exec 2>&1)
if echo "$output" | strip_ansi | grep -qi "Esc.*Cancel"; then
    pass
else
    fail "Rename dialog should show cancel hint" "Esc: Cancel" "$output" "rename"
fi

# Test: Rename Escape cancels
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,ESC' exec 2>/dev/null)
if [ -z "$output" ] || ! echo "$output" | grep -q "mv"; then
    pass
else
    fail "Ctrl-R then Esc should cancel rename" "no mv" "$output" "rename"
fi

# Test: Rename Enter with same name cancels (for entry with date prefix)
output=$(try_run --path="$REN_TEST_DIR" --and-keys='DOWN,CTRL-R,ENTER' exec 2>/dev/null)
# 2025-11-02-coolproject has date prefix, so same name should cancel
if [ -z "$output" ] || ! echo "$output" | grep -q "mv"; then
    pass
else
    fail "Rename with same name should cancel" "no mv" "$output" "rename"
fi

# Test: Rename with new suffix generates mv command
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,n,e,w,n,a,m,e,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "mv"; then
    pass
else
    fail "Rename with new name should generate mv" "mv command" "$output" "rename"
fi

# Test: Rename script contains old name
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,n,e,w,n,a,m,e,ENTER' exec 2>/dev/null)
# nodate-project is most recent (touched last)
if echo "$output" | grep -q "nodate-project"; then
    pass
else
    fail "Rename script should contain old name" "old name in script" "$output" "rename"
fi

# Test: Rename script contains new name
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,n,e,w,n,a,m,e,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "newname"; then
    pass
else
    fail "Rename script should contain new name" "new name in script" "$output" "rename"
fi

# Test: Rename script cds to base directory
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,n,e,w,n,a,m,e,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "Rename script should cd to base" "cd command" "$output" "rename"
fi

# Test: Rename rejects slash in name (path traversal prevention)
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,.,.,/,e,t,c,ENTER' exec 2>/dev/null)
if [ -z "$output" ] || ! echo "$output" | grep -q "mv"; then
    pass
else
    fail "Rename should reject slash in name" "no mv for path with /" "$output" "rename"
fi

# Test: Rename shows in footer hints
output=$(try_run --path="$REN_TEST_DIR" --and-exit exec 2>&1)
if echo "$output" | strip_ansi | grep -qE '(\^R|Ctrl-R).*Rename'; then
    pass
else
    fail "Footer should show rename hint" "^R: Rename or Ctrl-R: Rename" "$output" "rename"
fi

# Test: Rename dialog shows separator line
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,ESC' exec 2>&1)
if echo "$output" | grep -q '─'; then
    pass
else
    fail "Rename dialog should have separator lines" "─ character" "$output" "rename"
fi

# Test: Rename shows current name in dialog (with folder emoji)
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,ESC' exec 2>&1)
if echo "$output" | grep -qE "Current:|📁.*nodate-project"; then
    pass
else
    fail "Rename dialog should show current name" "Current: or 📁 with name" "$output" "rename"
fi

# Test: Rename shows new name field
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,ESC' exec 2>&1)
if echo "$output" | strip_ansi | grep -qi "New name:"; then
    pass
else
    fail "Rename dialog should show New name: label" "New name:" "$output" "rename"
fi

# Test: Backspace works in rename field
output=$(try_run --path="$REN_TEST_DIR" --and-keys='DOWN,CTRL-R,BACKSPACE,n,e,w,ENTER' exec 2>/dev/null)
# Navigate to coolproject and backspace one char then type new
if echo "$output" | grep -q "mv"; then
    pass
else
    fail "Backspace should work in rename" "mv command" "$output" "rename"
fi

# Test: Multiple items - navigate then rename
output=$(try_run --path="$REN_TEST_DIR" --and-keys='DOWN,CTRL-R,r,e,n,a,m,e,d,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "mv"; then
    pass
else
    fail "Rename should work on navigated item" "mv command" "$output" "rename"
fi

# Test: Rename cds to new directory
output=$(try_run --path="$REN_TEST_DIR" --and-keys='CTRL-R,n,e,w,n,a,m,e,ENTER' exec 2>/dev/null)
if echo "$output" | grep -qE "cd.*newname"; then
    pass
else
    fail "Rename should cd to new directory" "cd to newname" "$output" "rename"
fi

# Test: Entry with date prefix shows date in input field
output=$(try_run --path="$REN_TEST_DIR" --and-keys='DOWN,CTRL-R,ESC' exec 2>&1)
if echo "$output" | grep -q "2025-11-02-"; then
    pass
else
    fail "Entry with date should pre-fill date" "2025-11-02- prefix" "$output" "rename"
fi

# Cleanup
rm -rf "$REN_TEST_DIR"
