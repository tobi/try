require 'test/unit'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestWorktreeDrop < Test::Unit::TestCase
  def run_cmd(*args, **opts)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    Open3.capture3(*cmd, **opts)
  end

  def test_drop_fails_outside_git_repo
    Dir.mktmpdir do |tmpdir|
      _stdout, stderr, status = run_cmd('worktree', 'drop', chdir: tmpdir)
      assert_equal 1, status.exitstatus
      assert_match(/not in a git repository/i, stderr)
    end
  end

  def test_drop_fails_in_main_repo
    Dir.mktmpdir do |tmpdir|
      # Initialize a real git repo
      system('git', 'init', tmpdir, out: File::NULL, err: File::NULL)
      _stdout, stderr, status = run_cmd('worktree', 'drop', chdir: tmpdir)
      assert_equal 1, status.exitstatus
      assert_match(/not in a worktree/i, stderr)
    end
  end

  def test_drop_emits_correct_commands_for_named_branch
    Dir.mktmpdir do |tmpdir|
      parent_repo = File.join(tmpdir, 'parent')
      worktree_dir = File.join(tmpdir, 'worktree')
      
      # Create parent repo
      FileUtils.mkdir_p(parent_repo)
      system('git', 'init', parent_repo, out: File::NULL, err: File::NULL)
      system('git', '-C', parent_repo, 'config', 'user.email', 'test@test.com', out: File::NULL, err: File::NULL)
      system('git', '-C', parent_repo, 'config', 'user.name', 'Test', out: File::NULL, err: File::NULL)
      
      # Create initial commit
      File.write(File.join(parent_repo, 'test.txt'), 'initial')
      system('git', '-C', parent_repo, 'add', '.', out: File::NULL, err: File::NULL)
      system('git', '-C', parent_repo, 'commit', '-m', 'initial', out: File::NULL, err: File::NULL)
      
      # Create worktree with a branch
      system('git', '-C', parent_repo, 'worktree', 'add', '-b', 'feature', worktree_dir, out: File::NULL, err: File::NULL)
      
      # Run drop command
      stdout, _stderr, status = run_cmd('worktree', 'drop', chdir: worktree_dir)
      
      assert_equal 0, status.exitstatus
      assert_match(/cd '#{Regexp.escape(parent_repo)}'/, stdout)
      assert_match(/git worktree remove --force '#{Regexp.escape(worktree_dir)}'/, stdout)
      assert_match(/git branch -D 'feature'/, stdout)
      assert_match(/Removed worktree and deleted branch feature/, stdout)
    end
  end

  def test_drop_emits_correct_commands_for_detached_head
    Dir.mktmpdir do |tmpdir|
      parent_repo = File.join(tmpdir, 'parent')
      worktree_dir = File.join(tmpdir, 'worktree')
      
      # Create parent repo
      FileUtils.mkdir_p(parent_repo)
      system('git', 'init', parent_repo, out: File::NULL, err: File::NULL)
      system('git', '-C', parent_repo, 'config', 'user.email', 'test@test.com', out: File::NULL, err: File::NULL)
      system('git', '-C', parent_repo, 'config', 'user.name', 'Test', out: File::NULL, err: File::NULL)
      
      # Create initial commit
      File.write(File.join(parent_repo, 'test.txt'), 'initial')
      system('git', '-C', parent_repo, 'add', '.', out: File::NULL, err: File::NULL)
      system('git', '-C', parent_repo, 'commit', '-m', 'initial', out: File::NULL, err: File::NULL)
      
      # Create worktree with detached HEAD (no branch)
      system('git', '-C', parent_repo, 'worktree', 'add', '--detach', worktree_dir, out: File::NULL, err: File::NULL)
      
      # Run drop command
      stdout, _stderr, status = run_cmd('worktree', 'drop', chdir: worktree_dir)
      
      assert_equal 0, status.exitstatus
      assert_match(/cd '#{Regexp.escape(parent_repo)}'/, stdout)
      assert_match(/git worktree remove --force '#{Regexp.escape(worktree_dir)}'/, stdout)
      refute_match(/git branch -D/, stdout)  # Should not try to delete branch
      assert_match(/Removed worktree \(detached HEAD\)/, stdout)
    end
  end
end
