require 'rake/testtask'

Rake::TestTask.new(:unit) do |t|
  t.libs << 'lib' << 'test'
  t.pattern = 'test/**/*_test.rb'
end

desc "Run shell spec compliance tests"
task :spec do
  sh "bash spec/tests/runner.sh ./try.rb"
end

desc "Run all tests (unit + spec)"
task test: [:unit, :spec]

task default: :test
