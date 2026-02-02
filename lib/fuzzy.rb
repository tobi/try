# frozen_string_literal: true

# Fuzzy string matching with scoring and highlight positions
#
# Usage:
#   entries = [
#     { text: "2024-01-15-project", base_score: 3.2 },
#     { text: "2024-02-20-another", base_score: 1.5 },
#   ]
#   fuzzy = Fuzzy.new(entries)
#
#   # Get all matches
#   fuzzy.match("proj").each do |entry, positions, score|
#     puts "#{entry[:text]} score=#{score} highlight=#{positions.inspect}"
#   end
#
#   # Limit results
#   fuzzy.match("proj").limit(10).each { |entry, positions, score| ... }
#
class Fuzzy
  Entry = Data.define(:data, :text, :text_lower, :base_score)

  def initialize(entries)
    @entries = entries.map do |e|
      text = e[:text] || e["text"]
      Entry.new(
        data: e,
        text: text,
        text_lower: text.downcase,
        base_score: e[:base_score] || e["base_score"] || 0.0
      )
    end
  end

  # Returns a MatchResult enumerator for the query
  def match(query)
    MatchResult.new(@entries, query.to_s)
  end

  # Enumerator wrapper that supports .limit() and .each
  class MatchResult
    include Enumerable

    def initialize(entries, query)
      @entries = entries
      @query = query
      @query_lower = query.downcase
      @query_chars = @query_lower.chars
      @limit = nil
    end

    # Set maximum number of results
    def limit(n)
      @limit = n
      self
    end

    # Iterate over matches: yields (entry_data, highlight_positions, score)
    def each(&block)
      return enum_for(:each) unless block_given?

      results = []

      @entries.each do |entry|
        score, positions = calculate_match(entry)
        next if score.nil?  # No match

        results << [entry.data, positions, score]
      end

      if @limit && @limit < results.length
        # Partial sort: O(n log k) via heap selection instead of full O(n log n) sort
        results = results.max_by(@limit) { |_, _, score| score }
      else
        results.sort_by! { |_, _, score| -score }
      end

      results.each(&block)
    end

    private

    # Pre-compiled regex for word boundary detection
    WORD_BOUNDARY_RE = /[^a-z0-9]/

    # Pre-computed sqrt values for proximity bonus (gap 0-63)
    SQRT_TABLE = (0..64).map { |n| 2.0 / Math.sqrt(n + 1) }.freeze

    def calculate_match(entry)
      positions = []
      score = entry.base_score

      # Empty query = match all with base score only
      return [score, positions] if @query.empty?

      text = entry.text_lower
      query_chars = @query_chars
      query_len = query_chars.length

      last_pos = -1
      pos = 0

      query_chars.each do |qc|
        # Find next occurrence of query char starting from pos
        found = text.index(qc, pos)
        return nil unless found  # No match

        positions << found

        # Base match point
        score += 1.0

        # Word boundary bonus (start of string or after non-alphanumeric)
        if found == 0 || text[found - 1].match?(WORD_BOUNDARY_RE)
          score += 1.0
        end

        # Proximity bonus (consecutive chars score higher)
        if last_pos >= 0
          gap = found - last_pos - 1
          score += gap < 64 ? SQRT_TABLE[gap] : (2.0 / Math.sqrt(gap + 1))
        end

        last_pos = found
        pos = found + 1
      end

      # Density bonus: prefer shorter spans
      score *= (query_len.to_f / (last_pos + 1)) if last_pos >= 0

      # Length penalty: shorter strings score higher
      score *= (10.0 / (entry.text.length + 10.0))

      [score, positions]
    end
  end
end
