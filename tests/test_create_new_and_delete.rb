require 'test/unit'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestCreateNewAndDelete < Test::Unit::TestCase
  def run_cmd(*args)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    Open3.capture3(*cmd)
  end

  def test_create_new_generates_mkdir_script
    Dir.mktmpdir do |dir|
      stdout, _stderr, _status = run_cmd('cd', 'new-thing', '--and-keys', 'ENTER', '--path', dir)
      assert_match(/mkdir -p '\S+new-thing'/, stdout, 'should emit mkdir for create new')
      assert_match(/cd '\S+new-thing'/, stdout, 'should emit cd into created dir')
      assert_match(/\d{4}-\d{2}-\d{2}-new-thing/, stdout, 'should include date-prefixed new directory name')
    end
  end

  def test_delete_flow_confirms_and_deletes
    Dir.mktmpdir do |dir|
      # Seed a try directory
      name = '2025-08-14-delete-me'
      path = File.join(dir, name)
      FileUtils.mkdir_p(path)

      stdout, stderr, _status = run_cmd('cd', '--and-type', 'delete-me', '--and-keys', 'CTRL-D,ESC', '--and-confirm', 'YES', '--path', dir)
      combined = stdout.to_s + stderr.to_s
      clean = combined.gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, '')

      # Should show delete confirmation header at some point
      assert_match(/Delete Directory/, clean)
      # Should display a one-time status
      assert_match(/Deleted: #{Regexp.escape(name)}/, clean)
      # Ensure directory is gone
      refute(File.exist?(path), 'directory should be deleted')
    end
  end

  def test_delete_flow_cancel
    Dir.mktmpdir do |dir|
      name = '2025-08-14-keep-me'
      path = File.join(dir, name)
      FileUtils.mkdir_p(path)

      stdout, stderr, _status = run_cmd('cd', '--and-type', 'keep-me', '--and-keys', 'CTRL-D,ESC', '--and-confirm', 'NO', '--path', dir)
      combined = stdout.to_s + stderr.to_s
      clean = combined.gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, '')

      assert_match(/Delete Directory/, clean)
      assert_match(/Delete cancelled/, clean)
      assert(File.exist?(path), 'directory should still exist')
    end
  end
end
