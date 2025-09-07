require 'test/unit'
require 'open3'
require 'tmpdir'

class TestForkPrHandling < Test::Unit::TestCase
  def setup
    @script_path = File.expand_path('../try.rb', __dir__)
  end

  def run_cmd(*args)
    cmd = [RbConfig.ruby, @script_path, *args]
    Open3.capture3(*cmd)
  end

  def test_fork_pr_detection
    Dir.mktmpdir do |dir|
      # Test a known fork PR: jellydn/minui-artwork-scraper-pak -> josegonzalez/minui-artwork-scraper-pak
      stdout, stderr, status = run_cmd('cd', 'https://github.com/josegonzalez/minui-artwork-scraper-pak/pull/33', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should handle fork PR successfully"
      
      # Should clone from the fork repository (jellydn), not the base (josegonzalez)
      assert_match(/git clone 'https:\/\/github\.com\/jellydn\/minui-artwork-scraper-pak\.git'/, stdout, 
                  "Should clone from fork repository")
      
      # Should checkout the fork branch, not use PR fetch
      assert_match(/git checkout huynhdung\/reimplement-matching-as-a-golang-binary/, stdout,
                  "Should checkout fork branch directly")
      
      # Should still use base repo name for directory
      assert_match(/josegonzalez-minui-artwork-scraper-pak-pr33/, stdout,
                  "Should use base repository for directory naming")
    end
  end

  def test_regular_pr_fallback
    Dir.mktmpdir do |dir|
      # Test with non-existent PR that should fallback to regular PR handling
      stdout, stderr, status = run_cmd('cd', 'tobi/try#999', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should handle regular PR fallback"
      
      # Should clone from the base repository
      assert_match(/git clone 'https:\/\/github\.com\/tobi\/try\.git'/, stdout,
                  "Should clone from base repository for regular PR")
      
      # Should use PR fetch method, not direct branch checkout
      assert_match(/git fetch origin pull\/999\/head:pr-999/, stdout,
                  "Should use PR fetch method for regular PR")
    end
  end

  def test_fork_pr_with_custom_name
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_cmd('cd', 'https://github.com/josegonzalez/minui-artwork-scraper-pak/pull/33', 'my-test', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should handle fork PR with custom name"
      
      # Should use custom name for directory
      assert_match(/my-test/, stdout, "Should use custom name for directory")
      
      # Should still clone from fork
      assert_match(/git clone 'https:\/\/github\.com\/jellydn\/minui-artwork-scraper-pak\.git'/, stdout,
                  "Should still clone from fork with custom name")
    end
  end

  def test_implicit_fork_pr_command
    Dir.mktmpdir do |dir|
      # Test implicit command (PR URL without cd)
      stdout, stderr, status = run_cmd('https://github.com/josegonzalez/minui-artwork-scraper-pak/pull/33', '--path', dir)
      
      assert_equal 0, status.exitstatus, "Should handle implicit fork PR command"
      assert_match(/git clone 'https:\/\/github\.com\/jellydn\/minui-artwork-scraper-pak\.git'/, stdout,
                  "Should clone from fork for implicit command")
    end
  end
end