# Terminal manager panel/workspace title integration
# Rename commands are emitted only when the manager identifies itself.

section "tab-title"

# No manager environment: do not add optional manager commands.
output=$( (unset HERDR_ENV HERDR_PANE_ID HERDR_WORKSPACE_ID CMUX_SOCKET_PATH CMUX_BUNDLE_ID; try_run --path="$TEST_TRIES" --and-type='2025-11-01-alpha' exec --and-keys='ENTER' 2>/dev/null) )
if echo "$output" | grep -qE 'herdr tab rename|cmux rename-tab'; then
    fail "tab rename should be absent outside a terminal manager" "no rename command" "$output" "command_line.md#terminal-manager-tab-titles"
else
    pass
fi

# Herdr uses the inherited panel/workspace IDs and strips the date prefix.
output=$( (unset CMUX_SOCKET_PATH CMUX_BUNDLE_ID; export HERDR_ENV=1 HERDR_PANE_ID='wP:p1' HERDR_WORKSPACE_ID='wP'; try_run --path="$TEST_TRIES" --and-type='2025-11-01-alpha' exec --and-keys='ENTER' 2>/dev/null) )
if echo "$output" | grep -q "herdr pane report-metadata 'wP:p1' --source try --title 'try: alpha'" && echo "$output" | grep -q "herdr workspace rename 'wP' 'try: alpha'"; then
    pass
else
    fail "herdr panel 1 should receive subtitle and workspace project names" "herdr pane report-metadata ... --title 'try: alpha'" "$output" "command_line.md#terminal-manager-tab-titles"
fi

# cmux is identified by its inherited socket/bundle environment.
output=$( (unset HERDR_ENV HERDR_PANE_ID HERDR_WORKSPACE_ID CMUX_BUNDLE_ID; export CMUX_SOCKET_PATH='/tmp/cmux.sock'; try_run --path="$TEST_TRIES" --and-type='2025-11-01-alpha' exec --and-keys='ENTER' 2>/dev/null) )
if echo "$output" | grep -q "command -v cmux" && echo "$output" | grep -q "cmux rename-tab 'try: alpha'"; then
    pass
else
    fail "cmux should receive the project name" "cmux rename-tab 'try: alpha'" "$output" "command_line.md#terminal-manager-tab-titles"
fi

# The guards make the optional commands non-fatal when the CLI is unavailable.
if echo "$output" | grep -q "|| true"; then
    pass
else
    fail "tab rename should be best effort" "|| true" "$output" "command_line.md#terminal-manager-tab-titles"
fi
