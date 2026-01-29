# Git URI parsing and quoting tests
# Tests: parse_git_uri, is_git_uri?, q()

section "git-uri"

# Test: SSH git@github.com format
output=$(try_run --path="$TEST_TRIES" exec clone git@github.com:user/myrepo 2>&1)
if echo "$output" | grep -q "user-myrepo"; then
    pass
else
    fail "SSH git@github.com should parse user/repo" "user-myrepo" "$output" "git_uri"
fi

# Test: SSH with .git suffix stripping (directory name should not contain .git)
output=$(try_run --path="$TEST_TRIES" exec clone git@github.com:user/myrepo.git 2>&1)
# The cd target path should end with user-myrepo, not user-myrepo.git
if echo "$output" | grep -qE "cd '.*user-myrepo'"; then
    pass
else
    fail "SSH clone should strip .git suffix from directory name" "cd path ends with user-myrepo" "$output" "git_uri"
fi

# Test: Non-GitHub HTTPS host (gitlab.com)
output=$(try_run --path="$TEST_TRIES" exec clone https://gitlab.com/user/glrepo 2>&1)
if echo "$output" | grep -q "user-glrepo"; then
    pass
else
    fail "HTTPS gitlab.com should parse user/repo" "user-glrepo" "$output" "git_uri"
fi

# Test: Non-GitHub SSH host
output=$(try_run --path="$TEST_TRIES" exec clone git@gitlab.com:user/sshrepo 2>&1)
if echo "$output" | grep -q "user-sshrepo"; then
    pass
else
    fail "SSH gitlab.com should parse user/repo" "user-sshrepo" "$output" "git_uri"
fi

# Test: Unparseable URI produces error
output=$(try_run --path="$TEST_TRIES" exec clone not-a-valid-uri 2>&1)
exit_code=$?
if [ $exit_code -ne 0 ]; then
    pass
else
    fail "Unparseable URI should produce error exit" "non-zero exit code" "exit=$exit_code output=$output" "git_uri"
fi

# Test: is_git_uri detects gitlab.com
output=$(try_run --path="$TEST_TRIES" exec https://gitlab.com/user/repo 2>&1)
if echo "$output" | grep -q "git clone"; then
    pass
else
    fail "gitlab.com URL should be detected as git URI" "git clone" "$output" "git_uri"
fi

# Test: is_git_uri detects .git suffix
output=$(try_run --path="$TEST_TRIES" exec https://example.com/user/repo.git 2>&1)
if echo "$output" | grep -q "git clone"; then
    pass
else
    fail ".git suffix should be detected as git URI" "git clone" "$output" "git_uri"
fi

# Test: Shell quoting with special characters in path
output=$(try_run --path="$TEST_TRIES" exec clone https://github.com/user/repo 2>&1)
# q() wraps in single quotes; check output uses single-quoted paths
if echo "$output" | grep -qE "cd '.*repo'"; then
    pass
else
    fail "Clone output should use single-quoted paths" "single-quoted cd" "$output" "git_uri"
fi
