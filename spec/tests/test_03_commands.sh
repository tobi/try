# Command routing tests
# Spec: command_line.md (Commands section)

section "commands"

# Test: init outputs shell function
output=$(try_run init 2>&1)
if echo "$output" | grep -q "try()"; then
    pass
else
    fail "init should output shell function" "contains 'try()'" "$output" "command_line.md#init"
fi

# Test: exec clone outputs git clone script
output=$(try_run --path="$TEST_TRIES" exec clone https://github.com/test/repo 2>&1)
if echo "$output" | grep -q "git clone"; then
    pass
else
    fail "exec clone should output git clone" "contains 'git clone'" "$output" "command_line.md#clone"
fi

# Test: clone script includes cd
if echo "$output" | grep -q "cd '"; then
    pass
else
    fail "exec clone should include cd" "contains cd command" "$output" "command_line.md#clone"
fi

# Test: exec cd is equivalent to exec (default command)
output1=$(try_run --path="$TEST_TRIES" --and-keys=$'\r' exec 2>/dev/null)
output2=$(try_run --path="$TEST_TRIES" --and-keys=$'\r' exec cd 2>/dev/null)
# Both should produce cd output (may differ in exact path selected, but both should have cd)
if echo "$output1" | grep -q "cd '" && echo "$output2" | grep -q "cd '"; then
    pass
else
    fail "exec and exec cd should both produce cd output" "cd command in both" "output1: $output1, output2: $output2" "command_line.md#cd"
fi
