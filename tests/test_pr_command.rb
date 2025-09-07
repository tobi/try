require 'test/unit'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestPrCommand < Test::Unit::TestCase
  def setup
    @script_path = File.expand_path('../try.rb', __dir__)
  end

  def run_cmd(*args)
    cmd = [RbConfig.ruby, @script_path, *args]
    Open3.capture3(*cmd)
  end

  def run_cmd_in_git_repo(*args)
    # Create a temporary git repo for testing
    Dir.mktmpdir do |repo_dir|
      # Initialize a fake git repo with remote
      system("cd #{repo_dir} && git init >/dev/null 2>&1")
      system("cd #{repo_dir} && git remote add origin https://github.com/owner/repo.git >/dev/null 2>&1")
      
      # Run command from within the git repo
      cmd = [RbConfig.ruby, @script_path, *args]
      Open3.capture3(*cmd, chdir: repo_dir)
    end
  end

  # Test PR URL parsing and directory generation

  def test_pr_owner_repo_format
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Command should succeed"
      assert_match(/mkdir -p '.*2025-\d{2}-\d{2}-owner-repo-pr123'/, stdout, "Should create directory with PR fallback name")
      assert_match(/git clone 'https:\/\/github\.com\/owner\/repo\.git'/, stdout, "Should clone from correct URL")
      assert_match(/git fetch origin pull\/123\/head:pr-123/, stdout, "Should fetch PR branch")
      assert_match(/git checkout pr-123/, stdout, "Should checkout PR branch")
      assert_match(/cd '.*2025-\d{2}-\d{2}-owner-repo-pr123'/, stdout, "Should cd to directory")
    end
  end

  def test_pr_full_github_url_format
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'https://github.com/owner/repo/pull/456', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Command should succeed"
      assert_match(/mkdir -p '.*2025-\d{2}-\d{2}-owner-repo-pr456'/, stdout, "Should create directory with PR fallback name")
      assert_match(/git clone 'https:\/\/github\.com\/owner\/repo\.git'/, stdout, "Should clone from correct URL")
      assert_match(/git fetch origin pull\/456\/head:pr-456/, stdout, "Should fetch PR branch")
      assert_match(/git checkout pr-456/, stdout, "Should checkout PR branch")
    end
  end

  def test_pr_number_only_in_git_repo
    Dir.mktmpdir do |tries_dir|
      stdout, stderr, status = run_cmd_in_git_repo('cd', '789', '--path', tries_dir)
      
      assert_equal 0, status.exitstatus, "Command should succeed"
      assert_match(/mkdir -p '.*2025-\d{2}-\d{2}-owner-repo-pr789'/, stdout, "Should create directory with detected repo")
      assert_match(/git clone 'https:\/\/github\.com\/owner\/repo\.git'/, stdout, "Should clone from detected repo URL")
      assert_match(/git fetch origin pull\/789\/head:pr-789/, stdout, "Should fetch PR branch")
    end
  end

  def test_pr_with_custom_name
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', 'my-custom-test', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Command should succeed"
      assert_match(/mkdir -p '.*my-custom-test'/, stdout, "Should use custom name")
      assert_match(/cd '.*my-custom-test'/, stdout, "Should cd to custom name directory")
    end
  end

  def test_pr_with_multi_word_custom_name
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', 'my', 'test', 'name', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Command should succeed"
      assert_match(/mkdir -p '.*my test name'/, stdout, "Should use full multi-word custom name")
    end
  end

  # Test consistent directory naming (no longer using GitHub API for branch names)

  def test_pr_consistent_directory_naming
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'tobi/try#1', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Command should succeed"
      # Should use consistent pr-number format similar to clone repos
      assert_match(/2025-\d{2}-\d{2}-tobi-try-pr1/, stdout, "Should use consistent pr-number format")
    end
  end

  # Test error handling scenarios

  def test_pr_no_arguments_shows_interactive_selector
    # With no arguments, cd command shows interactive selector (not an error)
    stdout, stderr, status = run_cmd('cd', '--and-exit', '--path', '/tmp')
    
    assert_equal 0, status.exitstatus, "Should show interactive selector, not fail"
    # This test verifies that the cd command without arguments works as expected
  end

  def test_pr_invalid_format_fallbacks_to_search
    Dir.mktmpdir do |dir|
      # Invalid formats now fallback to search instead of erroring
      stdout, stderr, status = run_cmd('cd', 'invalid-format', '--and-exit', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should fallback to search, not fail"
      # This verifies that invalid PR formats are treated as search terms
    end
  end

  def test_pr_number_only_outside_git_repo
    Dir.mktmpdir do |non_git_dir|
      # Run command from within the non-git directory
      cmd = [RbConfig.ruby, @script_path, 'cd', '123', '--path', non_git_dir]
      stdout, stderr, status = Open3.capture3(*cmd, chdir: non_git_dir)
      
      assert_not_equal 0, status.exitstatus, "Command should fail"
      assert_match(/Error: PR number provided but not in a git repository/, stderr, "Should show git repo error")
      assert_match(/Either provide full PR reference \(owner\/repo#123\) or run from a git repository/, stderr, "Should show helpful suggestion")
    end
  end

  def test_malformed_pr_formats_fallback_to_search
    Dir.mktmpdir do |dir|
      # Malformed PR formats should fallback to interactive selector (not error)
      stdout, stderr, status = run_cmd('cd', 'invalid#format#too#many#hashes', '--and-exit', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should fallback to search, not fail"
      # Invalid PR formats are treated as search terms
    end
  end

  def test_non_numeric_pr_formats_fallback_to_search  
    Dir.mktmpdir do |dir|
      # Non-numeric PR formats should fallback to interactive selector (not error)
      stdout, stderr, status = run_cmd('cd', 'owner/repo#abc', '--and-exit', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should fallback to search, not fail"
      # Invalid PR formats are treated as search terms
    end
  end

  # Test script generation details

  def test_pr_script_structure
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', '--path', dir)
      
      # Verify the script structure matches expected pattern
      lines = stdout.strip.split(/\s*\\\s*\n\s*&& /)
      
      assert_match(/mkdir -p/, lines[0], "First command should be mkdir")
      assert_match(/echo.*Using.*git clone.*PR #123/, lines[1], "Second command should be informative echo")
      assert_match(/git clone/, lines[2], "Third command should be git clone")
      assert_match(/git fetch origin pull\/123\/head:pr-123/, lines[3], "Fourth command should fetch PR")
      assert_match(/touch/, lines[4], "Fifth command should be touch")
      assert_match(/cd/, lines[5], "Sixth command should be cd")
    end
  end

  def test_pr_echo_message_formatting
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', '--path', dir)
      
      assert_match(/Using.*git clone.*to create this trial from PR #123 in owner\/repo\./, stdout, 
                  "Should include informative message about PR being cloned")
    end
  end

  def test_pr_path_escaping
    Dir.mktmpdir do |base_dir|
      # Create a directory with spaces and special characters
      weird_path = File.join(base_dir, "path with spaces & special chars")
      FileUtils.mkdir_p(weird_path)
      
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', '--path', weird_path)
      
      assert_equal 0, status.exitstatus, "Command should succeed with special path"
      # Check that paths are properly quoted
      assert_match(/'.*path with spaces & special chars.*owner-repo-pr123'/, stdout, 
                  "Should properly quote paths with spaces")
    end
  end

  # Test integration with existing functionality

  def test_pr_help_integration
    stdout, stderr, status = run_cmd('--help')
    
    assert_equal 0, status.exitstatus, "Help should work"
    assert_match(/cd \[QUERY\] \[name\?\].*PR shorthand supported/, stdout, "Should show CD command supports PR shorthand")
    assert_match(/PR Examples:/, stdout, "Should have PR examples section")
    assert_match(/try owner\/repo#123/, stdout, "Should show owner/repo#123 example")
    assert_match(/try https:\/\/github\.com\/owner\/repo\/pull\/123/, stdout, "Should show full URL example")
    assert_match(/try 123 my-test/, stdout, "Should show custom name example")
  end

  def test_pr_url_detection_in_cd_command
    Dir.mktmpdir do |dir|
      # Test that PR URLs work with the cd command (auto-detection)
      stdout, stderr, status = run_cmd('cd', 'https://github.com/owner/repo/pull/123', '--path', dir)
      
      assert_equal 0, status.exitstatus, "CD command should auto-detect PR URL"
      assert_match(/mkdir -p '.*2025-\d{2}-\d{2}-owner-repo-pr123'/, stdout, "Should create PR directory")
      assert_match(/git clone 'https:\/\/github\.com\/owner\/repo\.git'/, stdout, "Should clone repo")
      assert_match(/git fetch origin pull\/123\/head:pr-123/, stdout, "Should fetch PR branch")
      assert_match(/PR #123 in owner\/repo/, stdout, "Should show PR info message")
    end
  end

  def test_pr_shorthand_detection_in_cd_command
    Dir.mktmpdir do |dir|
      # Test that owner/repo#123 format works with cd command
      stdout, stderr, status = run_cmd('cd', 'owner/repo#456', '--path', dir)
      
      assert_equal 0, status.exitstatus, "CD command should auto-detect PR shorthand"
      assert_match(/mkdir -p '.*2025-\d{2}-\d{2}-owner-repo-pr456'/, stdout, "Should create PR directory")
      assert_match(/PR #456 in owner\/repo/, stdout, "Should show PR info message")
    end
  end

  def test_pr_with_custom_name_via_cd_command
    Dir.mktmpdir do |dir|
      # Test that custom names work when PR URL is detected via cd command
      stdout, stderr, status = run_cmd('cd', 'https://github.com/owner/repo/pull/123', 'my-feature', '--path', dir)
      
      assert_equal 0, status.exitstatus, "CD command should handle PR URL with custom name"
      assert_match(/mkdir -p '.*my-feature'/, stdout, "Should use custom name")
      assert_no_match(/owner-repo-pr123/, stdout, "Should not use generated name")
    end
  end
end