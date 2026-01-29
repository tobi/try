# Shell init tests
# Tests: fish?, init, extract_option_with_value!

section "shell-init"

# Test: SHELL=fish emits fish function
output=$(SHELL=/usr/local/bin/fish try_run init "$TEST_TRIES" 2>&1)
if echo "$output" | grep -q "function try"; then
    pass
else
    fail "SHELL=fish should emit fish function" "function try" "$output" "shell_init"
fi

# Test: SHELL=zsh emits bash/zsh function
output=$(SHELL=/bin/zsh try_run init "$TEST_TRIES" 2>&1)
if echo "$output" | grep -q "try() {"; then
    pass
else
    fail "SHELL=zsh should emit bash/zsh function" "try() {" "$output" "shell_init"
fi

# Test: --path with space form
INIT_DIR=$(mktemp -d)
output=$(try_run --path "$INIT_DIR" --and-exit exec 2>&1)
exit_code=$?
# Should not error - the path was accepted
if [ $exit_code -ne 2 ]; then
    pass
else
    fail "--path with space form should work" "no error exit" "exit=$exit_code" "shell_init"
fi

# Test: --path with = form
output=$(try_run --path="$INIT_DIR" --and-exit exec 2>&1)
exit_code=$?
if [ $exit_code -ne 2 ]; then
    pass
else
    fail "--path with = form should work" "no error exit" "exit=$exit_code" "shell_init"
fi

# Test: --path= form uses correct directory contents
INIT_DIR2=$(mktemp -d)
mkdir -p "$INIT_DIR2/unique-marker-dir"
output=$(try_run --path="$INIT_DIR2" --and-exit exec 2>&1)
if echo "$output" | grep -q "unique-marker-dir"; then
    pass
else
    fail "--path= form should show directories from specified path" "unique-marker-dir in output" "$output" "shell_init"
fi

# Cleanup
rm -rf "$INIT_DIR" "$INIT_DIR2"
