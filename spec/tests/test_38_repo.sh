# GitHub repo publishing tests
# Verify try repo emits a script that publishes a plain try folder via gh.

section "repo"

REPO_DIR=$(mktemp -d)
mkdir -p "$REPO_DIR/2026-05-16-my-app"
echo "hello" > "$REPO_DIR/2026-05-16-my-app/README.md"

# Test: CLI repo command initializes git and creates a private GitHub repo by default
output=$(try_run --path="$REPO_DIR" repo 2026-05-16-my-app 2>&1)
if echo "$output" | grep -q "git init" && echo "$output" | grep -q "gh repo create 'my-app' --private --source=. --remote=origin --push"; then
    pass
else
    fail "repo should init git and create private GitHub repo" "git init and gh repo create 'my-app' --private" "$output" "command_line.md#repo"
fi

# Test: repo command stages and commits current files
if echo "$output" | grep -q "git add ." && echo "$output" | grep -q "git commit -m 'Initial commit'"; then
    pass
else
    fail "repo should add and commit files" "git add . and initial commit" "$output" "command_line.md#repo"
fi

# Test: cleanup runs after gh repo create so failures leave .git for debugging
gh_line=$(echo "$output" | grep -n "gh repo create" | cut -d: -f1 | head -1)
cleanup_line=$(echo "$output" | grep -n "rm -rf '.git'" | cut -d: -f1 | head -1)
if [ -n "$gh_line" ] && [ -n "$cleanup_line" ] && [ "$cleanup_line" -gt "$gh_line" ]; then
    pass
else
    fail "repo should clean up .git after gh succeeds" "rm -rf '.git' after gh repo create" "$output" "command_line.md#repo"
fi

# Test: --public uses public visibility
output=$(try_run --path="$REPO_DIR" repo 2026-05-16-my-app --public 2>&1)
if echo "$output" | grep -q "gh repo create 'my-app' --public --source=. --remote=origin --push"; then
    pass
else
    fail "repo --public should create public GitHub repo" "--public" "$output" "command_line.md#repo"
fi

# Test: custom repo name overrides stripped directory name
output=$(try_run --path="$REPO_DIR" repo 2026-05-16-my-app better-name 2>&1)
if echo "$output" | grep -q "gh repo create 'better-name' --private --source=. --remote=origin --push"; then
    pass
else
    fail "repo should accept custom repo name" "better-name" "$output" "command_line.md#repo"
fi

# Test: existing relative paths win over same-named TRY_PATH children
LOCAL_ROOT=$(mktemp -d)
mkdir -p "$LOCAL_ROOT/shared-name"
mkdir -p "$REPO_DIR/shared-name"
LOCAL_SOURCE=$(cd "$LOCAL_ROOT/shared-name" && pwd -P)
output=$(cd "$LOCAL_ROOT" && try_run --path="$REPO_DIR" repo ./shared-name 2>&1)
if echo "$output" | grep -q "cd '$LOCAL_SOURCE'"; then
    pass
else
    fail "repo should prefer existing relative source paths" "cd '$LOCAL_SOURCE'" "$output" "command_line.md#repo"
fi

# Test: repo refuses existing git repositories to avoid deleting history
mkdir -p "$REPO_DIR/2026-05-16-existing-git/.git"
output=$(try_run --path="$REPO_DIR" repo 2026-05-16-existing-git 2>&1)
if echo "$output" | grep -q "already contains .git"; then
    pass
else
    fail "repo should refuse existing git repository" "already contains .git" "$output" "command_line.md#repo"
fi

# Test: exec repo command emits the same publish script
output=$(try_run --path="$REPO_DIR" exec repo 2026-05-16-my-app 2>&1)
if echo "$output" | grep -q "gh repo create 'my-app' --private --source=. --remote=origin --push"; then
    pass
else
    fail "exec repo should emit publish script" "gh repo create" "$output" "command_line.md#repo"
fi

# Test: TUI action can publish selected try with default private visibility
output=$(try_run --path="$REPO_DIR" --and-keys='DOWN,CTRL-U,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "gh repo create 'my-app' --private --source=. --remote=origin --push"; then
    pass
else
    fail "Ctrl-U should publish selected try as private repo" "gh repo create 'my-app' --private" "$output" "tui_spec.md#keyboard"
fi

# Test: TUI action can toggle public visibility
output=$(try_run --path="$REPO_DIR" --and-keys='DOWN,CTRL-U,DOWN,ENTER' exec 2>/dev/null)
if echo "$output" | grep -q "gh repo create 'my-app' --public --source=. --remote=origin --push"; then
    pass
else
    fail "Repo dialog should allow public visibility" "--public" "$output" "tui_spec.md#keyboard"
fi

# Test: TUI repo dialog can be cancelled
output=$(try_run --path="$REPO_DIR" --and-keys='CTRL-U,ESC' exec 2>/dev/null)
if echo "$output" | grep -q "gh repo create"; then
    fail "Repo dialog Esc should cancel" "no gh repo create" "$output" "tui_spec.md#keyboard"
else
    pass
fi
