require 'rake/testtask'
require 'tempfile'

RUBY_SOURCES = FileList['try.rb', 'lib/**/*.rb']

def spinel_cmd
  ENV.fetch('SPINEL', 'spinel')
end

def spinel_available?
  system('sh', '-c', 'command -v "$1" >/dev/null', '--', spinel_cmd)
end

Rake::TestTask.new(:unit) do |t|
  t.libs << 'lib' << 'test'
  t.pattern = 'test/**/*_test.rb'
end

desc "Check syntax with MRI and Spinel (warns if Spinel is missing)"
task :lint do
  RUBY_SOURCES.each do |file|
    sh 'ruby', '-c', file
  end

  unless spinel_available?
    warn "warning: spinel not found (#{spinel_cmd}); skipping Spinel syntax check"
    warn "warning: try must parse and run on both MRI Ruby and Spinel"
    next
  end

  RUBY_SOURCES.each do |file|
    Tempfile.create(['try-spinel-syntax', '.c']) do |tmp|
      sh spinel_cmd, '-c', file, '-o', tmp.path
    end
  end
end

desc "Run shell spec compliance tests"
task :spec do
  sh "bash spec/tests/runner.sh ./try.rb"
end

desc "Run all tests (lint + unit + spec)"
task test: [:lint, :unit, :spec]

task default: :test
