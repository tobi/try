require 'test/unit'
require 'open3'
require 'tmpdir'

class TestCloneEcho < Test::Unit::TestCase
  def run_cmd(*args)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    Open3.capture3(*cmd)
  end

  def test_clone_echo_message_present
    Dir.mktmpdir do |dir|
      stdout, _stderr, _status = run_cmd('clone', 'https://github.com/tobi/try.git', 'my-fork', '--path', dir)
      assert_match(/printf %s .*git clone.*create this trial/i, stdout)
    end
  end

  def test_cd_url_echo_message_present
    Dir.mktmpdir do |dir|
      stdout, _stderr, _status = run_cmd('cd', 'https://github.com/tobi/try.git', 'my-fork', '--path', dir)
      assert_match(/printf %s .*git clone.*create this trial/i, stdout)
    end
  end
end

