# URL shorthand tests
# Spec: command_line.md (clone shortcuts)

section "url-shorthand"

# Test: cd <url> acts as clone shorthand
output=$(try_run --path="$TEST_TRIES" --and-exit exec cd https://github.com/user/repo  2>&1)
if echo "$output" | grep -q "git clone"; then
    pass
else
    fail "cd <url> should trigger git clone" "git clone command" "$output" "command_line.md#clone"
fi

# Test: cd <url> with custom name
output=$(try_run --path="$TEST_TRIES" --and-exit exec cd https://github.com/user/repo my-fork 2>&1)
if echo "$output" | grep -q "my-fork"; then
    pass
else
    fail "cd <url> <name> should use custom name" "my-fork in output" "$output" "command_line.md#clone"
fi

# Test: bare URL (without cd) also triggers clone
output=$(try_run --path="$TEST_TRIES" --and-exit exec https://github.com/user/repo 2>&1)
if echo "$output" | grep -q "git clone"; then
    pass
else
    fail "bare URL should trigger git clone" "git clone command" "$output" "command_line.md#clone"
fi
