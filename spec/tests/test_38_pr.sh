# PR command tests
# Spec: command_line.md (pr command)

section "pr"

# Test 1: PR with URL (default naming)
output=$(try_run --path="$TEST_TRIES" exec pr https://github.com/user/repo/pull/123 2>&1)
if echo "$output" | grep -q "git clone" && echo "$output" | grep -q "pull/123/head" && echo "$output" | grep -q "user-repo-pr-123"; then
    pass
else
    fail "pr with URL should clone and fetch pr" "contains git clone and pull/123/head" "$output" "command_line.md#pr"
fi

# Test 2: PR with URL and custom name
output=$(try_run --path="$TEST_TRIES" exec pr https://github.com/user/repo/pull/123 my-custom-pr 2>&1)
if echo "$output" | grep -q "git clone" && echo "$output" | grep -q "pull/123/head" && echo "$output" | grep -q "my-custom-pr"; then
    pass
else
    fail "pr with URL and custom name should clone to custom name" "contains my-custom-pr" "$output" "command_line.md#pr"
fi

# Test 3: PR shorthand user/repo#id
output=$(try_run --path="$TEST_TRIES" exec pr user/repo#456 2>&1)
if echo "$output" | grep -q "git clone" && echo "$output" | grep -q "pull/456/head" && echo "$output" | grep -q "user-repo-pr-456"; then
    pass
else
    fail "pr with user/repo#id shorthand should clone and fetch pr" "contains git clone and pull/456/head" "$output" "command_line.md#pr"
fi

# Test 4: Numeric ID outside git repository should error
# Start in the $TEST_TRIES which is not a git repo
output=$(cd "$TEST_TRIES" && try_run --path="$TEST_TRIES" exec pr 789 2>&1)
exit_code=$?
if [ $exit_code -ne 0 ] && echo "$output" | grep -qi "error" && echo "$output" | grep -qi "git repository"; then
    pass
else
    fail "numeric ID outside git repository should fail with error" "exit code non-zero, error message" "exit=$exit_code output=$output" "command_line.md#pr"
fi

# Test 5: Numeric ID inside git repository should fetch and create worktree
FAKE_REPO=$(mktemp -d)
(cd "$FAKE_REPO" && git init -q)
# Ensure we run from inside the fake git repository
output=$(cd "$FAKE_REPO" && try_run --path="$TEST_TRIES" exec pr 789 2>&1)
if echo "$output" | grep -q "worktree add" && echo "$output" | grep -q "pull/789/head"; then
    pass
else
    fail "numeric ID inside git repository should fetch and add worktree" "contains worktree add and pull/789/head" "$output" "command_line.md#pr"
fi
rm -rf "$FAKE_REPO"

# Test 6: Shorthand PR URL direct execution (no pr command keyword)
output=$(try_run --path="$TEST_TRIES" exec https://github.com/user/repo/pull/123 2>&1)
if echo "$output" | grep -q "git clone" && echo "$output" | grep -q "pull/123/head" && echo "$output" | grep -q "user-repo-pr-123"; then
    pass
else
    fail "direct PR URL shorthand should clone and fetch pr" "contains git clone and pull/123/head" "$output" "command_line.md#pr"
fi
