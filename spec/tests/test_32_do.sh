# Do command tests
# Spec: try do moves a try directory to a permanent work directory

section "do"

# Setup: Create isolated test directories
DO_TRIES_DIR=$(mktemp -d)
DO_WORK_DIR=$(mktemp -d)
mkdir -p "$DO_TRIES_DIR/2025-08-17-redis-pool"
touch "$DO_TRIES_DIR/2025-08-17-redis-pool/README.md"
mkdir -p "$DO_TRIES_DIR/2025-09-01-no-date-strip"
mkdir -p "$DO_TRIES_DIR/plain-project"

# Test: try do from outside tries dir shows error
output=$(TRY_DO_PATH="$DO_WORK_DIR" try_run --path="$DO_TRIES_DIR" do 2>&1)
exit_code=$?
if echo "$output" | grep -qi "not inside tries directory"; then
    pass
else
    fail "do outside tries dir should error" "not inside tries directory" "$output"
fi

# Test: try do from outside tries dir exits non-zero
if [ $exit_code -ne 0 ]; then
    pass
else
    fail "do outside tries dir should exit non-zero" "exit code != 0" "exit code: $exit_code"
fi

# Test: try exec do from outside tries dir shows error
output=$(TRY_DO_PATH="$DO_WORK_DIR" try_run --path="$DO_TRIES_DIR" exec do 2>&1)
exit_code=$?
if echo "$output" | grep -qi "not inside tries directory"; then
    pass
else
    fail "exec do outside tries dir should error" "not inside tries directory" "$output"
fi

# Test: try do at tries root shows specific message
output=$(cd "$DO_TRIES_DIR" && TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>&1)
if echo "$output" | grep -qi "cd into a try directory first"; then
    pass
else
    fail "do at tries root should say cd into a try directory" "cd into a try directory first" "$output"
fi

# Test: try do generates mv command (accept default name)
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>/dev/null)
if echo "$output" | grep -q "mv"; then
    pass
else
    fail "do should generate mv command" "mv in output" "$output"
fi

# Test: try do strips date prefix for default name
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>/dev/null)
if echo "$output" | grep -q "redis-pool"; then
    pass
else
    fail "do should use stripped name as default" "redis-pool in output" "$output"
fi

# Test: try do destination uses DO_WORK_DIR
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>/dev/null)
if echo "$output" | grep -q "$DO_WORK_DIR/redis-pool"; then
    pass
else
    fail "do should move to DO_WORK_DIR" "$DO_WORK_DIR/redis-pool" "$output"
fi

# Test: try do includes git init
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>/dev/null)
if echo "$output" | grep -q "git init"; then
    pass
else
    fail "do should include git init" "git init in output" "$output"
fi

# Test: try do with custom name uses that name
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "my-project" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>/dev/null)
if echo "$output" | grep -q "$DO_WORK_DIR/my-project"; then
    pass
else
    fail "do with custom name should use it" "$DO_WORK_DIR/my-project" "$output"
fi

# Test: try do prompts for name on stderr
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>&1 1>/dev/null)
if echo "$output" | grep -q "Name \[redis-pool\]:"; then
    pass
else
    fail "do should prompt for name on stderr" "Name [redis-pool]:" "$output"
fi

# Test: try do shows From path on stderr
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>&1 1>/dev/null)
if echo "$output" | grep -q "From:"; then
    pass
else
    fail "do should show From: on stderr" "From:" "$output"
fi

# Test: try do shows To path on stderr
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>&1 1>/dev/null)
if echo "$output" | grep -q "To:"; then
    pass
else
    fail "do should show To: on stderr" "To:" "$output"
fi

# Test: try do when destination exists shows error
mkdir -p "$DO_WORK_DIR/redis-pool"
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>&1)
exit_code=$?
if echo "$output" | grep -qi "destination already exists"; then
    pass
else
    fail "do should error when destination exists" "destination already exists" "$output"
fi
rmdir "$DO_WORK_DIR/redis-pool"

# Test: try do when destination exists exits non-zero
mkdir -p "$DO_WORK_DIR/redis-pool"
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>&1)
exit_code=$?
if [ $exit_code -ne 0 ]; then
    pass
else
    fail "do should exit non-zero when destination exists" "exit code != 0" "exit code: $exit_code"
fi
rmdir "$DO_WORK_DIR/redis-pool"

# Test: try do from subdirectory of try dir still works (uses parent try dir)
mkdir -p "$DO_TRIES_DIR/2025-08-17-redis-pool/src/lib"
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool/src/lib" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>/dev/null)
if echo "$output" | grep -q "2025-08-17-redis-pool"; then
    pass
else
    fail "do from subdirectory should use parent try dir" "2025-08-17-redis-pool in output" "$output"
fi

# Test: try do never includes gh repo create
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>/dev/null)
if ! echo "$output" | grep -q "gh repo create"; then
    pass
else
    fail "do should not include gh repo create" "no gh repo create" "$output"
fi

# Test: try do script ends with cd to destination
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>/dev/null)
last_line=$(echo "$output" | tail -1)
if echo "$last_line" | grep -q "cd "; then
    pass
else
    fail "do script should end with cd" "cd as last command" "$output"
fi

# Test: try do script includes ln -s (leaves symlink behind)
output=$(cd "$DO_TRIES_DIR/2025-08-17-redis-pool" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>/dev/null)
if echo "$output" | grep -q "ln -s"; then
    pass
else
    fail "do should include ln -s" "ln -s in output" "$output"
fi

# Test: try do on already-graduated symlink shows error
mkdir -p "$DO_WORK_DIR/already-done"
ln -s "$DO_WORK_DIR/already-done" "$DO_TRIES_DIR/2025-09-01-graduated"
output=$(cd "$DO_TRIES_DIR/2025-09-01-graduated" && echo "" | TRY_DO_PATH="$DO_WORK_DIR" eval $TRY_CMD --path="$DO_TRIES_DIR" do 2>&1)
exit_code=$?
if echo "$output" | grep -qi "already graduated"; then
    pass
else
    fail "do on symlink should say already graduated" "already graduated" "$output"
fi

# Test: try do on already-graduated symlink exits non-zero
if [ $exit_code -ne 0 ]; then
    pass
else
    fail "do on symlink should exit non-zero" "exit code != 0" "exit code: $exit_code"
fi
rm -f "$DO_TRIES_DIR/2025-09-01-graduated"
rm -rf "$DO_WORK_DIR/already-done"

# Test: symlinked entries show star emoji in TUI
ln -s "$DO_WORK_DIR" "$DO_TRIES_DIR/2025-10-01-starred"
output=$(try_run --path="$DO_TRIES_DIR" --and-exit exec 2>&1)
if echo "$output" | grep -q "⭐"; then
    pass
else
    fail "symlinked entry should show star emoji" "⭐ in output" "$output"
fi
rm -f "$DO_TRIES_DIR/2025-10-01-starred"

# Test: help text includes try do
output=$(try_run --help 2>&1)
if echo "$output" | grep -q "try do"; then
    pass
else
    fail "help should mention try do" "try do in help" "$output"
fi

# Test: help text mentions TRY_DO_PATH
output=$(try_run --help 2>&1)
if echo "$output" | grep -q "TRY_DO_PATH"; then
    pass
else
    fail "help should mention TRY_DO_PATH" "TRY_DO_PATH in help" "$output"
fi

# Cleanup
rm -rf "$DO_TRIES_DIR" "$DO_WORK_DIR"
