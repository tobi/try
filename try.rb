#!/usr/bin/env ruby

require 'io/console'
require 'time'
require 'fileutils'

# Lightweight token-based printer for all UI output with double buffering
module UI
  TOKEN_MAP = {
    # Text formatting
    '{b}' => "\e[1;33m",           # Bold + Yellow (highlighted text, fuzzy match chars)
    '{/b}' => "\e[22m\e[39m",      # Reset bold + foreground
    '{dim}' => "\e[90m",           # Gray (bright black) - secondary/de-emphasized text
    '{text}' => "\e[0m\e[39m",     # Full reset - normal text
    '{reset}' => "\e[0m\e[39m\e[49m",  # Complete reset of all formatting
    '{/fg}' => "\e[39m",           # Reset foreground color only
    # Headings
    '{h1}' => "\e[1;38;5;208m",    # Bold + Orange (primary headings)
    '{h2}' => "\e[1;34m",          # Bold + Blue (secondary headings)
    # Selection
    '{section}' => "\e[1m",        # Bold - start of selected/highlighted section
    '{/section}' => "\e[0m",       # Full reset - end of selected section
    # Strikethrough (for deleted items)
    '{strike}' => "\e[48;5;52m",   # Dark red background
    '{/strike}' => "\e[49m",       # Reset background
    # Screen control
    '{clear_screen}' => "\e[2J", '{clear_line}' => "\e[2K", '{home}' => "\e[H", '{clear_below}' => "\e[0J",
    '{hide_cursor}' => "\e[?25l", '{show_cursor}' => "\e[?25h",
    # Input cursor
    '{cursor}' => "\e[7m \e[27m",  # Reverse video space as cursor block
  }.freeze

  @@buffer = []
  @@last_buffer = []
  @@current_line = ""

  @@height = nil
  @@width = nil
  @@expand_tokens = true
  @@force_colors = false  # Force color output even when not TTY (for testing)

  def self.print(text, io: STDERR)
    return if text.nil?
    @@current_line += text
  end

  def self.puts(text = "", io: STDERR)
    @@current_line += text
    @@buffer << @@current_line
    @@current_line = ""
  end

  def self.flush(io: STDERR)
    # Always finalize the current line into the buffer
    unless @@current_line.empty?
      @@buffer << @@current_line
      @@current_line = ""
    end

    # In non-TTY contexts (unless force_colors), print plain text without control codes
    unless io.tty? || @@force_colors
      plain = @@buffer.join("\n").gsub(/\{.*?\}/, '')
      io.print(plain)
      io.print("\n") unless plain.end_with?("\n")
      @@last_buffer = []
      @@buffer.clear
      @@current_line = ""
      io.flush
      return
    end

    # TTY or force_colors mode: output with formatting
    if io.tty?
      # Position cursor at home for TTY
      io.print("\e[H")
    end

    max_lines = [@@buffer.length, @@last_buffer.length].max
    reset = TOKEN_MAP['{reset}']

    (0...max_lines).each do |i|
      current_line = @@buffer[i] || ""
      last_line = @@last_buffer[i] || ""

      if current_line != last_line || @@force_colors
        # Move to line and clear it (only for TTY)
        if io.tty?
          io.print("\e[#{i + 1};1H\e[2K")
        end
        if !current_line.empty?
          processed_line = expand_tokens(current_line)
          io.print(processed_line)
          io.print(reset) if @@expand_tokens
          io.print("\n") if @@force_colors && !io.tty?
        end
      end
    end

    # Store current buffer as last buffer for next comparison
    @@last_buffer = @@buffer.dup
    @@buffer.clear
    @@current_line = ""

    io.flush
  end

  def self.cls(io: STDERR)
    @@current_line = ""
    @@buffer.clear
    @@last_buffer.clear
    io.print("\e[2J\e[H")  # Clear screen and go home
  end

  def self.hide_cursor
    STDERR.print("\e[?25l")
  end

  def self.show_cursor
    STDERR.print("\e[?25h")
  end

  def self.read_key
    input = STDIN.getc

    if input == "\e"
      input << STDIN.read_nonblock(3) rescue ""
      input << STDIN.read_nonblock(2) rescue ""
    end

    input
  end

  def self.height
    @@height ||= begin
      env_h = ENV['TRY_HEIGHT'].to_i
      return env_h if env_h > 0
      h = `tput lines 2>/dev/null`.strip.to_i
      h > 0 ? h : 24
    end
  end

  def self.width
    @@width ||= begin
      env_w = ENV['TRY_WIDTH'].to_i
      return env_w if env_w > 0
      w = `tput cols 2>/dev/null`.strip.to_i
      w > 0 ? w : 80
    end
  end

  def self.refresh_size
    @@height = nil
    @@width = nil
  end

  def self.disable_token_expansion
    @@expand_tokens = false
  end

  def self.disable_colors
    @@expand_tokens = false  # Disabling colors means tokens won't expand to ANSI
  end

  def self.force_colors
    @@force_colors = true
  end

  # Expand tokens in a string to ANSI sequences
  def self.expand_tokens(str)
    return str unless @@expand_tokens
    str.gsub(/\{.*?\}/) do |match|
      TOKEN_MAP.fetch(match) { match }  # Leave unknown tokens unchanged
    end
  end

end

class TrySelector
  TRY_PATH = ENV['TRY_PATH'] || File.expand_path("~/src/tries")

  def initialize(search_term = "", base_path: TRY_PATH, initial_input: nil, test_render_once: false, test_no_cls: false, test_keys: nil, test_confirm: nil)
    @search_term = search_term.gsub(/\s+/, '-')
    @cursor_pos = 0  # Navigation cursor (list position)
    @input_cursor_pos = 0  # Text cursor (position within search buffer)
    @scroll_offset = 0
    @input_buffer = initial_input ? initial_input.gsub(/\s+/, '-') : @search_term
    @input_cursor_pos = @input_buffer.length  # Start at end of buffer
    @selected = nil
    @all_trials = nil  # Memoized trials
    @base_path = base_path
    @delete_status = nil  # Status message for deletions
    @delete_mode = false  # Whether we're in deletion mode
    @marked_for_deletion = []  # Paths marked for deletion
    @test_render_once = test_render_once
    @test_no_cls = test_no_cls
    @test_keys = test_keys
    @test_had_keys = test_keys && !test_keys.empty?
    @test_confirm = test_confirm
    @old_winch_handler = nil  # Store original SIGWINCH handler
    @needs_redraw = false
    # Rename mode state
    @rename_mode = false
    @rename_entry = nil
    @rename_buffer = ""
    @rename_cursor_pos = 0
    @rename_error = nil

    FileUtils.mkdir_p(@base_path) unless Dir.exist?(@base_path)
  end

  def run
    # Always use STDERR for UI (it stays connected to TTY)
    # This allows stdout to be captured for the shell commands
    setup_terminal

    # In test mode with no keys, render once and exit without TTY requirements
    # If test_keys are provided, run the full loop
    if @test_render_once && (@test_keys.nil? || @test_keys.empty?)
      tries = get_tries
      render(tries)
      return nil
    end

    # Check if we have a TTY; allow tests with injected keys
    if !STDIN.tty? || !STDERR.tty?
      if @test_keys.nil? || @test_keys.empty?
        UI.puts "Error: try requires an interactive terminal"
        return nil
      end
      main_loop
    else
      STDERR.raw do
        main_loop
      end
    end
  ensure
    restore_terminal
  end

  private

  def setup_terminal
    unless @test_no_cls
      UI.cls
      UI.hide_cursor
    end

    # Handle terminal resize
    @old_winch_handler = Signal.trap('WINCH') do
      @needs_redraw = true
    end
  end

  def restore_terminal
    unless @test_no_cls
      UI.cls
      UI.show_cursor
    end

    # Restore original SIGWINCH handler
    Signal.trap('WINCH', @old_winch_handler) if @old_winch_handler
  end

  def load_all_tries
    # Load trials only once - single pass through directory
    @all_tries ||= begin
      tries = []
      Dir.foreach(@base_path) do |entry|
        # exclude . and .. but also .git, and any other hidden dirs.
        next if entry.start_with?('.')

        path = File.join(@base_path, entry)
        stat = File.stat(path)

        # Only include directories
        next unless stat.directory?

        tries << {
          name: "📁 #{entry}",
          basename: entry,
          basename_down: entry.downcase, 
          path: path,
          is_new: false,
          ctime: stat.ctime,
          mtime: stat.mtime
        }
      end
      tries
    end
  end

  def get_tries
    load_all_tries

    query_down = @input_buffer.downcase
    query_chars = query_down.chars

    # Always score trials (for time-based sorting even without search)
    scored_tries = @all_tries.map do |try_dir|
      # Pass the whole object and the pre-calculated query parts
      score = calculate_score(try_dir, query_down, query_chars, try_dir[:ctime], try_dir[:mtime])
      try_dir.merge(score: score)
    end

    # Filter only if searching, otherwise show all
    if @input_buffer.empty?
      scored_tries.sort_by { |t| -t[:score] }
    else
      # When searching, only show matches
      filtered = scored_tries.select { |t| t[:score] > 0 }
      filtered.sort_by { |t| -t[:score] }
    end
  end

  def calculate_score(try_dir, query_down, query_chars, ctime = nil, mtime = nil)
    text = try_dir[:basename]
    text_lower = try_dir[:basename_down] # Use pre-calculated value
    
    score = 0.0

    # generally we are looking for default date-prefixed directories
    if text.start_with?(/\d\d\d\d\-\d\d\-\d\d\-/)
      score += 2.0
    end

    # If there's a search query, calculate match score
    if !query_down.empty?
      query_len = query_chars.length
      text_len = text_lower.length
      
      last_pos = -1
      query_idx = 0
      
      i = 0
      while i < text_len
        break if query_idx >= query_len
        
        char = text_lower[i] # Access string by index
        
        if char == query_chars[query_idx]
          # Base point + word boundary bonus
          score += 1.0
          
          # Check previous char for boundary
          is_boundary = (i == 0) || (text_lower[i-1].match?(/\W/))
          score += 1.0 if is_boundary

          # Proximity bonus: 2/sqrt(gap+1) gives nice decay
          if last_pos >= 0
            gap = i - last_pos - 1
            score += 2.0 / Math.sqrt(gap + 1)
          end

          last_pos = i
          query_idx += 1
        end
        i += 1
      end

      # Return 0 if not all query chars matched
      return 0.0 if query_idx < query_len

      # Prefer shorter matches (density bonus)
      score *= (query_len.to_f / (last_pos + 1)) if last_pos >= 0

      # Length penalty - shorter text scores higher for same match
      # e.g., "v" matches better in "2025-08-13-v" than "2025-08-13-vbo-viz"
      score *= (10.0 / (text.length + 10.0))  # Smooth penalty that doesn't dominate
    end

    # Recency bonus based on mtime (hours since access)
    if mtime
      hours_since_access = (Time.now - mtime) / 3600.0
      score += 3.0 / Math.sqrt(hours_since_access + 1)
    end

    score
  end

  def main_loop
    loop do
      tries = get_tries
      show_create_new = !@input_buffer.empty?
      total_items = tries.length + (show_create_new ? 1 : 0)

      # Ensure cursor is within bounds
      @cursor_pos = [[@cursor_pos, 0].max, [total_items - 1, 0].max].min

      render(tries)

      key = read_key
      # nil means terminal resize - just re-render with new dimensions
      next unless key

      # Handle rename mode separately
      if @rename_mode
        break if handle_rename_key(key)
        next
      end

      case key
      when "\r"  # Enter (carriage return)
        if @delete_mode && !@marked_for_deletion.empty?
          # Confirm deletion of marked items
          confirm_batch_delete(tries)
          break if @selected
        elsif @cursor_pos < tries.length
          handle_selection(tries[@cursor_pos])
          break if @selected
        elsif show_create_new
          # Selected "Create new"
          handle_create_new
          break if @selected
        end
      when "\e[A", "\x10"  # Up arrow or Ctrl-P
        @cursor_pos = [@cursor_pos - 1, 0].max
      when "\e[B", "\x0E"  # Down arrow or Ctrl-N
        @cursor_pos = [@cursor_pos + 1, total_items - 1].min
      when "\e[C"  # Right arrow - ignore
        # Do nothing
      when "\e[D"  # Left arrow - ignore
        # Do nothing
      when "\x7F", "\b"  # Backspace
        if @input_cursor_pos > 0
          @input_buffer = @input_buffer[0...(@input_cursor_pos-1)] + @input_buffer[@input_cursor_pos..-1]
          @input_cursor_pos -= 1
        end
        @cursor_pos = 0  # Reset list selection when typing
      when "\x01"  # Ctrl-A - beginning of line
        @input_cursor_pos = 0
      when "\x05"  # Ctrl-E - end of line
        @input_cursor_pos = @input_buffer.length
      when "\x02"  # Ctrl-B - backward char
        @input_cursor_pos = [@input_cursor_pos - 1, 0].max
      when "\x06"  # Ctrl-F - forward char
        @input_cursor_pos = [@input_cursor_pos + 1, @input_buffer.length].min
      when "\x08"  # Ctrl-H - backward delete char (same as backspace)
        if @input_cursor_pos > 0
          @input_buffer = @input_buffer[0...(@input_cursor_pos-1)] + @input_buffer[@input_cursor_pos..-1]
          @input_cursor_pos -= 1
        end
        @cursor_pos = 0
      when "\x0B"  # Ctrl-K - kill to end of line
        @input_buffer = @input_buffer[0...@input_cursor_pos]
      when "\x17"  # Ctrl-W - delete word backward (alphanumeric)
        if @input_cursor_pos > 0
          # Start from cursor position and move backward
          pos = @input_cursor_pos - 1

          # Skip trailing non-alphanumeric
          while pos >= 0 && @input_buffer[pos] !~ /[a-zA-Z0-9]/
            pos -= 1
          end

          # Skip backward over alphanumeric chars
          while pos >= 0 && @input_buffer[pos] =~ /[a-zA-Z0-9]/
            pos -= 1
          end

          # Delete from pos+1 to cursor
          new_pos = pos + 1
          @input_buffer = @input_buffer[0...new_pos] + @input_buffer[@input_cursor_pos..-1]
          @input_cursor_pos = new_pos
        end
      when "\x04"  # Ctrl-D - toggle mark for deletion
        if @cursor_pos < tries.length
          path = tries[@cursor_pos][:path]
          if @marked_for_deletion.include?(path)
            @marked_for_deletion.delete(path)
          else
            @marked_for_deletion << path
            @delete_mode = true
          end
          # Exit delete mode if no more marks
          @delete_mode = false if @marked_for_deletion.empty?
        end
      when "\x14"  # Ctrl-T - create new try (immediate)
        handle_create_new
        break if @selected
      when "\x12"  # Ctrl-R - rename selected entry
        if @cursor_pos < tries.length
          start_rename(tries[@cursor_pos])
        end
      when "\x03", "\e"  # Ctrl-C or ESC
        if @delete_mode
          # Exit delete mode, clear marks
          @marked_for_deletion.clear
          @delete_mode = false
        else
          @selected = nil
          break
        end
      when String
        # Only accept printable characters, not escape sequences
        if key.length == 1 && key =~ /[a-zA-Z0-9\-\_\. ]/
          @input_buffer = @input_buffer[0...@input_cursor_pos] + key + @input_buffer[@input_cursor_pos..-1]
          @input_cursor_pos += 1
          @cursor_pos = 0  # Reset list selection when typing
        end
      end
    end

    @selected
  end

  def read_key
    if @test_keys && !@test_keys.empty?
      return @test_keys.shift
    end
    # In test mode with no more keys, auto-exit by returning ESC
    return "\e" if @test_had_keys && @test_keys && @test_keys.empty?

    # Use IO.select with timeout to allow checking for resize
    loop do
      if @needs_redraw
        @needs_redraw = false
        UI.refresh_size
        UI.cls
        return nil
      end
      ready = IO.select([STDIN], nil, nil, 0.1)
      return UI.read_key if ready
    end
  end

  def render(tries)
    term_width = UI.width
    term_height = UI.height

    # Use actual terminal width for separator lines
    separator = "─" * (term_width - 1)

    # Header
    UI.puts "{h1}📁 Try Selector{reset}"
    UI.puts "{dim}#{separator}{/fg}"

    # Search input with cursor at correct position
    before_cursor = @input_buffer[0...@input_cursor_pos]
    char_at_cursor = @input_buffer[@input_cursor_pos] || " "
    after_cursor = @input_buffer[(@input_cursor_pos + 1)..-1] || ""
    # Render cursor by inverting the character at cursor position
    UI.puts "{dim}Search:{/fg} {b}#{before_cursor}\e[7m#{char_at_cursor}\e[27m#{after_cursor}{/b}"
    UI.puts "{dim}#{separator}{/fg}"

    # Calculate visible window based on actual terminal height
    max_visible = [term_height - 8, 3].max
    show_create_new = !@input_buffer.empty?
    total_items = tries.length + (show_create_new ? 1 : 0)

    # Adjust scroll window
    if @cursor_pos < @scroll_offset
      @scroll_offset = @cursor_pos
    elsif @cursor_pos >= @scroll_offset + max_visible
      @scroll_offset = @cursor_pos - max_visible + 1
    end

    # Display items
    visible_end = [@scroll_offset + max_visible, total_items].min

    (@scroll_offset...visible_end).each do |idx|
      # Add blank line before "Create new"
      if idx == tries.length && tries.any? && idx >= @scroll_offset
        UI.puts
      end

      # Print cursor/selection indicator
      is_selected = idx == @cursor_pos
      UI.print(is_selected ? "{b}→ {/b}" : "  ")

      # Display try directory or "Create new" option
      if idx < tries.length
        try_dir = tries[idx]
        is_marked = @marked_for_deletion.include?(try_dir[:path])
        basename = try_dir[:basename]

        # Calculate metadata
        time_text = format_relative_time(try_dir[:mtime])
        score_text = sprintf("%.1f", try_dir[:score])
        meta_text = "#{time_text}, #{score_text}"
        meta_width = meta_text.length + 1  # +1 for leading space

        # Layout: "→ 📁 name                    meta" or "  📁 name..."
        # prefix = 5 chars ("→ 📁 " or "  📁 ")
        # Metadata is right-aligned. If name overlaps, metadata is hidden.
        prefix_width = 5
        meta_start = term_width - meta_width
        max_name_for_meta = meta_start - prefix_width - 1  # -1 for min gap

        # Max name width before truncation (leave 1 char at end)
        max_name_width = term_width - prefix_width - 1

        # Start strike formatting for marked items
        UI.print "{strike}" if is_marked

        # Render the folder/trash icon
        UI.print(is_marked ? "🗑️  " : "📁 ")

        # Start selection highlighting after icon
        UI.print "{section}" if is_selected

        # Format directory name with date styling
        if basename =~ /^(\d{4}-\d{2}-\d{2})-(.+)$/
          date_part = $1
          name_part = $2
          full_name = "#{date_part}-#{name_part}"

          # Truncate only if exceeds terminal width
          if full_name.length > max_name_width && max_name_width > 14
            available_for_name = max_name_width - 11 - 1 - 1  # date + dash + ellipsis
            name_part = name_part[0, available_for_name] + "…" if name_part.length > available_for_name + 1
            full_name = "#{date_part}-#{name_part}"
          end

          # Render the date part (faint)
          UI.print "{dim}#{date_part}{/fg}"

          # Render the separator
          separator_matches = !@input_buffer.empty? && @input_buffer.include?('-')
          UI.print(separator_matches ? "{b}-{/b}" : "{dim}-{/fg}")

          # Render the name part with match highlighting
          if !@input_buffer.empty?
            UI.print highlight_matches_for_selection(name_part, @input_buffer, is_selected)
          else
            UI.print name_part
          end

          display_text = full_name
        else
          # No date prefix
          name = basename
          if name.length > max_name_width && max_name_width > 2
            name = name[0, max_name_width - 1] + "…"
          end

          if !@input_buffer.empty?
            UI.print highlight_matches_for_selection(name, @input_buffer, is_selected)
          else
            UI.print name
          end
          display_text = name
        end

        UI.print "{/section}" if is_selected

        # Show metadata if name doesn't overlap its position
        if display_text.length <= max_name_for_meta
          padding_needed = meta_start - prefix_width - display_text.length
          UI.print " " * padding_needed
          UI.print "{dim}#{meta_text}{/fg}"
        end

        UI.print "{/strike}" if is_marked

      else
        # This is the "Create new" option
        UI.print "{section}" if is_selected

        date_prefix = Time.now.strftime("%Y-%m-%d")
        display_text = if @input_buffer.empty?
          "📂 Create new: #{date_prefix}-"
        else
          "📂 Create new: #{date_prefix}-#{@input_buffer}"
        end

        UI.print display_text

        # Pad to full width
        text_width = display_text.length
        padding_needed = term_width - 3 - text_width  # -3 for arrow + space
        UI.print " " * [padding_needed, 1].max
      end

      # End selection and reset all formatting
      UI.puts
    end

    # Scroll indicator if needed
    if total_items > max_visible
      UI.puts "{dim}#{separator}{/fg}"
      UI.puts "{dim}[#{@scroll_offset + 1}-#{visible_end}/#{total_items}]{/fg}"
    end

    # Instructions at bottom
    UI.puts "{dim}#{separator}{/fg}"

    # Show delete status, rename dialog, or instructions
    if @rename_mode
      render_rename_dialog(separator)
    elsif @delete_status
      UI.puts "{b}#{@delete_status}{/b}"
      @delete_status = nil  # Clear after showing
    elsif @delete_mode
      count = @marked_for_deletion.length
      UI.puts "{strike} DELETE MODE {/strike} #{count} marked  |  Ctrl-D: Toggle  Enter: Confirm  Esc: Cancel"
    else
      UI.puts "{dim}↑↓: Navigate  Enter: Select  Ctrl-T: New  Ctrl-D: Delete  Ctrl-R: Rename  Esc: Cancel{/fg}"
    end

    # Flush the double buffer
    UI.flush
  end


  def format_relative_time(time)
    return "?" unless time

    seconds = Time.now - time
    minutes = seconds / 60
    hours = minutes / 60
    days = hours / 24

    if seconds < 60
      "just now"
    elsif minutes < 60
      "#{minutes.to_i}m ago"
    elsif hours < 24
      "#{hours.to_i}h ago"
    elsif days < 7
      "#{days.to_i}d ago"
    else
      "#{(days/7).to_i}w ago"
    end
  end

  def truncate_with_ansi(text, max_length)
    # Simple truncation that preserves ANSI codes
    visible_count = 0
    result = ""
    in_ansi = false

    text.chars.each do |char|
      if char == "\e"
        in_ansi = true
        result += char
      elsif in_ansi
        result += char
        in_ansi = false if char == "m"
      else
        break if visible_count >= max_length
        result += char
        visible_count += 1
      end
    end

    result
  end

  def highlight_matches(text, query)
    return text if query.empty?

    result = ""
    text_lower = text.downcase
    query_lower = query.downcase
    query_chars = query_lower.chars
    query_index = 0

    text.chars.each_with_index do |char, i|
      if query_index < query_chars.length && text_lower[i] == query_chars[query_index]
        result += "{b}#{char}{/b}"  # Bold yellow for matches
        query_index += 1
      else
        result += char
      end
    end

    result
  end

  def highlight_matches_for_selection(text, query, is_selected)
    return text if query.empty?

    result = ""
    text_lower = text.downcase
    query_lower = query.downcase
    query_chars = query_lower.chars
    query_index = 0

    text.chars.each_with_index do |char, i|
      if query_index < query_chars.length && text_lower[i] == query_chars[query_index]
        result += "{b}#{char}{/b}"  # Bold yellow for matches
        query_index += 1
      else
        result += char
      end
    end

    result
  end

  # Rename mode methods
  def start_rename(entry)
    @rename_mode = true
    @rename_entry = entry
    @rename_buffer = entry[:basename].dup
    @rename_cursor_pos = @rename_buffer.length
    @rename_error = nil
    @delete_mode = false
    @marked_for_deletion.clear
  end

  def exit_rename
    @rename_mode = false
    @rename_entry = nil
    @rename_buffer = ""
    @rename_cursor_pos = 0
    @rename_error = nil
  end

  def handle_rename_key(key)
    case key
    when "\r"  # Enter - confirm rename
      return finalize_rename
    when "\e", "\x03"  # ESC or Ctrl-C - cancel
      exit_rename
      return false
    when "\x7F", "\b"  # Backspace
      if @rename_cursor_pos > 0
        @rename_buffer = @rename_buffer[0...(@rename_cursor_pos - 1)] + @rename_buffer[@rename_cursor_pos..-1].to_s
        @rename_cursor_pos -= 1
      end
      @rename_error = nil
    when "\x01"  # Ctrl-A - start of line
      @rename_cursor_pos = 0
    when "\x05"  # Ctrl-E - end of line
      @rename_cursor_pos = @rename_buffer.length
    when "\x02"  # Ctrl-B - back one char
      @rename_cursor_pos = [@rename_cursor_pos - 1, 0].max
    when "\x06"  # Ctrl-F - forward one char
      @rename_cursor_pos = [@rename_cursor_pos + 1, @rename_buffer.length].min
    when "\x0B"  # Ctrl-K - kill to end
      @rename_buffer = @rename_buffer[0...@rename_cursor_pos]
      @rename_error = nil
    when "\x17"  # Ctrl-W - delete word backward
      if @rename_cursor_pos > 0
        pos = @rename_cursor_pos - 1
        pos -= 1 while pos > 0 && @rename_buffer[pos] !~ /[a-zA-Z0-9]/
        pos -= 1 while pos > 0 && @rename_buffer[pos - 1] =~ /[a-zA-Z0-9]/
        @rename_buffer = @rename_buffer[0...pos] + @rename_buffer[@rename_cursor_pos..-1].to_s
        @rename_cursor_pos = pos
      end
      @rename_error = nil
    when String
      if key.length == 1 && key =~ /[a-zA-Z0-9\-_\.\s\/]/
        @rename_buffer = @rename_buffer[0...@rename_cursor_pos] + key + @rename_buffer[@rename_cursor_pos..-1].to_s
        @rename_cursor_pos += 1
        @rename_error = nil
      end
    end
    false
  end

  def finalize_rename
    new_name = @rename_buffer.strip.gsub(/\s+/, '-')
    old_name = @rename_entry ? @rename_entry[:basename] : nil

    if new_name.empty?
      @rename_error = "Name cannot be empty"
      return false
    end

    if new_name.include?('/')
      @rename_error = "Name cannot contain /"
      return false
    end

    if old_name && new_name == old_name
      exit_rename
      return false
    end

    if Dir.exist?(File.join(@base_path, new_name))
      @rename_error = "Directory exists: #{new_name}"
      return false
    end

    if old_name
      @selected = { type: :rename, old: old_name, new: new_name, base_path: @base_path }
    end
    exit_rename
    true
  end

  def render_rename_dialog(separator)
    return unless @rename_mode && @rename_entry

    UI.puts "{dim}#{separator}{/fg}"
    UI.puts "{h2}📝 Rename{reset}"
    UI.puts "Current: #{@rename_entry[:basename]}"

    before = @rename_buffer[0...@rename_cursor_pos]
    cursor_char = @rename_buffer[@rename_cursor_pos] || " "
    after = @rename_buffer[(@rename_cursor_pos + 1)..-1] || ""
    UI.puts "New name: #{before}\e[7m#{cursor_char}\e[27m#{after}"

    if @rename_error
      UI.puts "{b}#{@rename_error}{/b}"
    end

    UI.puts "{dim}Enter: Confirm  Esc: Cancel{/fg}"
    UI.puts "{dim}#{separator}{/fg}"
  end

  def handle_selection(try_dir)
    # Select existing try directory
    @selected = { type: :cd, path: try_dir[:path] }
  end

  def handle_create_new
    # Create new try directory
    date_prefix = Time.now.strftime("%Y-%m-%d")

    # If user already typed a name, use it directly
    if !@input_buffer.empty?
      final_name = "#{date_prefix}-#{@input_buffer}".gsub(/\s+/, '-')
      full_path = File.join(@base_path, final_name)
      @selected = { type: :mkdir, path: full_path }
    else
      # No name typed, prompt for one
      suggested_name = ""

      UI.cls  # Clear screen using UI system
      UI.puts "{h2}Enter new try name"
      UI.puts
      UI.puts "> {dim}#{date_prefix}-{/fg}"
      UI.flush
      STDERR.print("\e[?25h")

      entry = ""
      # Read user input in cooked mode
      STDERR.cooked do
        STDIN.iflush
        entry = gets.chomp
      end

      if entry.empty?
        return { type: :cancel, path: nil  }
      end

      final_name = "#{date_prefix}-#{entry}".gsub(/\s+/, '-')
      full_path = File.join(@base_path, final_name)

      @selected = { type: :mkdir, path: full_path }
    end
  end

  def confirm_batch_delete(tries)
    # Find marked items with their info
    marked_items = tries.select { |t| @marked_for_deletion.include?(t[:path]) }
    return if marked_items.empty?

    # Show delete confirmation dialog
    UI.cls
    UI.puts "{h2}Delete #{marked_items.length} Director#{marked_items.length == 1 ? 'y' : 'ies'}{reset}"
    UI.puts

    marked_items.each do |item|
      UI.puts "  {strike}📁 #{item[:basename]}{/strike}"
    end

    UI.puts
    UI.puts "{b}Type {/b}YES{b} to confirm deletion: {/b}"
    UI.flush
    STDERR.print("\e[?25h")  # Show cursor after flushing

    # Confirmation input: in tests, read from test_keys; otherwise read from TTY
    confirmation = ""
    if @test_keys && !@test_keys.empty?
      # Read chars from test_keys until Enter
      while @test_keys && !@test_keys.empty?
        ch = @test_keys.shift
        break if ch == "\r" || ch == "\n"
        confirmation += ch
      end
    elsif @test_confirm || !STDERR.tty?
      confirmation = (@test_confirm || STDIN.gets)&.chomp.to_s
    else
      STDERR.cooked do
        STDIN.iflush
        confirmation = gets.chomp
      end
    end

    if confirmation == "YES"
      begin
        base_real = File.realpath(@base_path)

        # Validate all paths first
        validated_paths = []
        marked_items.each do |item|
          target_real = File.realpath(item[:path])
          unless target_real.start_with?(base_real + "/")
            raise "Safety check failed: #{target_real} is not inside #{base_real}"
          end
          validated_paths << { path: target_real, basename: item[:basename] }
        end

        # Return delete action with all paths
        @selected = { type: :delete, paths: validated_paths, base_path: base_real }
        names = validated_paths.map { |p| p[:basename] }.join(", ")
        @delete_status = "Deleted: {strike}#{names}{/strike}"
        @all_tries = nil  # Clear cache
        @marked_for_deletion.clear
        @delete_mode = false
      rescue => e
        @delete_status = "Error: #{e.message}"
      end
    else
      @delete_status = "Delete cancelled"
      @marked_for_deletion.clear
      @delete_mode = false
    end

    # Hide cursor again for main UI
    STDERR.print("\e[?25l")
  end
end

# Main execution with OptionParser subcommands
if __FILE__ == $0

  VERSION = "1.2.0"

  def print_global_help
    text = <<~HELP
      {h1}try{reset} v#{VERSION} - ephemeral workspace manager

      To use try, add to your shell config:

        {dim}# bash/zsh (~/.bashrc or ~/.zshrc){/fg}
        {b}eval "$(try init ~/src/tries)"{/b}

        {dim}# fish (~/.config/fish/config.fish){/fg}
        {b}eval (try init ~/src/tries | string collect){/b}

      {h2}Usage:{reset}
        try [query]           Interactive directory selector
        try clone <url>       Clone repo into dated directory
        try worktree <name>   Create worktree from current git repo
        try --help            Show this help

      {h2}Commands:{reset}
        init [path]           Output shell function definition
        clone <url> [name]    Clone git repo into date-prefixed directory
        worktree <name>       Create worktree in dated directory

      {h2}Examples:{reset}
        try                   Open interactive selector
        try project           Selector with initial filter
        try clone https://github.com/user/repo
        try worktree feature-branch

      {h2}Manual mode (without alias):{reset}
        try exec [query]      Output shell script to eval

      {h2}Defaults:{reset}
        Default path: {dim}~/src/tries{/fg}
        Current: {dim}#{TrySelector::TRY_PATH}{/fg}
    HELP
    # Help should not manipulate the screen; print plainly to STDOUT.
    # Expand tokens to ANSI when TTY, strip when not TTY (unless --no-expand-tokens keeps them)
    out = UI.expand_tokens(text)
    # If tokens weren't expanded (no-expand mode), keep them. Otherwise strip if non-tty.
    if STDOUT.tty? || out.include?('{')
      # TTY or tokens preserved by no-expand mode
    else
      out = text.gsub(/\{.*?\}/, '')
    end
    STDOUT.print(out)
  end

  # Process color-related flags early
  if ARGV.delete('--no-expand-tokens')
    UI.disable_token_expansion
  end

  # --no-colors disables ANSI color output
  if ARGV.delete('--no-colors')
    UI.disable_colors
  end

  # NO_COLOR environment variable disables colors (standard convention)
  if ENV['NO_COLOR'] && !ENV['NO_COLOR'].empty?
    UI.disable_colors
  end

  # Global help: show for --help/-h anywhere
  if ARGV.include?("--help") || ARGV.include?("-h")
    print_global_help
    exit 0
  end

  # Version flag
  if ARGV.include?("--version") || ARGV.include?("-v")
    puts "try #{VERSION}"
    exit 0
  end

  # Helper to extract a "--name VALUE" or "--name=VALUE" option from args (last one wins)
  def extract_option_with_value!(args, opt_name)
    i = args.rindex { |a| a == opt_name || a.start_with?("#{opt_name}=") }
    return nil unless i
    arg = args.delete_at(i)
    if arg.include?('=')
      arg.split('=', 2)[1]
    else
      args.delete_at(i)
    end
  end

  def parse_git_uri(uri)
    # Remove .git suffix if present
    uri = uri.sub(/\.git$/, '')

    # Handle different git URI formats
    if uri.match(%r{^https?://github\.com/([^/]+)/([^/]+)})
      # https://github.com/user/repo
      user, repo = $1, $2
      return { user: user, repo: repo, host: 'github.com' }
    elsif uri.match(%r{^git@github\.com:([^/]+)/([^/]+)})
      # git@github.com:user/repo
      user, repo = $1, $2
      return { user: user, repo: repo, host: 'github.com' }
    elsif uri.match(%r{^https?://([^/]+)/([^/]+)/([^/]+)})
      # https://gitlab.com/user/repo or other git hosts
      host, user, repo = $1, $2, $3
      return { user: user, repo: repo, host: host }
    elsif uri.match(%r{^git@([^:]+):([^/]+)/([^/]+)})
      # git@host:user/repo
      host, user, repo = $1, $2, $3
      return { user: user, repo: repo, host: host }
    else
      return nil
    end
  end

  def generate_clone_directory_name(git_uri, custom_name = nil)
    return custom_name if custom_name && !custom_name.empty?

    parsed = parse_git_uri(git_uri)
    return nil unless parsed

    date_prefix = Time.now.strftime("%Y-%m-%d")
    "#{date_prefix}-#{parsed[:user]}-#{parsed[:repo]}"
  end

  def is_git_uri?(arg)
    return false unless arg
    arg.match?(%r{^(https?://|git@)}) || arg.include?('github.com') || arg.include?('gitlab.com') || arg.end_with?('.git')
  end

  # Extract all options BEFORE getting command (they can appear anywhere)
  tries_path = extract_option_with_value!(ARGV, '--path') || TrySelector::TRY_PATH
  tries_path = File.expand_path(tries_path)

  # Test-only flags (undocumented; aid acceptance tests)
  # Must be extracted before command shift since they can come before command
  and_type = extract_option_with_value!(ARGV, '--and-type')
  and_exit = !!ARGV.delete('--and-exit')
  and_keys_raw = extract_option_with_value!(ARGV, '--and-keys')
  and_confirm = extract_option_with_value!(ARGV, '--and-confirm')
  # Note: --no-expand-tokens and --no-colors are processed early (before --help check)

  # Enable color output in test mode for proper output verification
  if and_exit || and_keys_raw
    UI.force_colors
  end

  command = ARGV.shift

  def parse_test_keys(spec)
    return nil unless spec && !spec.empty?

    # Detect mode: if contains comma OR is purely uppercase letters/hyphens, use token mode
    # Otherwise use raw character mode (for spec tests that pass literal key sequences)
    use_token_mode = spec.include?(',') || spec.match?(/^[A-Z\-]+$/)

    if use_token_mode
      tokens = spec.split(/,\s*/)
      keys = []
      tokens.each do |tok|
        up = tok.upcase
        case up
        when 'UP' then keys << "\e[A"
        when 'DOWN' then keys << "\e[B"
        when 'LEFT' then keys << "\e[D"
        when 'RIGHT' then keys << "\e[C"
        when 'ENTER' then keys << "\r"
        when 'ESC' then keys << "\e"
        when 'BACKSPACE' then keys << "\x7F"
        when 'CTRL-A', 'CTRLA' then keys << "\x01"
        when 'CTRL-B', 'CTRLB' then keys << "\x02"
        when 'CTRL-D', 'CTRLD' then keys << "\x04"
        when 'CTRL-E', 'CTRLE' then keys << "\x05"
        when 'CTRL-F', 'CTRLF' then keys << "\x06"
        when 'CTRL-H', 'CTRLH' then keys << "\x08"
        when 'CTRL-K', 'CTRLK' then keys << "\x0B"
        when 'CTRL-N', 'CTRLN' then keys << "\x0E"
        when 'CTRL-P', 'CTRLP' then keys << "\x10"
        when 'CTRL-R', 'CTRLR' then keys << "\x12"
        when 'CTRL-T', 'CTRLT' then keys << "\x14"
        when 'CTRL-W', 'CTRLW' then keys << "\x17"
        when /^TYPE=(.*)$/
          $1.each_char { |ch| keys << ch }
        else
          keys << tok if tok.length == 1
        end
      end
      keys
    else
      # Raw character mode: each character (including escape sequences) is a key
      keys = []
      i = 0
      while i < spec.length
        if spec[i] == "\e" && i + 2 < spec.length && spec[i + 1] == '['
          # Escape sequence like \e[A for arrow keys
          keys << spec[i, 3]
          i += 3
        else
          keys << spec[i]
          i += 1
        end
      end
      keys
    end
  end
  and_keys = parse_test_keys(and_keys_raw)

  def cmd_clone!(args, tries_path)
    git_uri = args.shift
    custom_name = args.shift

    unless git_uri
      warn "Error: git URI required for clone command"
      warn "Usage: try clone <git-uri> [name]"
      exit 1
    end

    dir_name = generate_clone_directory_name(git_uri, custom_name)
    unless dir_name
      warn "Error: Unable to parse git URI: #{git_uri}"
      exit 1
    end

    script_clone(File.join(tries_path, dir_name), git_uri)
  end

  def cmd_init!(args, tries_path)
    script_path = File.expand_path($0)

    if args[0] && args[0].start_with?('/')
      tries_path = File.expand_path(args.shift)
    end

    path_arg = tries_path ? " --path '#{tries_path}'" : ""
    bash_or_zsh_script = <<~SHELL
      try() {
        local out
        out=$(/usr/bin/env ruby '#{script_path}' exec#{path_arg} "$@" 2>/dev/tty)
        if [ $? -eq 0 ]; then
          eval "$out"
        else
          echo "$out"
        fi
      }
    SHELL

    fish_script = <<~SHELL
      function try
        set -l out (/usr/bin/env ruby '#{script_path}' exec#{path_arg} $argv 2>/dev/tty | string collect)
        if test $status -eq 0
          eval $out
        else
          echo $out
        end
      end
    SHELL

    puts fish? ? fish_script : bash_or_zsh_script
    exit 0
  end

  def cmd_cd!(args, tries_path, and_type, and_exit, and_keys, and_confirm)
    if args.first == "clone"
      return cmd_clone!(args[1..-1] || [], tries_path)
    end

    # Support: try . [name] and try ./path [name]
    if args.first && args.first.start_with?('.')
      path_arg = args.shift
      custom = args.join(' ')
      repo_dir = File.expand_path(path_arg)
      # Bare "try ." requires a name argument (too easy to invoke accidentally)
      if path_arg == '.' && (custom.nil? || custom.strip.empty?)
        STDERR.puts "Error: 'try .' requires a name argument"
        STDERR.puts "Usage: try . <name>"
        exit 1
      end
      base = if custom && !custom.strip.empty?
        custom.gsub(/\s+/, '-')
      else
        File.basename(repo_dir)
      end
      date_prefix = Time.now.strftime("%Y-%m-%d")
      base = resolve_unique_name_with_versioning(tries_path, date_prefix, base)
      full_path = File.join(tries_path, "#{date_prefix}-#{base}")
      # Use worktree if .git exists (file in worktrees, directory in regular repos)
      if File.exist?(File.join(repo_dir, '.git'))
        return script_worktree(full_path, repo_dir)
      else
        return script_mkdir_cd(full_path)
      end
    end

    search_term = args.join(' ')

    # Git URL shorthand → clone workflow
    if is_git_uri?(search_term.split.first)
      git_uri, custom_name = search_term.split(/\s+/, 2)
      dir_name = generate_clone_directory_name(git_uri, custom_name)
      unless dir_name
        warn "Error: Unable to parse git URI: #{git_uri}"
        exit 1
      end
      full_path = File.join(tries_path, dir_name)
      return script_clone(full_path, git_uri)
    end

    # Regular interactive selector
    selector = TrySelector.new(
      search_term,
      base_path: tries_path,
      initial_input: and_type,
      test_render_once: and_exit,
      test_no_cls: (and_exit || (and_keys && !and_keys.empty?)),
      test_keys: and_keys,
      test_confirm: and_confirm
    )
    result = selector.run
    return nil unless result

    case result[:type]
    when :delete
      script_delete(result[:paths], result[:base_path])
    when :mkdir
      script_mkdir_cd(result[:path])
    when :rename
      script_rename(result[:base_path], result[:old], result[:new])
    else
      script_cd(result[:path])
    end
  end

  # --- Shell script helpers ---
  SCRIPT_WARNING = "# if you can read this, you didn't launch try from an alias. run try --help."

  def q(str)
    "'" + str.gsub("'", %q('"'"')) + "'"
  end

  def emit_script(cmds)
    puts SCRIPT_WARNING
    cmds.each_with_index do |cmd, i|
      if i == 0
        print cmd
      else
        print "  #{cmd}"
      end
      if i < cmds.length - 1
        puts " && \\"
      else
        puts
      end
    end
  end

  def script_cd(path)
    ["touch #{q(path)}", "cd #{q(path)}"]
  end

  def script_mkdir_cd(path)
    ["mkdir -p #{q(path)}"] + script_cd(path)
  end

  def script_clone(path, uri)
    ["mkdir -p #{q(path)}", "echo #{q(UI.expand_tokens("Using {b}git clone{/b} to create this trial from #{uri}."))}", "git clone '#{uri}' #{q(path)}"] + script_cd(path)
  end

  def script_worktree(path, repo = nil)
    r = repo ? q(repo) : nil
    worktree_cmd = if r
      "/usr/bin/env sh -c 'if git -C #{r} rev-parse --is-inside-work-tree >/dev/null 2>&1; then repo=$(git -C #{r} rev-parse --show-toplevel); git -C \"$repo\" worktree add --detach #{q(path)} >/dev/null 2>&1 || true; fi; exit 0'"
    else
      "/usr/bin/env sh -c 'if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then repo=$(git rev-parse --show-toplevel); git -C \"$repo\" worktree add --detach #{q(path)} >/dev/null 2>&1 || true; fi; exit 0'"
    end
    src = repo || Dir.pwd
    ["mkdir -p #{q(path)}", "echo #{q(UI.expand_tokens("Using {b}git worktree{/b} to create this trial from #{src}."))}", worktree_cmd] + script_cd(path)
  end

  def script_delete(paths, base_path)
    cmds = ["cd #{q(base_path)}"]
    paths.each { |item| cmds << "test -d #{q(item[:basename])} && rm -rf #{q(item[:basename])}" }
    cmds << "( cd #{q(Dir.pwd)} 2>/dev/null || cd \"$HOME\" )"
    cmds
  end

  def script_rename(base_path, old_name, new_name)
    [
      "cd #{q(base_path)}",
      "mv #{q(old_name)} #{q(new_name)}",
      "cd #{q(File.join(base_path, new_name))}"
    ]
  end

  # Return a unique directory name under tries_path by appending -2, -3, ... if needed
  def unique_dir_name(tries_path, dir_name)
    candidate = dir_name
    i = 2
    while Dir.exist?(File.join(tries_path, candidate))
      candidate = "#{dir_name}-#{i}"
      i += 1
    end
    candidate
  end

  # If the given base ends with digits and today's dir already exists,
  # bump the trailing number to the next available one for today.
  # Otherwise, fall back to unique_dir_name with -2, -3 suffixes.
  def resolve_unique_name_with_versioning(tries_path, date_prefix, base)
    initial = "#{date_prefix}-#{base}"
    return base unless Dir.exist?(File.join(tries_path, initial))

    m = base.match(/^(.*?)(\d+)$/)
    if m
      stem, n = m[1], m[2].to_i
      candidate_num = n + 1
      loop do
        candidate_base = "#{stem}#{candidate_num}"
        candidate_full = File.join(tries_path, "#{date_prefix}-#{candidate_base}")
        return candidate_base unless Dir.exist?(candidate_full)
        candidate_num += 1
      end
    else
      # No numeric suffix; use -2 style uniqueness on full name
      return unique_dir_name(tries_path, "#{date_prefix}-#{base}").sub(/^#{Regexp.escape(date_prefix)}-/, '')
    end
  end

  # shell detection for init wrapper
  # Check $SHELL first (user's configured shell), then parent process as fallback
  def fish?
    shell = ENV["SHELL"]
    shell = `ps c -p #{Process.ppid} -o 'ucomm='`.strip rescue nil if shell.to_s.empty?

    shell&.include?('fish')
  end


  # Helper to generate worktree path from repo
  def worktree_path(tries_path, repo_dir, custom_name)
    base = if custom_name && !custom_name.strip.empty?
      custom_name.gsub(/\s+/, '-')
    else
      begin; File.basename(File.realpath(repo_dir)); rescue; File.basename(repo_dir); end
    end
    date_prefix = Time.now.strftime("%Y-%m-%d")
    base = resolve_unique_name_with_versioning(tries_path, date_prefix, base)
    File.join(tries_path, "#{date_prefix}-#{base}")
  end

  case command
  when nil
    print_global_help
    exit 2
  when 'clone'
    emit_script(cmd_clone!(ARGV, tries_path))
    exit 0
  when 'init'
    cmd_init!(ARGV, tries_path)
    exit 0
  when 'exec'
    sub = ARGV.first
    case sub
    when 'clone'
      ARGV.shift
      emit_script(cmd_clone!(ARGV, tries_path))
    when 'worktree'
      ARGV.shift
      repo = ARGV.shift
      repo_dir = repo && repo != 'dir' ? File.expand_path(repo) : Dir.pwd
      full_path = worktree_path(tries_path, repo_dir, ARGV.join(' '))
      emit_script(script_worktree(full_path, repo_dir == Dir.pwd ? nil : repo_dir))
    when 'cd'
      ARGV.shift
      script = cmd_cd!(ARGV, tries_path, and_type, and_exit, and_keys, and_confirm)
      if script
        emit_script(script)
        exit 0
      else
        puts "Cancelled."
        exit 1
      end
    else
      script = cmd_cd!(ARGV, tries_path, and_type, and_exit, and_keys, and_confirm)
      if script
        emit_script(script)
        exit 0
      else
        puts "Cancelled."
        exit 1
      end
    end
  when 'worktree'
    repo = ARGV.shift
    repo_dir = repo && repo != 'dir' ? File.expand_path(repo) : Dir.pwd
    full_path = worktree_path(tries_path, repo_dir, ARGV.join(' '))
    # Explicit worktree command always emits worktree script
    emit_script(script_worktree(full_path, repo_dir == Dir.pwd ? nil : repo_dir))
    exit 0
  else
    # Default: try [query] - same as try exec [query]
    script = cmd_cd!(ARGV.unshift(command), tries_path, and_type, and_exit, and_keys, and_confirm)
    if script
      emit_script(script)
      exit 0
    else
      puts "Cancelled."
      exit 1
    end
  end

end
