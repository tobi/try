require 'test/unit'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestWorktreeMerge < Test::Unit::TestCase
  def run_cmd(*args, **opts)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    Open3.capture3(*cmd, **opts)
  end

  def test_merge_fails_outside_git_repo
    Dir.mktmpdir do |tmpdir|
      _stdout, stderr, status = run_cmd('worktree', 'merge', chdir: tmpdir)
      assert_equal 1, status.exitstatus
      assert_match(/not in a git repository/i, stderr)
    end
  end

  def test_merge_fails_in_main_repo
    Dir.mktmpdir do |tmpdir|
      # Initialize a real git repo
      system('git', 'init', tmpdir, out: File::NULL, err: File::NULL)
      _stdout, stderr, status = run_cmd('worktree', 'merge', chdir: tmpdir)
      assert_equal 1, status.exitstatus
      assert_match(/not in a worktree/i, stderr)
    end
  end

  def test_merge_emits_correct_commands_for_named_branch
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
      
      # Make a commit in worktree
      File.write(File.join(worktree_dir, 'feature.txt'), 'feature')
      system('git', '-C', worktree_dir, 'add', '.', out: File::NULL, err: File::NULL)
      system('git', '-C', worktree_dir, 'commit', '-m', 'feature commit', out: File::NULL, err: File::NULL)
      
      # Run merge command
      stdout, _stderr, status = run_cmd('worktree', 'merge', chdir: worktree_dir)
      
      assert_equal 0, status.exitstatus
      assert_match(/cd '#{Regexp.escape(parent_repo)}'/, stdout)
      assert_match(/git merge --squash 'feature'/, stdout)
      assert_match(/git commit -m 'squash: merge feature'/, stdout)
      assert_match(/cd '#{Regexp.escape(worktree_dir)}'/, stdout)
    end
  end

  def test_merge_fails_with_uncommitted_changes
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
      
      # Create worktree
      system('git', '-C', parent_repo, 'worktree', 'add', worktree_dir, out: File::NULL, err: File::NULL)
      
      # Create uncommitted changes
      File.write(File.join(worktree_dir, 'uncommitted.txt'), 'uncommitted')
      
      # Run merge command - should fail
      _stdout, stderr, status = run_cmd('worktree', 'merge', chdir: worktree_dir)
      
      assert_equal 1, status.exitstatus
      assert_match(/uncommitted changes/i, stderr)
    end
  end
end
