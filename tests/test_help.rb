require 'test/unit'
require 'open3'

class TestHelp < Test::Unit::TestCase
  def run_cmd(*args)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    stdout, stderr, status = Open3.capture3(*cmd)
    # Force encoding to UTF-8 to handle ANSI escape sequences
    [stdout.force_encoding('UTF-8'), stderr.force_encoding('UTF-8'), status]
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
