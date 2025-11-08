require 'test/unit'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestCreateNewAndDelete < Test::Unit::TestCase
  def run_cmd(*args)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    stdout, stderr, status = Open3.capture3(*cmd)
    # Force encoding to UTF-8 to handle ANSI escape sequences
    [stdout.force_encoding('UTF-8'), stderr.force_encoding('UTF-8'), status]
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

  def test_ctrl_j_k_navigation
    Dir.mktmpdir do |dir|
      # Create some test directories
      first_dir = '2025-08-14-first'
      second_dir = '2025-08-15-second'
      FileUtils.mkdir_p(File.join(dir, first_dir))
      FileUtils.mkdir_p(File.join(dir, second_dir))
      # Bump mtime of the first directory so it appears first by recency
      FileUtils.touch(File.join(dir, first_dir, '.mtime_bump'))

      # Test Ctrl-J (down) navigation - starts at index 0, goes to index 1 (second directory)
      stdout, _stderr, _status = run_cmd('cd', '--and-keys', 'CTRL-J,ENTER', '--path', dir)
      # Should select the second directory (2025-08-15-second)
      assert_match(/cd '#{Regexp.escape(File.join(dir, second_dir))}'/, stdout, 'Ctrl-J should navigate down to second directory')

      # Test Ctrl-K (up) navigation - go down then up, should be back to first directory
      stdout, _stderr, _status = run_cmd('cd', '--and-keys', 'CTRL-J,CTRL-K,ENTER', '--path', dir)
      # Should go down then up and select first directory
      assert_match(/cd '#{Regexp.escape(File.join(dir, first_dir))}'/, stdout, 'Ctrl-K should navigate up after going down')
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

  def test_delete_current_directory_gracefully
    Dir.mktmpdir do |dir|
      # Create a try directory
      name = '2025-08-14-delete-current'
      path = File.join(dir, name)
      FileUtils.mkdir_p(path)
      
      # Change to the directory we're about to delete
      original_dir = Dir.pwd
      begin
        Dir.chdir(path)
        
        # Now delete it - this should handle the case gracefully
        stdout, stderr, _status = run_cmd('cd', '--and-type', 'delete-current', '--and-keys', 'CTRL-D,ESC', '--and-confirm', 'YES', '--path', dir)
        combined = stdout.to_s + stderr.to_s
        clean = combined.gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, '')
        
        # Should show delete confirmation and success
        assert_match(/Delete Directory/, clean)
        assert_match(/Deleted: #{Regexp.escape(name)}/, clean)
        
        # Directory should be deleted
        refute(File.exist?(path), 'directory should be deleted')
        
        # We should not get getcwd errors - the process should have changed directory
        refute_match(/getcwd/, stderr, 'should not have getcwd errors')
        refute_match(/error retrieving current directory/, stderr, 'should not have directory retrieval errors')
      ensure
        # Try to change back, but if the directory was deleted, change to original
        begin
          Dir.chdir(original_dir)
        rescue
          Dir.chdir(Dir.home)
        end
      end
    end
  end
end
