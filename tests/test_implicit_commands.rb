require 'test/unit'
require 'open3'
require 'tmpdir'

class TestImplicitCommands < Test::Unit::TestCase
  def setup
    @script_path = File.expand_path('../try.rb', __dir__)
  end

  def run_cmd(*args)
    cmd = [RbConfig.ruby, @script_path, *args]
    Open3.capture3(*cmd)
  end

  def test_implicit_pr_url_full
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('https://github.com/owner/repo/pull/123', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should handle PR URL without explicit cd command"
      assert_match(/owner-repo-pr123/, stdout, "Should generate correct directory name")
      assert_match(/git clone/, stdout, "Should clone repository")
      assert_match(/git fetch origin pull\/123\/head:pr-123/, stdout, "Should fetch PR")
    end
  end

  def test_implicit_pr_short_format
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('owner/repo#456', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should handle short PR format without explicit cd command"
      assert_match(/owner-repo-pr456/, stdout, "Should generate correct directory name")
      assert_match(/git clone/, stdout, "Should clone repository")
    end
  end

  def test_implicit_git_uri
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('https://github.com/tobi/try.git', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should handle git URI without explicit cd command"
      assert_match(/tobi-try/, stdout, "Should generate correct directory name")
      assert_match(/git clone/, stdout, "Should clone repository")
    end
  end

  def test_unknown_command_still_shows_help
    stdout, stderr, status = run_cmd('invalid-command')
    
    assert_not_equal 0, status.exitstatus, "Should fail for invalid commands"
    assert_match(/Unknown command: invalid-command/, stderr, "Should show unknown command error")
    # Note: help text goes to STDOUT, not STDERR
    combined_output = stdout + stderr
    assert_match(/try something!/, combined_output, "Should show help text")
  end

  def test_implicit_vs_explicit_cd_same_result
    Dir.mktmpdir do |dir|
      # Test implicit command (PR URL directly)
      stdout_implicit, _, status_implicit = run_cmd('owner/repo#789', '--path', dir)
      
      # Test explicit cd command
      stdout_explicit, _, status_explicit = run_cmd('cd', 'owner/repo#789', '--path', dir)
      
      assert_equal 0, status_implicit.exitstatus, "Implicit command should succeed"
      assert_equal 0, status_explicit.exitstatus, "Explicit cd command should succeed"
      
      # Both should produce equivalent results
      assert_match(/owner-repo-pr789/, stdout_implicit, "Implicit should generate correct directory")
      assert_match(/owner-repo-pr789/, stdout_explicit, "Explicit should generate correct directory")
    end
  end
end