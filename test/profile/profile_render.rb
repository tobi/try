#!/usr/bin/env ruby
# frozen_string_literal: true

# Profile try.rb rendering performance
# Usage: bundle exec ruby test/profile/profile_render.rb

require 'ruby-prof'
require 'fileutils'
require_relative '../../try.rb'

module ProfileHelpers
  def self.allocations
    x = GC.stat(:total_allocated_objects)
    yield
    GC.stat(:total_allocated_objects) - x
  end
end

# Create test data directory with many entries
TEST_PATH = '/tmp/profile_tries'
FileUtils.rm_rf(TEST_PATH)
FileUtils.mkdir_p(TEST_PATH)

# Create 100 test directories
100.times do |i|
  dir_name = "2024-#{format('%02d', (i % 12) + 1)}-#{format('%02d', (i % 28) + 1)}-project-#{i}-#{%w[api web cli lib].sample}"
  FileUtils.mkdir_p(File.join(TEST_PATH, dir_name))
end

puts "Test directory created with 100 entries"
puts

# Warm up
selector = TrySelector.new("", base_path: TEST_PATH, test_render_once: true, test_no_cls: true)
tries = selector.send(:get_tries)
5.times { selector.send(:render, tries) }

# Measure allocations per render
allocs = ProfileHelpers.allocations do
  selector.send(:render, tries)
end
puts "Allocations per render: #{allocs}"
puts

# Profile 50 render cycles
puts "Profiling 50 render cycles..."
RubyProf::Profile.profile do |profile|
  50.times do
    selector.send(:render, tries)
  end

  result = profile.stop

  puts
  puts "=" * 70
  puts "FLAT PROFILE (methods taking >1% of time)"
  puts "=" * 70
  printer = RubyProf::FlatPrinter.new(result)
  printer.print(STDOUT, min_percent: 1)

  puts
  puts "=" * 70
  puts "GRAPH PROFILE (call relationships)"
  puts "=" * 70
  graph_printer = RubyProf::GraphPrinter.new(result)
  graph_printer.print(STDOUT, min_percent: 2)
end

puts
puts "Profile complete!"
