require 'test/unit'
require 'open3'
require 'tmpdir'

class TestInitEval < Test::Unit::TestCase
  def run_cmd(env = {}, *args)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    stdout, stderr, status = Open3.capture3(env, *cmd)
    # Force encoding to UTF-8 to handle ANSI escape sequences
    [stdout.force_encoding('UTF-8'), stderr.force_encoding('UTF-8'), status]
  end

  def test_init_emits_bash_function_with_path
    Dir.mktmpdir do |dir|
      stdout, _stderr, status = run_cmd({'SHELL' => '/bin/bash'}, 'init', dir)
      assert(status.success?, 'init should exit successfully')
      assert_match(/try\(\) \{/, stdout)
      assert_match(/cd --path \"#{Regexp.escape(File.expand_path(dir))}\"/, stdout)
      assert_match(/case \"\$cmd\" in/m, stdout)
      assert_match(/\*" \&\& "\*\) eval \"\$cmd\" ;;/, stdout)
      # After the case, wrapper prints the command for shell-neutral usage.
      # Accept either printf or echo implementations.
      assert_match(/(printf %s \"\$cmd\"|echo \"\$cmd\")/, stdout)
    end
  end

  def test_init_emits_fish_function_with_path
    Dir.mktmpdir do |dir|
      stdout, _stderr, status = run_cmd({'SHELL' => '/usr/bin/fish'}, 'init', dir)
      assert(status.success?, 'init should exit successfully')
      assert_match(/^function try/m, stdout)
      assert_match(/cd --path \"#{Regexp.escape(File.expand_path(dir))}\"/, stdout)
      assert_match(/string collect\)/, stdout)
      assert_match(/string match -r ' \&\& ' -- \$cmd/, stdout)
    end
  end
end
