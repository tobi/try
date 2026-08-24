# GitHub pull request URL shorthand
# A full PR URL clones the main repository and checks out the PR directly.

section "pr-url"

pr_url="https://github.com/tobi/try/pull/124"
output=$(try_run --path="$TEST_TRIES" exec clone "$pr_url" 2>&1)
if echo "$output" | grep -q "git clone 'https://github.com/tobi/try.git'" && \
   echo "$output" | grep -q "fetch origin 'pull/124/head'" && \
   echo "$output" | grep -q "checkout --detach FETCH_HEAD"; then
    pass
else
    fail "clone with a GitHub PR URL should fetch and check out the PR" "clone, pull/124/head fetch, and detached checkout" "$output" "command_line.md#clone"
fi

if echo "$output" | grep -qE "${TEST_TRIES}/[0-9]{4}-[0-9]{2}-[0-9]{2}-tobi-try'" && \
   ! echo "$output" | grep -q "pull-124\|pr-124"; then
    pass
else
    fail "PR URL should use the main repository name" "date-tobi-try without PR suffix" "$output" "command_line.md#clone"
fi

# Bare URL shorthand should use the same workflow.
output=$(try_run --path="$TEST_TRIES" exec "$pr_url" 2>&1)
if echo "$output" | grep -q "git clone 'https://github.com/tobi/try.git'" && \
   echo "$output" | grep -q "pull/124/head"; then
    pass
else
    fail "bare GitHub PR URL should use the clone-and-checkout workflow" "repository clone and pull/124/head fetch" "$output" "command_line.md#clone"
fi
