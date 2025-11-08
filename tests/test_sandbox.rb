require 'test/unit'
require 'open3'
require 'tmpdir'
require 'fileutils'

class TestSandbox < Test::Unit::TestCase
  def run_cmd(*args, **opts)
    cmd = [RbConfig.ruby, File.expand_path('../try.rb', __dir__), *args]
    Open3.capture3(*cmd, **opts)
  end

  def test_sandbox_fails_without_compose_file
    Dir.mktmpdir do |tmpdir|
      _stdout, stderr, status = run_cmd('sandbox', chdir: tmpdir)
      assert_equal 1, status.exitstatus
      assert_match(/no \.toolkami\/docker-compose\.yml found/i, stderr)
    end
  end

  def test_sandbox_run_emits_correct_command
    Dir.mktmpdir do |tmpdir|
      # Create .toolkami directory and docker-compose.yml
      toolkami_dir = File.join(tmpdir, '.toolkami')
      FileUtils.mkdir_p(toolkami_dir)
      
      compose_content = <<~YAML
        services:
          app:
            image: ruby:3.0
            volumes:
              - .:/workspace
      YAML
      
      File.write(File.join(toolkami_dir, 'docker-compose.yml'), compose_content)
      
      # Mock docker availability by setting PATH to include a fake docker
      # For this test, we'll just check the output pattern
      # The actual docker check will fail, but we can verify the command structure
      
      # Skip this test if docker is not available
      unless system('command -v docker >/dev/null 2>&1')
        omit "Docker not available for testing"
      end
      
      stdout, _stderr, status = run_cmd('sandbox', chdir: tmpdir)
      
      assert_equal 0, status.exitstatus
      assert_match(/cd '#{Regexp.escape(tmpdir)}'/, stdout)
      assert_match(/docker compose -f \.toolkami\/docker-compose\.yml run --rm app/, stdout)
    end
  end

  def test_sandbox_build_emits_correct_command
    Dir.mktmpdir do |tmpdir|
      # Create .toolkami directory and docker-compose.yml
      toolkami_dir = File.join(tmpdir, '.toolkami')
      FileUtils.mkdir_p(toolkami_dir)
      
      compose_content = <<~YAML
        services:
          myservice:
            build: .
      YAML
      
      File.write(File.join(toolkami_dir, 'docker-compose.yml'), compose_content)
      
      unless system('command -v docker >/dev/null 2>&1')
        omit "Docker not available for testing"
      end
      
      stdout, _stderr, status = run_cmd('sandbox', 'build', chdir: tmpdir)
      
      assert_equal 0, status.exitstatus
      assert_match(/cd '#{Regexp.escape(tmpdir)}'/, stdout)
      assert_match(/docker compose -f \.toolkami\/docker-compose\.yml build myservice/, stdout)
    end
  end

  def test_sandbox_build_with_flags_emits_correct_command
    Dir.mktmpdir do |tmpdir|
      # Create .toolkami directory and docker-compose.yml
      toolkami_dir = File.join(tmpdir, '.toolkami')
      FileUtils.mkdir_p(toolkami_dir)
      
      compose_content = <<~YAML
        services:
          web:
            build: .
      YAML
      
      File.write(File.join(toolkami_dir, 'docker-compose.yml'), compose_content)
      
      unless system('command -v docker >/dev/null 2>&1')
        omit "Docker not available for testing"
      end
      
      stdout, _stderr, status = run_cmd('sandbox', 'build', '--no-cache', chdir: tmpdir)
      
      assert_equal 0, status.exitstatus
      assert_match(/cd '#{Regexp.escape(tmpdir)}'/, stdout)
      assert_match(/docker compose -f \.toolkami\/docker-compose\.yml build --no-cache web/, stdout)
    end
  end

  def test_sandbox_exec_emits_correct_command
    Dir.mktmpdir do |tmpdir|
      # Create .toolkami directory and docker-compose.yml
      toolkami_dir = File.join(tmpdir, '.toolkami')
      FileUtils.mkdir_p(toolkami_dir)
      
      compose_content = <<~YAML
        services:
          app:
            image: ruby:3.0
      YAML
      
      File.write(File.join(toolkami_dir, 'docker-compose.yml'), compose_content)
      
      unless system('command -v docker >/dev/null 2>&1')
        omit "Docker not available for testing"
      end
      
      stdout, _stderr, status = run_cmd('sandbox', 'exec', chdir: tmpdir)
      
      assert_equal 0, status.exitstatus
      assert_match(/cd '#{Regexp.escape(tmpdir)}'/, stdout)
      assert_match(/docker compose -f \.toolkami\/docker-compose\.yml exec -it app bash/, stdout)
    end
  end

  def test_sandbox_exec_with_command_emits_correct_command
    Dir.mktmpdir do |tmpdir|
      # Create .toolkami directory and docker-compose.yml
      toolkami_dir = File.join(tmpdir, '.toolkami')
      FileUtils.mkdir_p(toolkami_dir)
      
      compose_content = <<~YAML
        services:
          app:
            image: node:18
      YAML
      
      File.write(File.join(toolkami_dir, 'docker-compose.yml'), compose_content)
      
      unless system('command -v docker >/dev/null 2>&1')
        omit "Docker not available for testing"
      end
      
      stdout, _stderr, status = run_cmd('sandbox', 'exec', 'npm', 'test', chdir: tmpdir)
      
      assert_equal 0, status.exitstatus
      assert_match(/cd '#{Regexp.escape(tmpdir)}'/, stdout)
      assert_match(/docker compose -f \.toolkami\/docker-compose\.yml exec -it app npm test/, stdout)
    end
  end

  def test_sandbox_parses_service_name_from_compose_file
    Dir.mktmpdir do |tmpdir|
      # Create .toolkami directory and docker-compose.yml with custom service name
      toolkami_dir = File.join(tmpdir, '.toolkami')
      FileUtils.mkdir_p(toolkami_dir)
      
      compose_content = <<~YAML
        services:
          custom-service-name:
            image: alpine:latest
      YAML
      
      File.write(File.join(toolkami_dir, 'docker-compose.yml'), compose_content)
      
      unless system('command -v docker >/dev/null 2>&1')
        omit "Docker not available for testing"
      end
      
      stdout, _stderr, status = run_cmd('sandbox', chdir: tmpdir)
      
      assert_equal 0, status.exitstatus
      assert_match(/docker compose -f \.toolkami\/docker-compose\.yml run --rm custom-service-name/, stdout)
    end
  end
end
