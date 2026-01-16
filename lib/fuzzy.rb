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

      # Sort by score descending
      results.sort_by! { |_, _, score| -score }

      # Apply limit
      results = results.first(@limit) if @limit

      results.each(&block)
    end

    private

    def calculate_match(entry)
      positions = []
      score = entry.base_score

      # Empty query = match all with base score only
      if @query.empty?
        return [score, positions]
      end

      text_lower = entry.text_lower
      text_len = text_lower.length
      query_len = @query_chars.length

      last_pos = -1
      query_idx = 0

      i = 0
      while i < text_len
        break if query_idx >= query_len

        if text_lower[i] == @query_chars[query_idx]
          positions << i

          # Base match point
          score += 1.0

          # Word boundary bonus (start of string or after non-alphanumeric)
          is_boundary = (i == 0) || text_lower[i - 1].match?(/[^a-z0-9]/)
          score += 1.0 if is_boundary

          # Proximity bonus (consecutive chars score higher)
          if last_pos >= 0
            gap = i - last_pos - 1
            score += 2.0 / Math.sqrt(gap + 1)
          end

          last_pos = i
          query_idx += 1
        end

        i += 1
      end

      # Not all query chars matched = no match
      return nil if query_idx < query_len

      # Density bonus: prefer shorter spans
      score *= (query_len.to_f / (last_pos + 1)) if last_pos >= 0

      # Length penalty: shorter strings score higher
      score *= (10.0 / (entry.text.length + 10.0))

      [score, positions]
    end
  end
end
