require 'test/unit'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestWorktreeDot < Test::Unit::TestCase
  def run_cmd(cwd, *args)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    Open3.capture3(*cmd, chdir: cwd)
  end

  def test_try_dot_emits_worktree_step_and_uses_cwd_name
    Dir.mktmpdir do |dir|
      # Create a fake project directory name
      proj = File.join(dir, 'myproj')
      FileUtils.mkdir_p(proj)
      FileUtils.mkdir_p(File.join(proj, '.git')) # simulate git repo
      tries = Dir.mktmpdir

      # also support path-relative invocation
      stdout, _stderr, _status = run_cmd(proj, 'cd', './', '--path', tries)
      # Should include a git worktree step (conditional in sh)
      assert_match(/git .* worktree add --detach '\S+'/, stdout)
      # Should echo intent to use worktree
      assert_match(/(?:printf %s|echo) .*git worktree.*create this trial/i, stdout)
      # Should include date-prefixed cwd name
      base = File.basename(proj)
      assert_match(/\d{4}-\d{2}-\d{2}-#{Regexp.escape(base)}/, stdout)
    end
  end

  def test_try_dot_with_name_overrides_basename
    Dir.mktmpdir do |dir|
      proj = File.join(dir, 'myproj')
      FileUtils.mkdir_p(proj)
      FileUtils.mkdir_p(File.join(proj, '.git')) # simulate git repo
      tries = Dir.mktmpdir

      stdout, _stderr, _status = run_cmd(proj, 'cd', '.', 'custom-name', '--path', tries)
      assert_match(/worktree add --detach '\S+custom-name'/, stdout)
      assert_match(/(?:printf %s|echo) .*git worktree.*create this trial/i, stdout)
      assert_match(/\d{4}-\d{2}-\d{2}-custom-name/, stdout)
    end
  end

  def test_try_dot_without_git_skips_worktree
    Dir.mktmpdir do |dir|
      proj = File.join(dir, 'plain')
      FileUtils.mkdir_p(proj)
      tries = Dir.mktmpdir
      stdout, _stderr, _status = run_cmd(proj, 'cd', '.', '--path', tries)
      refute_match(/worktree add --detach/, stdout)
      refute_match(/(?:printf %s|echo) .*git worktree.*create this trial/i, stdout)
      assert_match(/mkdir -p '\S+\d{4}-\d{2}-\d{2}-plain'/, stdout)
    end
  end
end
