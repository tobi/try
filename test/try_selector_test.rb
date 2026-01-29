# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "set"
require_relative "../lib/tui"
require_relative "../lib/fuzzy"

# Load TrySelector class without executing the __FILE__ == $0 block
# We eval the class definition portion only
unless defined?(TrySelector)
  source = File.read(File.expand_path("../try.rb", __dir__))
  # Extract everything up to the "if __FILE__ == $0" guard
  class_source = source.split(/^if __FILE__ == \$0$/)[0]
  eval(class_source, TOPLEVEL_BINDING, File.expand_path("../try.rb", __dir__), 1)
end

class TrySelectorTestCase < Minitest::Test
  def setup
    @colors_were_enabled = Tui.colors_enabled?
    @tmpdir = Dir.mktmpdir("try_test")
  end

  def teardown
    Tui.colors_enabled = @colors_were_enabled
    FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def build_selector(**opts)
    TrySelector.new("", base_path: @tmpdir, test_render_once: true, test_no_cls: true, **opts)
  end
end

# -------------------------------------------------------------------
# word_boundary_backward
# -------------------------------------------------------------------
class WordBoundaryTest < TrySelectorTestCase
  def selector
    @sel ||= build_selector
  end

  def wb(buffer, cursor)
    selector.send(:word_boundary_backward, buffer, cursor)
  end

  def test_end_of_word
    assert_equal 0, wb("hello", 5)
  end

  def test_middle_of_word
    assert_equal 0, wb("hello", 3)
  end

  def test_start_of_word
    assert_equal 0, wb("hello", 1)
  end

  def test_skips_separators
    # "foo-bar" cursor at end (7) -> skip to beginning of "bar" segment
    assert_equal 4, wb("foo-bar", 7)
  end

  def test_single_word
    assert_equal 0, wb("x", 1)
  end

  def test_dots_and_underscores_are_separators
    # "a.b_c" cursor at 5 -> "c" is alphanumeric, "_" is separator, skips to 4
    assert_equal 4, wb("a.b_c", 5)
  end

  def test_cursor_at_one
    assert_equal 0, wb("abc", 1)
  end

  def test_all_separator_string
    # "---" cursor at 3 -> no alphanumeric to skip, stops at 0
    assert_equal 0, wb("---", 3)
  end
end

# -------------------------------------------------------------------
# format_relative_time
# -------------------------------------------------------------------
class FormatRelativeTimeTest < TrySelectorTestCase
  def selector
    @sel ||= build_selector
  end

  def fmt(time)
    selector.send(:format_relative_time, time)
  end

  def test_nil_returns_question_mark
    assert_equal "?", fmt(nil)
  end

  def test_just_now
    assert_equal "just now", fmt(Time.now)
  end

  def test_minutes
    assert_equal "5m ago", fmt(Time.now - 300)
  end

  def test_hours
    assert_equal "3h ago", fmt(Time.now - 3 * 3600)
  end

  def test_days
    assert_equal "2d ago", fmt(Time.now - 2 * 86400)
  end

  def test_weeks
    assert_equal "3w ago", fmt(Time.now - 21 * 86400)
  end

  def test_boundary_at_59_seconds
    assert_equal "just now", fmt(Time.now - 59)
  end

  def test_boundary_at_60_seconds
    assert_equal "1m ago", fmt(Time.now - 60)
  end
end

# -------------------------------------------------------------------
# truncate_with_ansi
# -------------------------------------------------------------------
class TruncateWithAnsiTest < TrySelectorTestCase
  def selector
    @sel ||= build_selector
  end

  def trunc(text, max)
    selector.send(:truncate_with_ansi, text, max)
  end

  def test_plain_text_truncated
    assert_equal "hel", trunc("hello", 3)
  end

  def test_no_truncation_needed
    assert_equal "hi", trunc("hi", 5)
  end

  def test_ansi_preserved
    Tui.enable_colors!
    colored = "\e[1mhello\e[22m"
    result = trunc(colored, 3)
    assert_includes result, "\e[1m"
    # Should have at most 3 visible chars
    visible = result.gsub(/\e\[[0-9;]*[a-zA-Z]/, '')
    assert_equal 3, visible.length
  end

  def test_mixed_ansi_and_text
    text = "ab\e[31mcd\e[0mef"
    result = trunc(text, 4)
    visible = result.gsub(/\e\[[0-9;]*[a-zA-Z]/, '')
    assert_equal 4, visible.length
  end

  def test_empty_string
    assert_equal "", trunc("", 5)
  end

  def test_zero_max_length
    assert_equal "", trunc("hello", 0)
  end
end

# -------------------------------------------------------------------
# highlight_with_positions
# -------------------------------------------------------------------
class HighlightWithPositionsTest < TrySelectorTestCase
  def selector
    @sel ||= build_selector
  end

  def hlp(text, positions, offset)
    selector.send(:highlight_with_positions, text, positions, offset)
  end

  def test_no_positions
    Tui.disable_colors!
    assert_equal "hello", hlp("hello", [], 0)
  end

  def test_array_input
    Tui.enable_colors!
    result = hlp("abc", [0], 0)
    assert_includes result, Tui::Palette::HIGHLIGHT
    assert_includes result, "a"
  end

  def test_set_input
    Tui.enable_colors!
    result = hlp("abc", Set.new([1]), 0)
    assert_includes result, Tui::Palette::HIGHLIGHT
  end

  def test_with_offset
    Tui.enable_colors!
    # offset=5, positions=[5] -> highlights char at index 0 of text
    result = hlp("abc", [5], 5)
    assert_includes result, Tui::Palette::HIGHLIGHT
  end
end

# -------------------------------------------------------------------
# load_all_tries
# -------------------------------------------------------------------
class LoadAllTriesTest < TrySelectorTestCase
  def test_directories_only
    FileUtils.mkdir_p(File.join(@tmpdir, "dir1"))
    FileUtils.touch(File.join(@tmpdir, "file1"))
    sel = build_selector
    tries = sel.send(:load_all_tries)
    names = tries.map { |t| t[:text] }
    assert_includes names, "dir1"
    refute_includes names, "file1"
  end

  def test_hidden_dirs_skipped
    FileUtils.mkdir_p(File.join(@tmpdir, ".hidden"))
    FileUtils.mkdir_p(File.join(@tmpdir, "visible"))
    sel = build_selector
    tries = sel.send(:load_all_tries)
    names = tries.map { |t| t[:text] }
    refute_includes names, ".hidden"
    assert_includes names, "visible"
  end

  def test_date_prefix_bonus
    FileUtils.mkdir_p(File.join(@tmpdir, "2024-01-15-dated"))
    FileUtils.mkdir_p(File.join(@tmpdir, "nodated"))
    sel = build_selector
    tries = sel.send(:load_all_tries)
    dated = tries.find { |t| t[:text] == "2024-01-15-dated" }
    undated = tries.find { |t| t[:text] == "nodated" }
    assert dated[:base_score] > undated[:base_score],
      "Dated entry should have higher base_score"
  end

  def test_enoent_handling
    # Create dir then remove it before scan -- selector should not crash
    disappearing = File.join(@tmpdir, "vanish")
    FileUtils.mkdir_p(disappearing)
    sel = build_selector
    FileUtils.rm_rf(disappearing)
    # Should not raise
    tries = sel.send(:load_all_tries)
    assert_kind_of Array, tries
  end
end

# -------------------------------------------------------------------
# get_tries caching
# -------------------------------------------------------------------
class GetTriesCachingTest < TrySelectorTestCase
  def test_returns_try_entry_objects
    FileUtils.mkdir_p(File.join(@tmpdir, "mydir"))
    sel = build_selector
    tries = sel.send(:get_tries)
    refute_empty tries
    assert_kind_of TrySelector::TryEntry, tries.first
  end

  def test_cache_hit
    FileUtils.mkdir_p(File.join(@tmpdir, "mydir"))
    sel = build_selector
    first = sel.send(:get_tries)
    second = sel.send(:get_tries)
    assert_same first, second
  end

  def test_cache_miss_on_buffer_change
    FileUtils.mkdir_p(File.join(@tmpdir, "mydir"))
    sel = build_selector
    first = sel.send(:get_tries)
    sel.instance_variable_set(:@input_buffer, "my")
    second = sel.send(:get_tries)
    refute_same first, second
  end
end

# -------------------------------------------------------------------
# formatted_entry_name
# -------------------------------------------------------------------
class FormattedEntryNameTest < TrySelectorTestCase
  def selector
    @sel ||= build_selector
  end

  def test_date_prefixed_entry
    Tui.enable_colors!
    entry = TrySelector::TryEntry.new(
      { basename: "2024-01-15-project", text: "2024-01-15-project" }, 1.0, []
    )
    plain, rendered = selector.send(:formatted_entry_name, entry)
    assert_equal "2024-01-15-project", plain
    assert_includes rendered, Tui::Palette::MUTED  # date part is dimmed
  end

  def test_non_date_entry
    Tui.disable_colors!
    entry = TrySelector::TryEntry.new(
      { basename: "nodate", text: "nodate" }, 1.0, []
    )
    plain, rendered = selector.send(:formatted_entry_name, entry)
    assert_equal "nodate", plain
    assert_equal "nodate", rendered
  end

  def test_highlights_with_offset
    Tui.enable_colors!
    # Position 11 = first char of name part in "2024-01-15-project"
    entry = TrySelector::TryEntry.new(
      { basename: "2024-01-15-project", text: "2024-01-15-project" }, 1.0, [11]
    )
    _plain, rendered = selector.send(:formatted_entry_name, entry)
    assert_includes rendered, Tui::Palette::HIGHLIGHT
  end

  def test_hyphen_highlight_at_position_10
    Tui.enable_colors!
    entry = TrySelector::TryEntry.new(
      { basename: "2024-01-15-project", text: "2024-01-15-project" }, 1.0, [10]
    )
    _plain, rendered = selector.send(:formatted_entry_name, entry)
    # Position 10 is the hyphen between date and name
    assert_includes rendered, Tui::Palette::HIGHLIGHT
  end
end

# -------------------------------------------------------------------
# finalize_rename
# -------------------------------------------------------------------
class FinalizeRenameTest < TrySelectorTestCase
  def selector
    @sel ||= build_selector
  end

  def entry(name)
    TrySelector::TryEntry.new(
      { basename: name, text: name, path: File.join(@tmpdir, name) }, 1.0, []
    )
  end

  def test_empty_name_error
    result = selector.send(:finalize_rename, entry("old"), "   ")
    assert_equal "Name cannot be empty", result
  end

  def test_slash_error
    result = selector.send(:finalize_rename, entry("old"), "foo/bar")
    assert_equal "Name cannot contain /", result
  end

  def test_same_name_noop
    result = selector.send(:finalize_rename, entry("myname"), "myname")
    assert_equal true, result
    assert_nil selector.instance_variable_get(:@selected)
  end

  def test_collision_error
    FileUtils.mkdir_p(File.join(@tmpdir, "existing"))
    result = selector.send(:finalize_rename, entry("old"), "existing")
    assert_equal "Directory exists: existing", result
  end

  def test_valid_rename_sets_selected
    result = selector.send(:finalize_rename, entry("old"), "brand-new")
    assert_equal true, result
    selected = selector.instance_variable_get(:@selected)
    assert_equal :rename, selected[:type]
    assert_equal "old", selected[:old]
    assert_equal "brand-new", selected[:new]
  end
end
