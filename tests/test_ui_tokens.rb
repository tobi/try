require 'test/unit'
require 'stringio'
require_relative '../try.rb'

class TestUITokens < Test::Unit::TestCase

  def test_token_map_contains_core_tokens
    %w[{text} {dim_text} {h1} {h2} {highlight} {reset} {reset_bg} {reset_fg}].each do |tok|
      assert(UI::TOKEN_MAP.key?(tok), "missing token #{tok}")
    end
  end

  def test_expand_tokens_substitutes_sequences
    sample = "{h1}Title{reset}"
    expanded = UI.expand_tokens(sample)
    refute_equal(sample, expanded, 'should have expanded tokens')
    assert_match(/\e\[/, expanded, 'expanded should contain ANSI')
  end

  def test_flush_strips_tokens_for_non_tty
    io = StringIO.new
    UI.puts '{h2}Hello{reset}'
    UI.flush(io: io)
    out = io.string
    assert_match(/Hello/, out)
    refute_match(/\{h2\}|\{reset\}/, out)
  end
end
