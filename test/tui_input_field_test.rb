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

class InputFieldEditingTest < TuiTestCase
  def field(text = "hello", cursor = nil)
    Tui::InputField.new(placeholder: "", text: text, cursor: cursor)
  end

  def test_insert_at_cursor
    f = field("abc", 1)
    f.insert("X")
    assert_equal "aXbc", f.text
    assert_equal 2, f.cursor
  end

  def test_backspace
    f = field("abc", 2)
    f.backspace
    assert_equal "ac", f.text
    assert_equal 1, f.cursor
  end

  def test_backspace_at_start_is_noop
    f = field("abc", 0)
    f.backspace
    assert_equal "abc", f.text
    assert_equal 0, f.cursor
  end

  def test_delete_forward
    f = field("abc", 1)
    f.delete_forward
    assert_equal "ac", f.text
    assert_equal 1, f.cursor
  end

  def test_kill_to_end
    f = field("abcdef", 3)
    f.kill_to_end
    assert_equal "abc", f.text
    assert_equal 3, f.cursor
  end

  def test_kill_to_start
    f = field("abcdef", 3)
    f.kill_to_start
    assert_equal "def", f.text
    assert_equal 0, f.cursor
  end

  def test_kill_word_stops_at_dash
    f = field("hello-world")
    f.kill_word
    assert_equal "hello-", f.text
  end

  def test_handle_key_consumes_arrows
    f = field("abc", 2)
    assert f.handle_key("\e[D")
    assert_equal 1, f.cursor
    assert f.handle_key("\e[C")
    assert_equal 2, f.cursor
  end

  def test_handle_key_consumes_ctrl_u
    f = field("abc", 2)
    assert f.handle_key("\x15")
    assert_equal "c", f.text
    assert_equal 0, f.cursor
  end

  def test_handle_key_consumes_delete_csi
    f = field("abc", 1)
    assert f.handle_key("\e[3~")
    assert_equal "ac", f.text
  end

  def test_handle_key_rejects_selector_keys
    f = field("abc")
    ["\r", "\e", "\x03", "\x04", "\x07", "\x14", "\x10", "\x0E", "\e[A", "\e[B", "\t", "\x12"].each do |key|
      refute f.handle_key(key), "should not consume #{key.inspect}"
    end
    assert_equal "abc", f.text
  end

  def test_handle_key_inserts_printable
    f = field("", 0)
    assert f.handle_key("z")
    assert_equal "z", f.text
  end

  def test_to_s_still_reverse_video_cursor
    enable_colors!
    f = field("ab", 1)
    rendered = f.to_s
    assert_includes rendered, Tui::Palette::INPUT_CURSOR_ON
    assert_includes rendered, "b"
  end
end
