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
      tries = Dir.mktmpdir

      stdout, _stderr, _status = run_cmd(proj, 'cd', '.', '--path', tries)
      # Should include a git worktree step (conditional in sh)
      assert_match(/git .* worktree add --detach '\S+'/, stdout)
      # Should include date-prefixed cwd name
      base = File.basename(proj)
      assert_match(/\d{4}-\d{2}-\d{2}-#{Regexp.escape(base)}/, stdout)
    end
  end
end
