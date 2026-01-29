# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/fuzzy"

class FuzzyTest < Minitest::Test
  def setup
    @entries = [
      { text: "2024-01-15-project-alpha", base_score: 3.0 },
      { text: "2024-02-20-project-beta", base_score: 2.0 },
      { text: "2024-03-10-something-else", base_score: 1.0 },
      { text: "2024-04-05-beta-test", base_score: 0.5 },
    ]
    @fuzzy = Fuzzy.new(@entries)
  end

  def test_empty_query_returns_all_sorted_by_base_score
    results = @fuzzy.match("").to_a
    assert_equal 4, results.length
    assert_equal "2024-01-15-project-alpha", results.first[0][:text]
    assert_equal 3.0, results.first[2]
  end

  def test_match_returns_enumerator
    result = @fuzzy.match("proj")
    assert_respond_to result, :each
    assert_respond_to result, :limit
  end

  def test_match_filters_non_matching
    results = @fuzzy.match("xyz").to_a
    assert_empty results
  end

  def test_match_returns_highlight_positions
    results = @fuzzy.match("proj").to_a
    refute_empty results

    # First result should be project-alpha (highest base_score + match)
    entry, positions, _score = results.first
    assert_equal "2024-01-15-project-alpha", entry[:text]

    # Positions should be indices of p, r, o, j
    assert_equal 4, positions.length
    assert_equal 11, positions[0]  # p in project
    assert_equal 12, positions[1]  # r
    assert_equal 13, positions[2]  # o
    assert_equal 14, positions[3]  # j
  end

  def test_limit_restricts_results
    results = @fuzzy.match("").limit(2).to_a
    assert_equal 2, results.length
  end

  def test_case_insensitive_matching
    results = @fuzzy.match("PROJ").to_a
    refute_empty results
    assert results.any? { |e, _, _| e[:text].include?("project") }
  end

  def test_word_boundary_detection
    # Verify positions are correctly identified
    entries = [{ text: "foo-bar", base_score: 0 }]
    fuzzy = Fuzzy.new(entries)
    results = fuzzy.match("b").to_a
    _, positions, _ = results.first

    # Should match 'b' at position 4 (after hyphen)
    assert_equal [4], positions
  end

  def test_consecutive_chars_bonus
    entries = [
      { text: "project", base_score: 0 },
      { text: "p-r-o-j-e-c-t", base_score: 0 },
    ]
    fuzzy = Fuzzy.new(entries)
    results = fuzzy.match("proj").to_a

    # "project" should score higher (consecutive chars)
    assert_equal "project", results.first[0][:text]
  end

  def test_shorter_strings_preferred
    entries = [
      { text: "project", base_score: 0 },
      { text: "project-with-long-suffix", base_score: 0 },
    ]
    fuzzy = Fuzzy.new(entries)
    results = fuzzy.match("proj").to_a

    # Shorter string should score higher
    assert_equal "project", results.first[0][:text]
  end

  def test_base_score_affects_ranking
    entries = [
      { text: "project-old", base_score: 1.0 },
      { text: "project-new", base_score: 10.0 },
    ]
    fuzzy = Fuzzy.new(entries)
    results = fuzzy.match("proj").to_a

    # Higher base_score should win
    assert_equal "project-new", results.first[0][:text]
  end

  def test_partial_match_fails
    results = @fuzzy.match("projectxyz").to_a
    assert_empty results
  end

  def test_each_yields_three_values
    @fuzzy.match("proj").each do |entry, positions, score|
      assert_kind_of Hash, entry
      assert_kind_of Array, positions
      assert_kind_of Numeric, score
    end
  end

  def test_chained_limit_and_each
    count = 0
    @fuzzy.match("").limit(2).each { count += 1 }
    assert_equal 2, count
  end

  def test_string_key_access
    entries = [
      { "text" => "string-keyed-entry", "base_score" => 2.0 },
    ]
    fuzzy = Fuzzy.new(entries)
    results = fuzzy.match("string").to_a
    refute_empty results
    assert_equal "string-keyed-entry", results.first[0]["text"]
  end

  def test_string_base_score_key
    entries = [
      { "text" => "alpha", "base_score" => 10.0 },
      { "text" => "alphabravo", "base_score" => 1.0 },
    ]
    fuzzy = Fuzzy.new(entries)
    results = fuzzy.match("alpha").to_a
    # Higher base_score should rank first
    assert_equal "alpha", results.first[0]["text"]
  end

  def test_word_boundary_at_position_zero
    entries = [{ text: "alpha", base_score: 0 }]
    fuzzy = Fuzzy.new(entries)
    results = fuzzy.match("a").to_a
    _, positions, score = results.first
    assert_equal [0], positions
    # Position 0 is a word boundary, so should get boundary bonus
    # Score should be > base(0) + match(1.0) + density + length
    assert score > 0
  end

  def test_match_positions_are_arrays
    results = @fuzzy.match("proj").to_a
    results.each do |_entry, positions, _score|
      assert_kind_of Array, positions
      # Should be convertible to Set for highlight_with_positions
      set = positions.to_set
      assert_kind_of Set, set
    end
  end
end
