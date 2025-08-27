require 'test/unit'
require 'open3'
require 'tmpdir'

class TestWorktreeCmd < Test::Unit::TestCase
  def run_cmd(*args)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    Open3.capture3(*cmd)
  end

  def test_worktree_dir_with_name
    Dir.mktmpdir do |tries|
      Dir.mktmpdir do |repo|
        FileUtils.mkdir_p(File.join(repo, '.git')) # simulate repo
        stdout, _stderr, _status = Open3.capture3(RbConfig.ruby, File.expand_path('../try.rb', __dir__), 'worktree', 'dir', 'xyz', '--path', tries, chdir: repo)
        assert_match(/mkdir -p '\S+\d{4}-\d{2}-\d{2}-xyz'/, stdout)
        assert_match(/worktree add --detach '\S+\d{4}-\d{2}-\d{2}-xyz'/, stdout)
        assert_match(/cd '\S+\d{4}-\d{2}-\d{2}-xyz'/, stdout)
      end
    end
  end
end
