require 'test/unit'
require 'open3'

class TestHelp < Test::Unit::TestCase
  def run_cmd(*args)
    cmd = [RbConfig.ruby, File.expand_path('../tryout.rb', __dir__), *args]
    Open3.capture3(*cmd)
  end

  def test_help_flag_prints_usage
    stdout, _stderr, _status = run_cmd('--help')
    assert(_status.success?, 'expected --help to exit successfully')
    assert_match(/Usage:/i, stdout, 'help should print usage to stdout')
  end

  def test_no_args_prints_usage
    stdout, _stderr, _status = run_cmd
    assert_match(/Usage:/i, stdout, 'running without args should print usage')
  end
end
