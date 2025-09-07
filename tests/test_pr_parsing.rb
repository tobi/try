require 'test/unit'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestPrParsing < Test::Unit::TestCase
  def setup
    @script_path = File.expand_path('../try.rb', __dir__)
  end

  def run_cmd(*args)
    cmd = [RbConfig.ruby, @script_path, *args]
    Open3.capture3(*cmd)
  end

  def run_cmd_in_git_repo(*args)
    Dir.mktmpdir do |repo_dir|
      # Initialize a fake git repo with remote
      system("cd #{repo_dir} && git init >/dev/null 2>&1")
      system("cd #{repo_dir} && git remote add origin https://github.com/test-user/test-repo.git >/dev/null 2>&1")
      
      # Run command from within the git repo
      cmd = [RbConfig.ruby, @script_path, *args]
      Open3.capture3(*cmd, chdir: repo_dir)
    end
  end

  # Test URL parsing through actual command execution

  def test_owner_repo_format_parsing
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should parse owner/repo#123 format"
      assert_match(/owner\/repo/, stdout, "Should reference correct repository")
      assert_match(/123/, stdout, "Should reference correct PR number")
    end
  end

  def test_github_url_format_parsing
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'https://github.com/owner/repo/pull/456', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should parse GitHub URL format"
      assert_match(/owner\/repo/, stdout, "Should extract owner/repo from URL")
      assert_match(/456/, stdout, "Should extract PR number from URL")
    end
  end

  def test_number_only_format_in_git_repo
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd_in_git_repo('cd', '789', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should parse number-only format in git repo"
      assert_match(/test-user\/test-repo/, stdout, "Should detect repo from git remote")
      assert_match(/789/, stdout, "Should use provided PR number")
    end
  end

  def test_number_only_format_outside_git_repo
    Dir.mktmpdir do |dir|
      # Run command from within the non-git directory
      cmd = [RbConfig.ruby, @script_path, 'cd', '123', '--path', dir]
      stdout, stderr, status = Open3.capture3(*cmd, chdir: dir)
      
      assert_not_equal 0, status.exitstatus, "Should fail when not in git repo"
      assert_match(/not in a git repository/, stderr, "Should show helpful error message")
    end
  end

  # Test various invalid format rejections

  def test_invalid_formats_fallback_to_search
    invalid_formats = [
      'invalid-format',
      'owner/repo',  # missing PR number
      'owner/repo#',  # empty PR number
      'owner/repo#abc',  # non-numeric PR number
      'https://gitlab.com/owner/repo/pull/123',  # non-GitHub URL
      'owner#123',  # missing slash
    ]

    invalid_formats.each do |format|
      Dir.mktmpdir do |dir|
        stdout, stderr, status = run_cmd('cd', format, '--and-exit', '--path', dir)
        
        assert_equal 0, status.exitstatus, "Should fallback to search for invalid format: #{format}"
        # Invalid PR formats now fallback to interactive selector instead of erroring
      end
    end
  end

  # Test edge cases

  def test_large_pr_numbers
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'owner/repo#999999', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should handle large PR numbers"
      assert_match(/999999/, stdout, "Should preserve large PR number")
    end
  end

  def test_http_urls_supported
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'http://github.com/owner/repo/pull/123', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should support http URLs"
      assert_match(/owner\/repo/, stdout, "Should parse http URLs correctly")
    end
  end

  # Test directory name generation patterns

  def test_directory_name_generation
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', '--path', dir)
      
      # Should include today's date
      today = Time.now.strftime("%Y-%m-%d")
      assert_match(/#{today}/, stdout, "Should include today's date in directory name")
      
      # Should include owner and repo
      assert_match(/owner-repo/, stdout, "Should include owner and repo in directory name")
      
      # Should include PR number in consistent format
      assert_match(/pr123/, stdout, "Should include PR number in directory name")
      
      # Verify exact format matches expected pattern
      assert_match(/#{today}-owner-repo-pr123/, stdout, "Should use exact expected format")
    end
  end

  def test_custom_name_overrides_generation
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', 'my-custom-name', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should accept custom name"
      assert_match(/my-custom-name/, stdout, "Should use custom name in paths")
      assert_no_match(/owner-repo/, stdout, "Should not use generated name when custom provided")
    end
  end

  # Test script structure

  def test_generated_script_structure
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', '--path', dir)
      
      # Verify proper script structure
      assert_match(/mkdir -p/, stdout, "Should create directory")
      assert_match(/git clone/, stdout, "Should clone repository")
      assert_match(/git fetch origin pull\/123\/head:pr-123/, stdout, "Should fetch PR branch")
      assert_match(/git checkout pr-123/, stdout, "Should checkout PR branch")
      assert_match(/touch/, stdout, "Should touch directory")
      assert_match(/cd/, stdout, "Should change to directory")
    end
  end

  def test_proper_shell_escaping
    Dir.mktmpdir do |base_dir|
      # Test with a path that has spaces and special characters
      weird_path = File.join(base_dir, "path with spaces & special chars")
      FileUtils.mkdir_p(weird_path)
      
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', '--path', weird_path)
      
      assert_equal 0, status.exitstatus, "Should handle paths with special characters"
      # Check that all paths are properly quoted
      assert_match(/'.*path with spaces & special chars.*'/, stdout, "Should quote paths with spaces")
    end
  end

  # Test informational messages

  def test_informational_echo_message
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'owner/repo#123', '--path', dir)
      
      assert_match(/Using.*git clone.*PR #123 in owner\/repo/, stdout, 
                  "Should include informative message about the PR being cloned")
    end
  end
end