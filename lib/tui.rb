# frozen_string_literal: true

# Experimental TUI toolkit for try.rb

require "io/console"
#
# Usage pattern:
#   include Tui::Helpers
#   screen = Tui::Screen.new
#   screen.header.add_line { |line| line.write << Tui::Text.bold("📁 Try Selector") }
#   search_line = screen.body.add_line
#   search_line.write_dim("Search:").write(" ")
#   search_line.write << screen.input("Type to filter…", value: query, cursor: cursor)
#   list_line = screen.body.add_line(background: Tui::Palette::SELECTED_BG)
#   list_line.write << Tui::Text.highlight("→ ") << name
#   list_line.right.write_dim(metadata)
#   screen.footer.add_line { |line| line.write_dim("↑↓ navigate  Enter select  Esc cancel") }
#   screen.flush
#
# The screen owns a single InputField (enforced by #input). Lines support
# independent left/right writers, truncation, and per-line backgrounds. Right
# writers are rendered via rwrite-style positioning (clear line + move col).

module Tui
  @colors_enabled = ENV["NO_COLORS"].to_s.empty?

  class << self
    attr_accessor :colors_enabled

    def colors_enabled?
      @colors_enabled
    end

    def disable_colors!
      @colors_enabled = false
    end

    def enable_colors!
      @colors_enabled = true
    end
  end

  module ANSI
    CLEAR_EOL = "\e[K"
    CLEAR_EOS = "\e[J"
    CLEAR_SCREEN = "\e[2J"
    HOME      = "\e[H"
    HIDE      = "\e[?25l"
    SHOW      = "\e[?25h"
    CURSOR_BLINK = "\e[1 q"       # Blinking block cursor
    CURSOR_STEADY = "\e[2 q"      # Steady block cursor
    CURSOR_DEFAULT = "\e[0 q"     # Reset cursor to terminal default
    ALT_SCREEN_ON  = "\e[?1049h"  # Enter alternate screen buffer
    ALT_SCREEN_OFF = "\e[?1049l"  # Return to main screen buffer
    RESET     = "\e[0m"
    RESET_FG  = "\e[39m"
    RESET_BG  = "\e[49m"
    RESET_INTENSITY = "\e[22m"
    BOLD      = "\e[1m"
    DIM       = "\e[2m"

    module_function

    def fg(code)
      "\e[38;5;#{code}m"
    end

    def bg(code)
      "\e[48;5;#{code}m"
    end

    def move_col(col)
      "\e[#{col}G"
    end

    def sgr(*codes)
      joined = codes.flatten.join(";")
      "\e[#{joined}m"
    end
  end

  module Palette
    HEADER      = ANSI.sgr(1, "38;5;114")
    ACCENT      = ANSI.sgr(1, "38;5;214")
    MUTED       = ANSI.fg(245)
    MATCH       = ANSI.sgr(1, "38;5;226")
    INPUT_HINT  = ANSI.fg(244)
    INPUT_CURSOR_ON  = "\e[7m"
    INPUT_CURSOR_OFF = "\e[27m"

    SELECTED_BG = ANSI.bg(238)
    DANGER_BG   = ANSI.bg(52)
  end

  module Metrics
    module_function

    def visible_width(text)
      stripped = text.gsub(/\e\[[0-9;]*[A-Za-z]/, '')
      stripped.each_char.sum do |ch|
        if zero_width?(ch)
          0
        elsif wide?(ch)
          2
        else
          1
        end
      end
    end

    def zero_width?(ch)
      code = ch.ord
      # Zero-width characters: variation selectors, combining marks, ZWJ, etc.
      (code >= 0xFE00 && code <= 0xFE0F) ||   # Variation Selectors
      (code >= 0x200B && code <= 0x200D) ||   # Zero-width space, ZWNJ, ZWJ
      (code >= 0x0300 && code <= 0x036F) ||   # Combining Diacritical Marks
      (code >= 0xE0100 && code <= 0xE01EF)    # Variation Selectors Supplement
    end

    def truncate(text, max_width, overflow: "…")
      return text if visible_width(text) <= max_width

      overflow_width = visible_width(overflow)
      target = [max_width - overflow_width, 0].max
      truncated = String.new
      width = 0
      in_escape = false
      escape_buf = String.new

      text.each_char do |ch|
        if in_escape
          escape_buf << ch
          if ch =~ /[A-Za-z]/
            truncated << escape_buf
            escape_buf = String.new
            in_escape = false
          end
          next
        end

        if ch == "\e"
          in_escape = true
          escape_buf = ch
          next
        end

        char_width = wide?(ch) ? 2 : 1
        break if width + char_width > target

        truncated << ch
        width += char_width
      end

      truncated.rstrip + overflow
    end

    def wide?(ch)
      code = ch.ord
      # CJK characters, full-width forms, emojis, and other wide characters
      # Excludes box drawing (0x2500-0x257F) and other single-width symbols
      (code >= 0x1100 && code <= 0x115F) ||   # Hangul Jamo
      (code >= 0x231A && code <= 0x23FF) ||   # Miscellaneous Technical (some wide)
      (code >= 0x2600 && code <= 0x26FF) ||   # Miscellaneous Symbols
      (code >= 0x2700 && code <= 0x27BF) ||   # Dingbats
      (code >= 0x2E80 && code <= 0x9FFF) ||   # CJK
      (code >= 0xAC00 && code <= 0xD7AF) ||   # Hangul Syllables
      (code >= 0xF900 && code <= 0xFAFF) ||   # CJK Compatibility Ideographs
      (code >= 0xFE10 && code <= 0xFE1F) ||   # Vertical forms
      (code >= 0xFE30 && code <= 0xFE6F) ||   # CJK Compatibility Forms
      (code >= 0xFF00 && code <= 0xFF60) ||   # Fullwidth Forms
      (code >= 0xFFE0 && code <= 0xFFE6) ||   # Fullwidth symbols
      (code >= 0x1F300 && code <= 0x1F9FF) || # Emojis (Misc Symbols, Emoticons, etc.)
      (code >= 0x1FA00 && code <= 0x1FAFF) || # Chess symbols, Extended-A
      (code >= 0x20000 && code <= 0x2FFFF)    # CJK Extension B+
    end
  end

  module Text
    module_function

    def bold(text)
      wrap(text, ANSI::BOLD, ANSI::RESET_INTENSITY)
    end

    def dim(text)
      wrap(text, Palette::MUTED, ANSI::RESET_FG)
    end

    def highlight(text)
      wrap(text, Palette::MATCH, ANSI::RESET_FG + ANSI::RESET_INTENSITY)
    end

    def accent(text)
      wrap(text, Palette::ACCENT, ANSI::RESET_FG + ANSI::RESET_INTENSITY)
    end

    def wrap(text, prefix, suffix)
      return "" if text.nil? || text.empty?
      return text unless Tui.colors_enabled?
      "#{prefix}#{text}#{suffix}"
    end
  end

  module Helpers
    def bold(text)
      Text.bold(text)
    end

    def dim(text)
      Text.dim(text)
    end

    def highlight(text)
      Text.highlight(text)
    end

    def accent(text)
      Text.accent(text)
    end

    def fill(char = " ")
      SegmentWriter::FillSegment.new(char.to_s)
    end
  end

  class Terminal
    class << self
      def size(io = $stderr)
        env_rows = ENV['TRY_HEIGHT'].to_i
        env_cols = ENV['TRY_WIDTH'].to_i
        rows = env_rows.positive? ? env_rows : nil
        cols = env_cols.positive? ? env_cols : nil

        streams = [io, $stdout, $stdin].compact.uniq

        streams.each do |stream|
          next unless (!rows || !cols)
          next unless stream.respond_to?(:winsize)

          begin
            s_rows, s_cols = stream.winsize
            rows ||= s_rows
            cols ||= s_cols
          rescue IOError, Errno::ENOTTY, Errno::EOPNOTSUPP, Errno::ENODEV
            next
          end
        end

        if (!rows || !cols)
          begin
            console = IO.console
            if console
              c_rows, c_cols = console.winsize
              rows ||= c_rows
              cols ||= c_cols
            end
          rescue IOError, Errno::ENOTTY, Errno::EOPNOTSUPP, Errno::ENODEV
          end
        end

        rows ||= 24
        cols ||= 80
        [rows, cols]
      end
    end
  end

  class Screen
    include Helpers

    attr_reader :header, :body, :footer, :input_field, :width, :height

    def initialize(io: $stderr, width: nil, height: nil)
      @io = io
      @fixed_width = width
      @fixed_height = height
      @width = @height = nil
      refresh_size
      @header = Section.new(self)
      @body   = Section.new(self)
      @footer = Section.new(self)
      @sections = [@header, @body, @footer]
      @input_field = nil
      @cursor_row = nil
    end

    def refresh_size
      rows, cols = Terminal.size(@io)
      @height = @fixed_height || rows
      @width = @fixed_width || cols
      self
    end

    def input(placeholder = "", value: "", cursor: nil)
      raise ArgumentError, "screen already has an input" if @input_field
      @input_field = InputField.new(placeholder: placeholder, text: value, cursor: cursor)
    end

    def clear
      @sections.each(&:clear)
      self
    end

    def flush
      refresh_size
      begin
        @io.write(ANSI::HOME)
      rescue IOError
      end

      rendered_rows = 0
      cursor_row = nil
      cursor_col = nil

      @sections.each do |section|
        section.lines.each do |line|
          # Check if this line contains the input field
          if @input_field && line.has_input?
            cursor_row = rendered_rows + 1  # 1-based row
            cursor_col = line.cursor_column(@input_field, @width)
          end
          line.render(@io, @width)
          rendered_rows += 1
        end
      end

      pad_rows = @height - rendered_rows
      if pad_rows.positive?
        # Write all but last padding row with \n
        (pad_rows - 1).times { @io.write("#{ANSI::CLEAR_EOL}\n") }
        # Last row: clear but no \n to avoid scrolling
        @io.write(ANSI::CLEAR_EOL)
      end

      # Position cursor at input field if present, otherwise hide cursor
      if cursor_row && cursor_col && @input_field
        @io.write("\e[#{cursor_row};#{cursor_col}H")
        @io.write(ANSI::SHOW)
      else
        @io.write(ANSI::HIDE)
      end

      @io.write(ANSI::RESET)
      @io.flush
    ensure
      clear
    end
  end

  class Section
    attr_reader :lines

    def initialize(screen)
      @screen = screen
      @lines = []
    end

    def add_line(background: nil, truncate: true)
      line = Line.new(@screen, background: background, truncate: truncate)
      @lines << line
      yield line if block_given?
      line
    end

    def divider(char: '─')
      add_line do |line|
        span = [@screen.width - 1, 1].max
        line.write << char * span
      end
    end

    def clear
      @lines.clear
    end
  end

  class Line
    attr_accessor :background, :truncate

    def initialize(screen, background:, truncate: true)
      @screen = screen
      @background = background
      @truncate = truncate
      @left = SegmentWriter.new(z_index: 1)
      @center = nil  # Lazy - only created when accessed (z_index: 2, renders on top)
      @right = nil   # Lazy - only created when accessed (z_index: 0)
      @has_input = false
      @input_prefix_width = 0
    end

    def write
      @left
    end

    def left
      @left
    end

    def center
      @center ||= SegmentWriter.new(z_index: 2)
    end

    def right
      @right ||= SegmentWriter.new(z_index: 0)
    end

    def has_input?
      @has_input
    end

    def mark_has_input(prefix_width)
      @has_input = true
      @input_prefix_width = prefix_width
    end

    def cursor_column(input_field, width)
      # Calculate cursor position: prefix + cursor position in input
      @input_prefix_width + input_field.cursor + 1
    end

    def render(io, width)
      buffer = String.new
      buffer << "\r"

      # Set background if present
      buffer << background if background && Tui.colors_enabled?

      content_width = [width, 1].max
      left_text = @left.to_s(width: content_width)
      center_text = @center ? @center.to_s(width: content_width) : ""
      right_text = @right ? @right.to_s(width: content_width) : ""

      left_text = Metrics.truncate(left_text, content_width) if @truncate && !left_text.empty?

      # Calculate widths
      left_width = left_text.empty? ? 0 : Metrics.visible_width(left_text)
      center_width = center_text.empty? ? 0 : Metrics.visible_width(center_text)
      right_width = right_text.empty? ? 0 : Metrics.visible_width(right_text)

      # Calculate positions
      center_col = center_text.empty? ? 0 : [(width - center_width) / 2, left_width].max
      right_col = right_text.empty? ? width : [width - right_width, left_width].max

      # Write left content
      buffer << left_text unless left_text.empty?
      current_pos = left_width

      # Write centered content if present
      unless center_text.empty?
        gap_to_center = center_col - current_pos
        buffer << (" " * gap_to_center) if gap_to_center > 0
        buffer << center_text
        current_pos = center_col + center_width
      end

      # Fill gap to right content (or end of line)
      # This is critical for clearing stale content from previous renders
      # Fill to width-1 to leave room for the newline without wrap
      fill_end = right_text.empty? ? (width - 1) : right_col
      gap = fill_end - current_pos

      if gap > 0
        buffer << (" " * gap)
      end

      # If no right content, fill the very last column with a space
      # This ensures the line extends to full width
      if right_text.empty? && current_pos + gap < width - 1
        buffer << " "
      end

      # Write right content if present
      unless right_text.empty?
        buffer << right_text
        buffer << ANSI::RESET_FG
      end

      buffer << ANSI::RESET
      buffer << "\n"

      io.write(buffer)
    end
  end

  class SegmentWriter
    include Helpers

    class FillSegment
      attr_reader :char, :style

      def initialize(char, style: nil)
        @char = char.to_s
        @style = style
      end

      def with_style(style)
        self.class.new(char, style: style)
      end
    end

    attr_accessor :z_index

    def initialize(z_index: 1)
      @segments = []
      @z_index = z_index
    end

    def write(text = "")
      return self if text.nil?
      if text.respond_to?(:empty?) && text.empty?
        return self
      end

      @segments << normalize_segment(text)
      self
    end

    alias << write

    def write_dim(text)
      write(style_segment(text, :dim) { |value| dim(value) })
    end

    def write_bold(text)
      write(style_segment(text, :bold) { |value| bold(value) })
    end

    def write_highlight(text)
      write(style_segment(text, :highlight) { |value| highlight(value) })
    end

    def to_s(width: nil)
      rendered = String.new
      @segments.each do |segment|
        case segment
        when FillSegment
          raise ArgumentError, "fill requires width context" unless width
          rendered << render_fill(segment, rendered, width)
        else
          rendered << segment.to_s
        end
      end
      rendered
    end

    def empty?
      @segments.empty?
    end

    private

    def normalize_segment(text)
      if text.is_a?(FillSegment)
        text
      else
        text.to_s
      end
    end

    def style_segment(text, style)
      if text.is_a?(FillSegment)
        text.with_style(style)
      else
        yield(text)
      end
    end

    def render_fill(segment, rendered, width)
      # Use width - 1 to avoid wrapping in terminals that wrap at the last column
      max_fill = width - 1
      remaining = max_fill - Metrics.visible_width(rendered)
      return "" if remaining <= 0

      pattern = segment.char
      pattern = " " if pattern.empty?
      pattern_width = [Metrics.visible_width(pattern), 1].max
      repeat = (remaining.to_f / pattern_width).ceil
      filler = pattern * repeat
      filler = Metrics.truncate(filler, remaining, overflow: "")
      apply_style(filler, segment.style)
    end

    def apply_style(text, style)
      case style
      when :dim
        dim(text)
      when :bold
        bold(text)
      when :highlight
        highlight(text)
      when :accent
        accent(text)
      else
        text
      end
    end
  end

  class InputField
    attr_accessor :text, :cursor
    attr_reader :placeholder

    def initialize(placeholder:, text:, cursor: nil)
      @placeholder = placeholder
      @text = text.to_s.dup
      @cursor = cursor.nil? ? @text.length : [[cursor, 0].max, @text.length].min
    end

    def to_s
      return render_placeholder if text.empty?

      before = text[0...cursor]
      cursor_char = text[cursor] || ' '
      after = cursor < text.length ? text[(cursor + 1)..] : ""

      buf = String.new
      buf << before
      buf << Palette::INPUT_CURSOR_ON if Tui.colors_enabled?
      buf << cursor_char
      buf << Palette::INPUT_CURSOR_OFF if Tui.colors_enabled?
      buf << after
      buf
    end

    private

    def render_placeholder
      Text.dim(placeholder)
    end
  end
end
