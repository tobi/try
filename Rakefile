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

desc "Build concatenated dist/try.rb"
task :dist do
  sh 'make', 'dist'
end

desc "Check syntax with MRI and Spinel (warns if Spinel is missing)"
task :lint do
  RUBY_SOURCES.each do |file|
    sh 'ruby', '-c', file
  end

  sh 'make', 'dist/try.rb'
  sh 'ruby', '-c', 'dist/try.rb'

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

  Tempfile.create(['try-spinel-dist', '.c']) do |tmp|
    sh spinel_cmd, '-c', 'dist/try.rb', '-o', tmp.path
  end
end

desc "Run shell spec compliance tests (MRI source)"
task :spec do
  sh 'bash', 'spec/tests/runner.sh', './try.rb'
end

desc "Run shell spec compliance tests against dist/try.rb"
task :spec_dist do
  sh 'make', 'dist'
  sh 'bash', 'spec/tests/runner.sh', 'dist/try.rb'
end

desc "Emit dist/try.c from concat, compile dist/try, spec it, and compare with MRI"
task :spec_spinel do
  unless spinel_available?
    warn "warning: spinel not found (#{spinel_cmd}); skipping native spec + compare"
    next
  end

  sh 'make', 'native', "SPINEL=#{spinel_cmd}"
  sh 'bash', 'spec/tests/runner.sh', 'dist/try'
  sh 'bash', 'spec/tests/runner_and_compare.sh', 'dist/try.rb', 'dist/try'
end

desc "Run all tests (lint + unit + spec + dist spec; native spec+compare if Spinel is present)"
task test: [:lint, :unit, :spec, :spec_dist, :spec_spinel]

task default: :test
