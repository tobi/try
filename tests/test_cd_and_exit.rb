require 'test/unit'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestCdAndExit < Test::Unit::TestCase
  def run_cmd(*args)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    Open3.capture3(*cmd)
  end

  def test_tui_renders_with_and_exit_and_type
    Dir.mktmpdir do |dir|
      # Create some sample project directories
      FileUtils.mkdir_p(File.join(dir, '2025-08-14-redis-connection-pool'))
      FileUtils.mkdir_p(File.join(dir, 'thread-pool'))

      stdout, stderr, status = run_cmd('cd', '--and-type', 'pool', '--and-exit', '--path', dir)
      combined = stdout.to_s + stderr.to_s
      # Strip ANSI escape codes and cursor controls for assertions
      clean = combined.gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, '')

      # Should contain the TUI header and the typed query
      assert_match(/Try Directory Selection/, clean)
      assert_match(/Search: pool/, clean)

      # Should list directories
      assert_match(/redis-connection-pool/, clean)
      assert_match(/thread-pool/, clean)

      # Should show create new line when input present
      assert_match(/Create new: pool/, clean)
    end
  end
end
