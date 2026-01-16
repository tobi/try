# frozen_string_literal: true

require_relative "test_helper"

class TuiColorToggleTest < TuiTestCase
  def test_colors_can_be_toggled
    enable_colors!
    assert Tui.colors_enabled?
    Tui.disable_colors!
    refute Tui.colors_enabled?
    Tui.enable_colors!
    assert Tui.colors_enabled?
  end
end

class TuiTextTest < TuiTestCase
  def test_wrap_returns_blank_for_empty_input
    disable_colors!
    assert_equal "", Tui::Text.wrap("", "pre", "post")
    assert_equal "", Tui::Text.wrap(nil, "pre", "post")
  end

  def test_bold_respects_color_toggle
    enable_colors!
    wrapped = Tui::Text.bold("Hi")
    assert_includes wrapped, Tui::ANSI::BOLD
    disable_colors!
    assert_equal "Hi", Tui::Text.bold("Hi")
  end

  def test_dim_wraps_with_palette
    enable_colors!
    wrapped = Tui::Text.dim("meta")
    assert_includes wrapped, Tui::Palette::MUTED
  end

  def test_accent_and_highlight_helpers
    enable_colors!
    assert_includes Tui::Text.accent("wow"), Tui::Palette::ACCENT
    assert_includes Tui::Text.highlight("hit"), Tui::Palette::MATCH
  end
end

class TuiMetricsTest < TuiTestCase
  def test_visible_width_counts_wide_characters
    # We only support emoji as wide chars (not CJK)
    text = "a📁b"  # 📁 = width 2
    assert_equal 4, Tui::Metrics.visible_width(text)
  end

  def test_visible_width_ignores_escape_sequences
    enable_colors!
    colored = Tui::Text.bold("abc")
    assert_equal 3, Tui::Metrics.visible_width(colored)
  end

  def test_truncate_preserves_escape_sequences
    enable_colors!
    colored = Tui::Text.bold("abcdefghij")
    truncated = Tui::Metrics.truncate(colored, 6)
    assert_includes truncated, Tui::ANSI::BOLD
    assert truncated.end_with?("…"), "Expected overflow ellipsis"
    assert_equal 6, Tui::Metrics.visible_width(truncated)
  end

  def test_wide_predicate
    # We only support emoji as wide chars (📁 etc), not CJK
    assert Tui::Metrics.wide?("📁")
    refute Tui::Metrics.wide?("k")
    refute Tui::Metrics.wide?("→")
  end
end

class TuiANSITest < TuiTestCase
  def test_fg_bg_and_move_col_render_codes
    assert_equal "\e[38;5;42m", Tui::ANSI.fg(42)
    assert_equal "\e[48;5;42m", Tui::ANSI.bg(42)
    assert_equal "\e[10G", Tui::ANSI.move_col(10)
  end
end

class SegmentWriterTest < TuiTestCase
  def test_write_chains_and_skips_empty_text
    writer = Tui::SegmentWriter.new
    writer.write(nil).write("")
    writer.write("foo").write("bar")
    assert_equal "foobar", writer.to_s
  end

  def test_write_dim_uses_text_helpers
    disable_colors!
    writer = Tui::SegmentWriter.new
    writer.write_dim("meta")
    assert_equal "meta", writer.to_s
  end

  def test_write_bold_and_highlight
    enable_colors!
    writer = Tui::SegmentWriter.new
    writer.write_bold("B")
    writer.write_highlight("H")
    output = writer.to_s
    assert_includes output, Tui::ANSI::BOLD
    assert_includes output, Tui::Palette::MATCH
  end

  def test_fill_fills_remaining_width
    writer = Tui::SegmentWriter.new
    writer.write("ab")
    writer.write(fill("-"))
    # Fill uses width - 1 to avoid terminal wrapping
    assert_equal "ab--", writer.to_s(width: 5)
  end

  def test_fill_supports_styles
    enable_colors!
    writer = Tui::SegmentWriter.new
    writer.write_dim(fill("-"))
    rendered = writer.to_s(width: 4)
    assert_includes rendered, Tui::Palette::MUTED
    # Fill uses width - 1 to avoid terminal wrapping
    assert_equal 3, Tui::Metrics.visible_width(rendered)
  end
end

class InputFieldTest < TuiTestCase
  def test_placeholder_renders_dimmed
    disable_colors!
    field = Tui::InputField.new(placeholder: "Search", text: "")
    assert_equal "Search", field.to_s
  end

  def test_text_renders_cursor_block
    enable_colors!
    field = Tui::InputField.new(placeholder: "", text: "hello", cursor: 1)
    rendered = field.to_s
    assert_includes rendered, Tui::Palette::INPUT_CURSOR_ON
    assert_includes rendered, Tui::Palette::INPUT_CURSOR_OFF
    assert_includes rendered, "h"
  end

  def test_cursor_clamped_to_text_bounds
    disable_colors!
    field = Tui::InputField.new(placeholder: "", text: "abc", cursor: 99)
    assert_equal field.text.length, field.cursor
    assert_equal "abc ", field.to_s
  end
end

class SectionTest < TuiTestCase
  def test_add_line_yields_line
    screen = build_screen
    yielded = nil
    line = screen.header.add_line { |l| yielded = l; l.write << "Header" }
    assert_equal line, yielded
    assert_equal "Header", line.instance_variable_get(:@left).to_s
  end

  def test_divider_uses_screen_width
    screen = build_screen(width: 10)
    line = screen.body.divider
    span = [screen.width - 1, 1].max
    assert_equal "─" * span, line.instance_variable_get(:@left).to_s
  end

  def test_clear_removes_lines
    screen = build_screen
    screen.footer.add_line { |line| line.write << "foot" }
    assert_equal 1, screen.footer.lines.size
    screen.footer.clear
    assert_empty screen.footer.lines
  end
end

class LineRenderTest < TuiTestCase
  def test_render_with_background_and_right_text
    enable_colors!
    screen = build_screen(width: 15)
    line = Tui::Line.new(screen, background: Tui::Palette::SELECTED_BG, truncate: true)
    line.write << "left content"
    line.right.write("R")
    io = string_io
    line.render(io, screen.width)
    output = io.string
    assert_includes output, Tui::Palette::SELECTED_BG
    # Right-aligned text is placed at end via space-filling (not cursor positioning)
    assert_includes output, "R"
    assert_includes output, "\n"
  end

  def test_render_without_truncation
    screen = build_screen(width: 8)
    line = Tui::Line.new(screen, background: nil, truncate: false)
    line.write << "123456789"
    io = string_io
    line.render(io, screen.width)
    assert_includes io.string, "123456789"
  end

  def test_fill_helper_fills_line_width
    disable_colors!
    screen = build_screen(width: 6)
    line = Tui::Line.new(screen, background: nil, truncate: true)
    line.write << fill("-")
    io = string_io
    line.render(io, screen.width)
    assert_includes io.string.lines.first, "-----"
  end

  def test_z_index_controls_layer_order
    disable_colors!
    screen = build_screen(width: 20)
    line = Tui::Line.new(screen, background: nil, truncate: true)
    line.write << "LEFT"
    line.right.write("RIGHT")
    io = string_io
    line.render(io, screen.width)
    output = io.string
    # Default z-index: left=1, right=0
    # Left renders at start, right renders at end (right-justified)
    assert output.index("LEFT") < output.index("RIGHT"),
      "LEFT should appear before RIGHT in output: #{output.inspect}"
  end
end

class ScreenTest < TuiTestCase
  def test_input_only_allows_single_field
    screen = build_screen
    screen.input("Search")
    assert_raises(ArgumentError) { screen.input("Other") }
  end

  def test_flush_writes_sections_and_clears_them
    io = string_io
    screen = build_screen(width: 20, height: 4, io: io)
    screen.header.add_line { |line| line.write << "Header" }
    screen.body.add_line { |line| line.write << "Body"; line.right.write << "meta" }
    screen.footer.add_line { |line| line.write << "Footer" }
    screen.flush
    output = io.string
    assert output.start_with?(Tui::ANSI::HOME), "Expected screen to move cursor home"
    assert_includes output, "Header"
    assert_includes output, "Body"
    assert_includes output, "Footer"
    assert_empty screen.header.lines
    assert_empty screen.body.lines
    assert_empty screen.footer.lines
  end

  def test_flush_pads_short_screens
    io = string_io
    screen = build_screen(width: 10, height: 5, io: io)
    screen.body.add_line { |line| line.write << "Only" }
    screen.flush
    # 4 newlines: after each of first 4 lines (last line has no trailing newline)
    newlines = io.string.count("\n")
    assert_equal 4, newlines
  end

  def test_clear_clears_sections_and_returns_screen
    screen = build_screen
    screen.body.add_line { |line| line.write << "x" }
    result = screen.clear
    assert_same screen, result
    assert_empty screen.body.lines
  end

  def test_input_field_accessor
    screen = build_screen
    field = screen.input("Type", value: "abc", cursor: 1)
    assert_same field, screen.input_field
    assert_equal 1, field.cursor
  end

  def test_refresh_size_uses_terminal_dimensions
    stub_io = Class.new do
      def winsize
        [41, 120]
      end
    end.new

    begin
      ENV["TRY_HEIGHT"] = ""
      ENV["TRY_WIDTH"] = ""
      rows, cols = Tui::Terminal.size(stub_io)
      assert_equal 41, rows
      assert_equal 120, cols
    ensure
      ENV.delete("TRY_HEIGHT")
      ENV.delete("TRY_WIDTH")
    end
  end
end

class TerminalEnvOverrideTest < TuiTestCase
  def test_env_overrides
    stub_io = Class.new do
      def winsize
        [10, 10]
      end
    end.new

    begin
      ENV["TRY_HEIGHT"] = "50"
      ENV["TRY_WIDTH"] = ""
      rows, cols = Tui::Terminal.size(stub_io)
      assert_equal 50, rows
      assert_equal 10, cols
    ensure
      ENV.delete("TRY_HEIGHT")
      ENV.delete("TRY_WIDTH")
    end
  end

  def test_defaults_when_no_env_or_winsize
    rows, cols = Tui::Terminal.size(Object.new)
    assert_equal 24, rows
    assert_equal 80, cols
  end
end
