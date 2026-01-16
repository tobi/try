# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "../lib/tui"

class TuiTestCase < Minitest::Test
  include Tui::Helpers
  def setup
    super
    @colors_were_enabled = Tui.colors_enabled?
  end

  def teardown
    Tui.colors_enabled = @colors_were_enabled
    super
  end

  def enable_colors!
    Tui.enable_colors!
  end

  def disable_colors!
    Tui.disable_colors!
  end

  def string_io
    StringIO.new
  end

  def build_screen(width: 40, height: 5, io: string_io)
    Tui::Screen.new(io: io, width: width, height: height)
  end
end
