# Shell init tests
# Tests: fish?, init, extract_option_with_value!

section "shell-init"

# Test: the invoking shell takes precedence over the login shell in $SHELL
FAKE_PS_DIR=$(mktemp -d)
printf '#!/bin/sh\nprintf "fish\\n"\n' > "$FAKE_PS_DIR/ps"
chmod +x "$FAKE_PS_DIR/ps"
output=$(PATH="$FAKE_PS_DIR:$PATH" SHELL=/bin/zsh try_run init "$TEST_TRIES" 2>&1)
if echo "$output" | grep -q "function try"; then
    pass
else
    fail "fish parent should override SHELL=zsh" "function try" "$output" "shell_init"
fi

# Test: a non-fish parent also takes precedence over SHELL=fish
printf '#!/bin/sh\nprintf "zsh\\n"\n' > "$FAKE_PS_DIR/ps"
output=$(PATH="$FAKE_PS_DIR:$PATH" SHELL=/usr/local/bin/fish try_run init "$TEST_TRIES" 2>&1)
if echo "$output" | grep -q "try() {"; then
    pass
else
    fail "zsh parent should override SHELL=fish" "try() {" "$output" "shell_init"
fi

# Test: SHELL is used when the parent shell cannot be detected
printf '#!/bin/sh\n' > "$FAKE_PS_DIR/ps"
output=$(PATH="$FAKE_PS_DIR:$PATH" SHELL=/usr/local/bin/fish try_run init "$TEST_TRIES" 2>&1)
if echo "$output" | grep -q "function try"; then
    pass
else
    fail "SHELL=fish should be the fallback" "function try" "$output" "shell_init"
fi
rm -rf "$FAKE_PS_DIR"

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
