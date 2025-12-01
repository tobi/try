# Script output format compliance tests
# Spec: command_line.md (Script Output Format section)

section "script-format"

# Test: clone script format
output=$(try_run --path="$TEST_TRIES" exec clone https://github.com/user/repo 2>&1)

# Should have warning header
if echo "$output" | head -1 | grep -q "^#"; then
    pass
else
    fail "clone script should start with comment" "# comment" "$(echo "$output" | head -1)" "command_line.md#script-output-format"
fi

# Should have git clone command
if echo "$output" | grep -q "git clone 'https://github.com/user/repo'"; then
    pass
else
    fail "clone script should have git clone with URL" "git clone 'url'" "$output" "command_line.md#clone"
fi

# Should chain commands with && \
if echo "$output" | grep -q "&& \\\\"; then
    pass
else
    fail "commands should chain with && \\\\" "found && \\\\" "$output" "command_line.md#script-output-format"
fi

# cd should be on its own line with 2-space indent
if echo "$output" | grep -q "^  cd '"; then
    pass
else
    fail "cd should be on its own line with 2-space indent" "line starting with '  cd'" "$output" "command_line.md#script-output-format"
fi

# Test: cd script format (select existing directory)
output=$(try_run --path="$TEST_TRIES" --and-keys=$'\r' exec 2>/dev/null)

# Should touch the directory
if echo "$output" | grep -q "touch '"; then
    pass
else
    fail "cd script should touch directory" "touch command" "$output" "command_line.md#cd"
fi

# Should cd to directory
if echo "$output" | grep -q "cd '$TEST_TRIES/"; then
    pass
else
    fail "cd script should cd to tries path" "cd to test path" "$output" "command_line.md#cd"
fi
