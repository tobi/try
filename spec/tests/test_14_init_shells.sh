# Init command shell function tests
# Spec: init_spec.md

section "init-shells"

# Test: init with bash shell emits bash function
output=$(SHELL=/bin/bash try_run init "$TEST_TRIES" 2>&1)
if echo "$output" | grep -q "try() {"; then
    pass
else
    fail "init should emit bash function" "try() {" "$output" "init_spec.md"
fi

# Test: bash function includes --path argument with the specified path
if echo "$output" | grep -qF -- "--path '$TEST_TRIES'"; then
    pass
else
    fail "bash function should include --path with specified path" "--path '$TEST_TRIES'" "$output" "init_spec.md"
fi

# Test: init invoked by fish emits fish function
FAKE_PS_DIR=$(mktemp -d)
printf '#!/bin/sh\nprintf "fish\\n"\n' > "$FAKE_PS_DIR/ps"
chmod +x "$FAKE_PS_DIR/ps"
output=$(PATH="$FAKE_PS_DIR:$PATH" SHELL=/bin/zsh try_run init "$TEST_TRIES" 2>&1)
if echo "$output" | grep -q "function try"; then
    pass
else
    fail "init with fish should emit fish function" "function try" "$output" "init_spec.md"
fi
rm -rf "$FAKE_PS_DIR"

# Test: init output contains the real, full path to try binary
output=$(SHELL=/bin/bash try_run init "$TEST_TRIES" 2>&1)
if echo "$output" | grep -qF "$TRY_BIN_PATH"; then
    pass
else
    fail "init should contain real, full path to try binary" "$TRY_BIN_PATH" "$output" "init_spec.md"
fi
