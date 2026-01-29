# Versioning tests (resolve_unique_name_with_versioning)
# Tests: collision resolution for worktree and dot shorthand

section "versioning"

# Setup: create a temporary directory for versioning tests
VER_DIR=$(mktemp -d)
FAKE_GIT_REPO=$(mktemp -d)
mkdir -p "$FAKE_GIT_REPO/.git"

today=$(date +%Y-%m-%d)

# Test: No collision creates normally
output=$(cd "$FAKE_GIT_REPO" && try_run --path="$VER_DIR" exec . fresh-name 2>&1)
if echo "$output" | grep -qE "${today}-fresh-name"; then
    pass
else
    fail "No collision should create normally" "${today}-fresh-name" "$output" "versioning"
fi

# Test: Numeric suffix collision bumps number
mkdir -p "$VER_DIR/${today}-feature1"
output=$(cd "$FAKE_GIT_REPO" && try_run --path="$VER_DIR" exec . feature1 2>&1)
if echo "$output" | grep -qE "${today}-feature2"; then
    pass
else
    fail "Numeric suffix collision should bump number" "${today}-feature2" "$output" "versioning"
fi

# Test: Non-numeric collision appends -2
mkdir -p "$VER_DIR/${today}-nonum"
output=$(cd "$FAKE_GIT_REPO" && try_run --path="$VER_DIR" exec . nonum 2>&1)
if echo "$output" | grep -qE "${today}-nonum-2"; then
    pass
else
    fail "Non-numeric collision should append -2" "${today}-nonum-2" "$output" "versioning"
fi

# Test: Worktree script with explicit repo path
output=$(try_run --path="$VER_DIR" exec worktree "$FAKE_GIT_REPO" wtname 2>&1)
if echo "$output" | grep -q "worktree add"; then
    pass
else
    fail "Worktree with explicit repo should emit worktree add" "worktree add" "$output" "versioning"
fi

# Test: Worktree script without repo (uses cwd)
output=$(cd "$FAKE_GIT_REPO" && try_run --path="$VER_DIR" exec worktree dir cwdname 2>&1)
if echo "$output" | grep -q "worktree add"; then
    pass
else
    fail "Worktree without repo should emit worktree add" "worktree add" "$output" "versioning"
fi

# Cleanup
rm -rf "$VER_DIR" "$FAKE_GIT_REPO"
