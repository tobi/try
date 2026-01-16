# frozen_string_literal: true

require_relative "test_helper"

class InputFieldBehaviorTest < TuiTestCase
  def test_cursor_defaults_to_end
    field = Tui::InputField.new(placeholder: "", text: "abc")
    assert_equal 3, field.cursor
  end

  def test_cursor_defaults_to_zero_when_empty
    field = Tui::InputField.new(placeholder: "", text: "")
    assert_equal 0, field.cursor
  end

  def test_placeholder_dimmed_when_colors_enabled
    enable_colors!
    field = Tui::InputField.new(placeholder: "Search", text: "")
    assert_includes field.to_s, Tui::Palette::MUTED
  end
end
