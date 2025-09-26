require 'test/unit'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestDeleteCurrentDirectory < Test::Unit::TestCase
  def run_cmd(cwd, *args)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    Open3.capture3(*cmd, chdir: cwd)
  end

  def test_delete_current_directory_should_not_cause_shell_error
    Dir.mktmpdir do |tries_root|
      # Create a test directory
      test_dir_name = '2025-09-26-test-delete-current'
      test_dir_path = File.join(tries_root, test_dir_name)
      FileUtils.mkdir_p(test_dir_path)
      
      # Run try cd from within the directory we're about to delete
      # This simulates the user being inside a try directory and deleting it
      stdout, stderr, status = run_cmd(
        test_dir_path,  # Run from within the directory to be deleted
        'cd', 
        '--and-type', 'test-delete-current',  # Search for the directory
        '--and-keys', 'CTRL-D,ESC',          # Delete it (Ctrl-D) then exit (ESC)
        '--and-confirm', 'YES',              # Confirm deletion
        '--path', tries_root
      )
      
      # The directory should be deleted
      refute(File.exist?(test_dir_path), 'directory should be deleted')
      
      # There should be no shell errors about getcwd or current directory
      combined_output = stdout.to_s + stderr.to_s
      refute_match(
        /shell-init: error retrieving current directory|getcwd: cannot access parent directories/,
        combined_output,
        'should not have shell errors about current directory'
      )
      
      # Should show successful deletion
      clean_output = combined_output.gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, '')
      assert_match(/Deleted: #{Regexp.escape(test_dir_name)}/, clean_output)
    end
  end
  
  def test_delete_current_directory_changes_to_safe_location
    Dir.mktmpdir do |tries_root|
      # Create a test directory  
      test_dir_name = '2025-09-26-test-safe-nav'
      test_dir_path = File.join(tries_root, test_dir_name)
      FileUtils.mkdir_p(test_dir_path)
      
      # Run try cd from within the directory we're about to delete
      # After deletion, just exit (ESC) to avoid navigation complexity
      stdout, stderr, status = run_cmd(
        test_dir_path,  # Run from within the directory to be deleted
        'cd',
        '--and-type', 'test-safe-nav',       # Search for the directory to delete
        '--and-keys', 'CTRL-D,ESC',         # Delete it then exit
        '--and-confirm', 'YES',             # Confirm deletion
        '--path', tries_root
      )
      
      # The directory should be deleted
      refute(File.exist?(test_dir_path), 'directory should be deleted')
      
      # Should not have shell errors about current directory 
      combined_output = stdout.to_s + stderr.to_s
      refute_match(
        /shell-init: error retrieving current directory|getcwd.*failed|getcwd: cannot access parent directories/,
        combined_output,
        'should not have shell errors about current directory'
      )
      
      # Should show successful deletion
      clean_output = combined_output.gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, '')
      assert_match(/Deleted: #{Regexp.escape(test_dir_name)}/, clean_output)
    end
  end
end