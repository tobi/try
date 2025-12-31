# Init command shell function tests
# Spec: init_spec.md

section "init-shells"

# Test: init with bash shell emits bash function
bash_output=$(SHELL=/bin/bash try_run init "$TEST_TRIES" 2>&1)
if echo "$bash_output" | grep -q "try() {"; then
    pass
else
    fail "init should emit bash function" "try() {" "$bash_output" "init_spec.md"
fi

# Test: bash function includes --path argument with the specified path
if echo "$bash_output" | grep -qF -- "--path '$TEST_TRIES'"; then
    pass
else
    fail "bash function should include --path with specified path" "--path '$TEST_TRIES'" "$bash_output" "init_spec.md"
fi

# Test: bash wrapper keeps TTY stream for control keys
if echo "$bash_output" | grep -q '2>/dev/tty'; then
    pass
else
    fail "bash init should keep stderr attached to TTY" "2>/dev/tty" "$bash_output" "init_spec.md"
fi

# Test: bash wrapper evals returned script
if echo "$bash_output" | grep -q 'eval "\$out"'; then
    pass
else
    fail "bash init should eval returned script" 'eval "$out"' "$bash_output" "init_spec.md"
fi

# Test: init with fish shell emits fish function
fish_output=$(SHELL=/usr/bin/fish try_run init "$TEST_TRIES" 2>&1)
if echo "$fish_output" | grep -q "function try"; then
    pass
else
    fail "init with fish should emit fish function" "function try" "$fish_output" "init_spec.md"
fi

# Test: fish wrapper keeps TTY stream for control keys
if echo "$fish_output" | grep -q '2>/dev/tty'; then
    pass
else
    fail "fish init should keep stderr attached to TTY" "2>/dev/tty" "$fish_output" "init_spec.md"
fi

# Test: fish wrapper evals returned script
if echo "$fish_output" | grep -q 'eval $out'; then
    pass
else
    fail "fish init should eval returned script" "eval \$out" "$fish_output" "init_spec.md"
fi

# Test: init output contains the real, full path to try binary
if echo "$bash_output" | grep -qF "$TRY_BIN_PATH"; then
    pass
else
    fail "init should contain real, full path to try binary" "$TRY_BIN_PATH" "$bash_output" "init_spec.md"
fi
