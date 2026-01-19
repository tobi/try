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
    HIGHLIGHT   = "\e[1;33m"  # Bold yellow (matches C version)
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

    # Optimized width calculation - avoids per-character method calls
    def visible_width(text)
      # Fast path: pure ASCII with no escapes
      if text.bytesize == text.length && !text.include?("\e")
        return text.length
      end

      # Strip ANSI escapes only if present
      stripped = text.include?("\e") ? text.gsub(/\e\[[0-9;]*[A-Za-z]/, '') : text

      # Fast path after stripping: pure ASCII
      if stripped.bytesize == stripped.length
        return stripped.length
      end

      # Slow path: calculate width per codepoint (avoids each_char + ord)
      width = 0
      stripped.each_codepoint do |code|
        width += char_width(code)
      end
      width
    end

    # Simplified width check - we only use known Unicode in this app
    def char_width(code)
      # Zero-width: variation selectors (🗑️ = trash + VS16)
      return 0 if code >= 0xFE00 && code <= 0xFE0F

      # Emoji range (📁🏠🗑📂 etc) = width 2
      return 2 if code >= 0x1F300 && code <= 0x1FAFF

      # Everything else (ASCII, arrows, box drawing, ellipsis) = width 1
      1
    end

    def zero_width?(ch)
      code = ch.ord
      (code >= 0xFE00 && code <= 0xFE0F) ||
      (code >= 0x200B && code <= 0x200D) ||
      (code >= 0x0300 && code <= 0x036F) ||
      (code >= 0xE0100 && code <= 0xE01EF)
    end

    def wide?(ch)
      char_width(ch.ord) == 2
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
          if ch.match?(/[A-Za-z]/)
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

        cw = char_width(ch.ord)
        break if width + cw > target

        truncated << ch
        width += cw
      end

      truncated.rstrip + overflow
    end

    # Truncate from the start, keeping trailing portion (for right-aligned overflow)
    # Preserves leading ANSI escape sequences (like dim/color codes)
    def truncate_from_start(text, max_width)
      vis_width = visible_width(text)
      return text if vis_width <= max_width

      # Collect leading escape sequences first
      leading_escapes = String.new
      in_escape = false
      escape_buf = String.new
      text_start = 0

      text.each_char.with_index do |ch, i|
        if in_escape
          escape_buf << ch
          if ch.match?(/[A-Za-z]/)
            leading_escapes << escape_buf
            escape_buf = String.new
            in_escape = false
            text_start = i + 1
          end
        elsif ch == "\e"
          in_escape = true
          escape_buf = ch
        else
          # First non-escape character, stop collecting leading escapes
          break
        end
      end

      # Now skip visible characters to get max_width remaining
      chars_to_skip = vis_width - max_width
      skipped = 0
      result = String.new
      in_escape = false

      text.each_char do |ch|
        if in_escape
          result << ch if skipped >= chars_to_skip
          in_escape = false if ch.match?(/[A-Za-z]/)
          next
        end

        if ch == "\e"
          in_escape = true
          result << ch if skipped >= chars_to_skip
          next
        end

        cw = char_width(ch.ord)
        if skipped < chars_to_skip
          skipped += cw
        else
          result << ch
        end
      end

      # Prepend leading escapes to preserve styling
      leading_escapes + result
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
      wrap(text, Palette::HIGHLIGHT, ANSI::RESET_FG + ANSI::RESET_INTENSITY)
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

    # Use for emoji characters - precomputes width and enables fast-path
    def emoji(char)
      SegmentWriter::EmojiSegment.new(char)
    end
  end

  # Security module for sanitizing user input to prevent command injection
  module Security
    # Shell metacharacters that could be used for command injection
    SHELL_METACHARACTERS = /[;|&$`<>(){}[\]\\!#*?~\n\r]/
    
    module_function
    
    # Sanitize user input to remove shell metacharacters
    # This prevents command injection attacks when user input might be used in shell contexts
    def sanitize_input(input)
      return "" if input.nil?
      # Remove all shell metacharacters to prevent command injection
      input.to_s.gsub(SHELL_METACHARACTERS, '')
    end
    
    # Check if input contains potentially dangerous shell metacharacters
    def contains_shell_metacharacters?(input)
      return false if input.nil?
      !!(input.to_s =~ SHELL_METACHARACTERS)
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

      cursor_row = nil
      cursor_col = nil
      current_row = 0

      # Render header at top
      @header.lines.each do |line|
        if @input_field && line.has_input?
          cursor_row = current_row + 1
          cursor_col = line.cursor_column(@input_field, @width)
        end
        line.render(@io, @width)
        current_row += 1
      end

      # Calculate available body space (total height minus header and footer)
      footer_lines = @footer.lines.length
      body_space = @height - current_row - footer_lines

      # Render body lines (limited to available space)
      body_rendered = 0
      @body.lines.each do |line|
        break if body_rendered >= body_space
        if @input_field && line.has_input?
          cursor_row = current_row + 1
          cursor_col = line.cursor_column(@input_field, @width)
        end
        line.render(@io, @width)
        current_row += 1
        body_rendered += 1
      end

      # Fill gap between body and footer with blank lines
      # Use \r to position at column 0, clear line, fill with spaces for reliability
      gap = body_space - body_rendered
      blank_line = "\r#{ANSI::CLEAR_EOL}#{' ' * (@width - 1)}\n"
      blank_line_no_newline = "\r#{ANSI::CLEAR_EOL}#{' ' * (@width - 1)}"
      gap.times do |i|
        # Last gap line without newline if no footer follows
        if i == gap - 1 && @footer.lines.empty?
          @io.write(blank_line_no_newline)
        else
          @io.write(blank_line)
        end
        current_row += 1
      end

      # Render footer at the bottom (sticky)
      @footer.lines.each_with_index do |line, idx|
        if @input_field && line.has_input?
          cursor_row = current_row + 1
          cursor_col = line.cursor_column(@input_field, @width)
        end
        # Last line: don't write \n to avoid scrolling
        if idx == footer_lines - 1
          line.render_no_newline(@io, @width)
        else
          line.render(@io, @width)
        end
        current_row += 1
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
      buffer << ANSI::CLEAR_EOL  # Clear line before rendering to remove stale content

      # Set background if present
      buffer << background if background && Tui.colors_enabled?

      # Maximum content to avoid wrap (leave room for newline)
      max_content = width - 1
      content_width = [width, 1].max

      left_text = @left.to_s(width: content_width)
      center_text = @center ? @center.to_s(width: content_width) : ""
      right_text = @right ? @right.to_s(width: content_width) : ""

      # Truncate left to fit line
      left_text = Metrics.truncate(left_text, max_content) if @truncate && !left_text.empty?
      left_width = left_text.empty? ? 0 : Metrics.visible_width(left_text)

      # Truncate center text to available space (never wrap)
      unless center_text.empty?
        max_center = max_content - left_width - 4
        if max_center > 0
          center_text = Metrics.truncate(center_text, max_center)
        else
          center_text = ""
        end
      end
      center_width = center_text.empty? ? 0 : Metrics.visible_width(center_text)

      # Calculate available space for right (need at least 1 space gap after left/center)
      used_by_left_center = left_width + center_width + (center_width > 0 ? 2 : 0)
      available_for_right = max_content - used_by_left_center - 1  # -1 for mandatory gap

      # Truncate right from the LEFT if needed (show trailing portion)
      right_width = 0
      unless right_text.empty?
        right_width = Metrics.visible_width(right_text)
        if available_for_right <= 0
          right_text = ""
          right_width = 0
        elsif right_width > available_for_right
          # Skip leading characters, keep trailing portion
          right_text = Metrics.truncate_from_start(right_text, available_for_right)
          right_width = Metrics.visible_width(right_text)
        end
      end

      # Calculate positions
      center_col = center_text.empty? ? 0 : [(max_content - center_width) / 2, left_width + 1].max
      right_col = right_text.empty? ? max_content : (max_content - right_width)

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
      fill_end = right_text.empty? ? max_content : right_col
      gap = fill_end - current_pos
      buffer << (" " * gap) if gap > 0

      # Write right content if present
      unless right_text.empty?
        buffer << right_text
        buffer << ANSI::RESET_FG
      end

      buffer << ANSI::RESET
      buffer << "\n"

      io.write(buffer)
    end

    def render_no_newline(io, width)
      buffer = String.new
      buffer << "\r"
      buffer << ANSI::CLEAR_EOL

      buffer << background if background && Tui.colors_enabled?

      max_content = width - 1
      content_width = [width, 1].max

      left_text = @left.to_s(width: content_width)
      center_text = @center ? @center.to_s(width: content_width) : ""
      right_text = @right ? @right.to_s(width: content_width) : ""

      # Truncate left to fit line
      left_text = Metrics.truncate(left_text, max_content) if @truncate && !left_text.empty?
      left_width = left_text.empty? ? 0 : Metrics.visible_width(left_text)

      # Truncate center text to available space (never wrap)
      unless center_text.empty?
        max_center = max_content - left_width - 4
        if max_center > 0
          center_text = Metrics.truncate(center_text, max_center)
        else
          center_text = ""
        end
      end
      center_width = center_text.empty? ? 0 : Metrics.visible_width(center_text)

      # Calculate available space for right (need at least 1 space gap)
      used_by_left_center = left_width + center_width + (center_width > 0 ? 2 : 0)
      available_for_right = max_content - used_by_left_center - 1

      # Truncate right from the LEFT if needed (show trailing portion)
      right_width = 0
      unless right_text.empty?
        right_width = Metrics.visible_width(right_text)
        if available_for_right <= 0
          right_text = ""
          right_width = 0
        elsif right_width > available_for_right
          right_text = Metrics.truncate_from_start(right_text, available_for_right)
          right_width = Metrics.visible_width(right_text)
        end
      end

      # Calculate positions
      center_col = center_text.empty? ? 0 : [(max_content - center_width) / 2, left_width + 1].max
      right_col = right_text.empty? ? max_content : (max_content - right_width)

      buffer << left_text unless left_text.empty?
      current_pos = left_width

      unless center_text.empty?
        gap_to_center = center_col - current_pos
        buffer << (" " * gap_to_center) if gap_to_center > 0
        buffer << center_text
        current_pos = center_col + center_width
      end

      fill_end = right_text.empty? ? max_content : right_col
      gap = fill_end - current_pos
      buffer << (" " * gap) if gap > 0

      unless right_text.empty?
        buffer << right_text
        buffer << ANSI::RESET_FG
      end

      buffer << ANSI::RESET
      # No newline at end

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

    # Emoji with precomputed width - triggers has_wide flag
    class EmojiSegment
      attr_reader :char, :width

      def initialize(char)
        @char = char.to_s
        # Precompute: emoji = 2, variation selectors = 0
        @width = 0
        @char_count = 0
        @char.each_codepoint do |code|
          w = Metrics.char_width(code)
          @width += w
          @char_count += 1 if w > 0  # Don't count zero-width chars
        end
      end

      def to_s
        @char
      end

      # How many characters this counts as in string.length
      def char_count
        @char.length
      end

      # Extra width beyond char_count (for width calculation)
      def width_delta
        @width - char_count
      end
    end

    attr_accessor :z_index

    def initialize(z_index: 1)
      @segments = []
      @z_index = z_index
      @has_wide = false
      @width_delta = 0  # Extra width from wide chars (width - bytecount)
    end

    def write(text = "")
      return self if text.nil?
      if text.respond_to?(:empty?) && text.empty?
        return self
      end

      segment = normalize_segment(text)
      if segment.is_a?(EmojiSegment)
        @has_wide = true
        @width_delta += segment.width_delta
      end
      @segments << segment
      self
    end

    def has_wide?
      @has_wide
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
        when EmojiSegment
          rendered << segment.to_s
        else
          rendered << segment.to_s
        end
      end
      rendered
    end

    # Fast width calculation using precomputed emoji widths
    def visible_width(rendered_str)
      if @has_wide
        # Has emoji - use delta: string length + extra width from wide chars
        stripped = rendered_str.include?("\e") ? rendered_str.gsub(/\e\[[0-9;]*[A-Za-z]/, '') : rendered_str
        stripped.length + @width_delta
      else
        # Pure ASCII - just string length
        stripped = rendered_str.include?("\e") ? rendered_str.gsub(/\e\[[0-9;]*[A-Za-z]/, '') : rendered_str
        stripped.length
      end
    end

    def empty?
      @segments.empty?
    end

    private

    def normalize_segment(text)
      case text
      when FillSegment, EmojiSegment
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
