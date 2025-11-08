require 'test/unit'
require 'open3'
require 'tmpdir'

class TestCloneEcho < Test::Unit::TestCase
  def run_cmd(*args)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    stdout, stderr, status = Open3.capture3(*cmd)
    # Force encoding to UTF-8 to handle ANSI escape sequences
    [stdout.force_encoding('UTF-8'), stderr.force_encoding('UTF-8'), status]
  end

  def test_clone_echo_message_present
    Dir.mktmpdir do |dir|
      stdout, _stderr, _status = run_cmd('clone', 'https://github.com/tobi/try.git', 'my-fork', '--path', dir)
      assert_match(/(?:printf %s|echo) .*git clone.*create this trial/i, stdout)
    end
  end

  def test_cd_url_echo_message_present
    Dir.mktmpdir do |dir|
      stdout, _stderr, _status = run_cmd('cd', 'https://github.com/tobi/try.git', 'my-fork', '--path', dir)
      assert_match(/(?:printf %s|echo) .*git clone.*create this trial/i, stdout)
    end
  end
end
