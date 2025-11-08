require 'test/unit'
require 'open3'
require 'tmpdir'

class TestCloneAndUrlName < Test::Unit::TestCase
  def run_cmd(*args)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    stdout, stderr, status = Open3.capture3(*cmd)
    # Force encoding to UTF-8 to handle ANSI escape sequences
    [stdout.force_encoding('UTF-8'), stderr.force_encoding('UTF-8'), status]
  end

  def test_clone_generates_script
    Dir.mktmpdir do |dir|
      stdout, _stderr, _status = run_cmd('clone', 'https://github.com/tobi/try.git', 'my-fork', '--path', dir)
      assert_match(/mkdir -p '\S+my-fork'/, stdout)
      assert_match(/git clone 'https:\/\/github\.com\/tobi\/try\.git' '\S+my-fork'/, stdout)
      assert_match(/cd '\S+my-fork'/, stdout)
    end
  end

  def test_cd_url_shorthand_with_name
    Dir.mktmpdir do |dir|
      stdout, _stderr, _status = run_cmd('cd', 'https://github.com/tobi/try.git', 'my-fork', '--path', dir)
      assert_match(/git clone 'https:\/\/github\.com\/tobi\/try\.git' '\S+my-fork'/, stdout)
      assert_match(/my-fork/, stdout, 'should use the provided custom name in path')
    end
  end

  def test_cd_clone_wrapper_emits_clone_script
    Dir.mktmpdir do |dir|
      stdout, _stderr, _status = run_cmd('cd', 'clone', 'https://github.com/tobi/try.git', 'my-fork', '--path', dir)
      assert_match(/mkdir -p '\S+my-fork'/, stdout)
      assert_match(/git clone 'https:\/\/github\.com\/tobi\/try\.git' '\S+my-fork'/, stdout)
      assert_match(/cd '\S+my-fork'/, stdout)
    end
  end
end
