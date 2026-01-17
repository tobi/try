#!/usr/bin/env ruby

require 'io/console'
require 'time'
require 'fileutils'
require_relative 'lib/tui'
require_relative 'lib/fuzzy'

class TrySelector
  include Tui::Helpers
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

    FileUtils.mkdir_p(@base_path) unless Dir.exist?(@base_path)
  end

  def run
    # Always use STDERR for rendering (it stays connected to TTY)
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
        STDERR.puts "Error: try requires an interactive terminal"
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
      # Switch to alternate screen buffer (like vim, less, etc.)
      STDERR.print(Tui::ANSI::ALT_SCREEN_ON)
      STDERR.print(Tui::ANSI::CLEAR_SCREEN)
      STDERR.print(Tui::ANSI::HOME)
      STDERR.print(Tui::ANSI::CURSOR_BLINK)
    end

    @old_winch_handler = Signal.trap('WINCH') { @needs_redraw = true }
  end

  def restore_terminal
    unless @test_no_cls
      STDERR.print(Tui::ANSI::RESET)
      STDERR.print(Tui::ANSI::CURSOR_DEFAULT)
      # Return to main screen buffer
      STDERR.print(Tui::ANSI::ALT_SCREEN_OFF)
    end

    Signal.trap('WINCH', @old_winch_handler) if @old_winch_handler
  end

  def load_all_tries
    # Load trials only once - single pass through directory
    @all_tries ||= begin
      tries = []
      now = Time.now
      Dir.foreach(@base_path) do |entry|
        # exclude . and .. but also .git, and any other hidden dirs.
        next if entry.start_with?('.')

        path = File.join(@base_path, entry)
        stat = File.stat(path)

        # Only include directories
        next unless stat.directory?

        # Compute base_score from recency + date prefix bonus
        mtime = stat.mtime
        hours_since_access = (now - mtime) / 3600.0
        base_score = 3.0 / Math.sqrt(hours_since_access + 1)

        # Bonus for date-prefixed directories
        base_score += 2.0 if entry.match?(/^\d{4}-\d{2}-\d{2}-/)

        tries << {
          text: entry,
          basename: entry,
          path: path,
          is_new: false,
          ctime: stat.ctime,
          mtime: mtime,
          base_score: base_score
        }
      end
      tries
    end
  end

  # Result wrapper to avoid Hash#merge allocation per entry
  TryEntry = Data.define(:data, :score, :highlight_positions) do
    def [](key)
      case key
      when :score then score
      when :highlight_positions then highlight_positions
      else data[key]
      end
    end

    def method_missing(name, *)
      data[name]
    end

    def respond_to_missing?(name, include_private = false)
      data.key?(name) || super
    end
  end

  def get_tries
    load_all_tries
    @fuzzy ||= Fuzzy.new(@all_tries)

    results = []
    @fuzzy.match(@input_buffer).each do |entry, positions, score|
      results << TryEntry.new(entry, score, positions)
    end
    results
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
          run_rename_dialog(tries[@cursor_pos])
          break if @selected
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
        clear_screen unless @test_no_cls
        return nil
      end
      ready = IO.select([STDIN], nil, nil, 0.1)
      return read_keypress if ready
    end
  end

  def read_keypress
    input = STDIN.getc
    return nil if input.nil?

    if input == "\e"
      input << STDIN.read_nonblock(3) rescue ""
      input << STDIN.read_nonblock(2) rescue ""
    end

    input
  end

  def clear_screen
    STDERR.print("\e[2J\e[H")
  end

  def hide_cursor
    STDERR.print(Tui::ANSI::HIDE)
  end

  def show_cursor
    STDERR.print(Tui::ANSI::SHOW)
  end

  def render(tries)
    screen = Tui::Screen.new(io: STDERR)
    width = screen.width
    height = screen.height

    screen.header.add_line { |line| line.write << emoji("🏠") << Tui::Text.accent(" Try Directory Selection") }
    screen.header.add_line { |line| line.write.write_dim(fill("─")) }
    screen.header.add_line do |line|
      prefix = "Search: "
      line.write.write_dim(prefix)
      line.write << screen.input("", value: @input_buffer, cursor: @input_cursor_pos).to_s
      line.mark_has_input(Tui::Metrics.visible_width(prefix))
    end
    screen.header.add_line { |line| line.write.write_dim(fill("─")) }

    # Add footer first to get accurate line count
    screen.footer.add_line { |line| line.write.write_dim(fill("─")) }
    if @delete_status
      screen.footer.add_line { |line| line.write.write_bold(@delete_status) }
      @delete_status = nil
    elsif @delete_mode
      screen.footer.add_line(background: Tui::Palette::DANGER_BG) do |line|
        line.write.write_bold(" DELETE MODE ")
        line.write << " #{@marked_for_deletion.length} marked  |  Ctrl-D: Toggle  Enter: Confirm  Esc: Cancel"
      end
    else
      screen.footer.add_line do |line|
        line.center.write_dim("↑/↓: Navigate  Enter: Select  ^R: Rename  ^D: Delete  Esc: Cancel")
      end
    end

    # Calculate max visible from actual header/footer counts
    header_lines = screen.header.lines.length
    footer_lines = screen.footer.lines.length
    max_visible = [height - header_lines - footer_lines, 3].max
    show_create_new = !@input_buffer.empty?
    total_items = tries.length + (show_create_new ? 1 : 0)

    if @cursor_pos < @scroll_offset
      @scroll_offset = @cursor_pos
    elsif @cursor_pos >= @scroll_offset + max_visible
      @scroll_offset = @cursor_pos - max_visible + 1
    end

    visible_end = [@scroll_offset + max_visible, total_items].min

    (@scroll_offset...visible_end).each do |idx|
      if idx == tries.length && tries.any? && idx >= @scroll_offset
        screen.body.add_line
      end

      if idx < tries.length
        render_entry_line(screen, tries[idx], idx == @cursor_pos, width)
      else
        render_create_line(screen, idx == @cursor_pos, width)
      end
    end

    screen.flush
  end

  def render_entry_line(screen, entry, is_selected, width)
    is_marked = @marked_for_deletion.include?(entry[:path])
    # Marked items always show red; selection shows via arrow only
    background = if is_marked
      Tui::Palette::DANGER_BG
    elsif is_selected
      Tui::Palette::SELECTED_BG
    end

    line = screen.body.add_line(background: background)
    line.write << (is_selected ? Tui::Text.highlight("→ ") : "  ")
    line.write << (is_marked ? emoji("🗑️") : emoji("📁")) << " "

    plain_name, rendered_name = formatted_entry_name(entry)
    prefix_width = 5
    meta_text = "#{format_relative_time(entry[:mtime])}, #{format('%.1f', entry[:score])}"

    # Only truncate name if it exceeds total line width (not to make room for metadata)
    max_name_width = width - prefix_width - 1
    if plain_name.length > max_name_width && max_name_width > 2
      display_rendered = truncate_with_ansi(rendered_name, max_name_width - 1) + "…"
    else
      display_rendered = rendered_name
    end

    line.write << display_rendered

    # Right content is lower layer - will be overwritten by left if they overlap
    line.right.write_dim(meta_text)
  end

  def render_create_line(screen, is_selected, width)
    background = is_selected ? Tui::Palette::SELECTED_BG : nil
    line = screen.body.add_line(background: background)
    line.write << (is_selected ? Tui::Text.highlight("→ ") : "  ")
    date_prefix = Time.now.strftime("%Y-%m-%d")
    label = if @input_buffer.empty?
      "📂 Create new: #{date_prefix}-"
    else
      "📂 Create new: #{date_prefix}-#{@input_buffer}"
    end
    line.write << label
  end

  def formatted_entry_name(entry)
    basename = entry[:basename]
    positions = entry[:highlight_positions] || []

    if basename =~ /^(\d{4}-\d{2}-\d{2})-(.+)$/
      date_part = $1
      name_part = $2
      date_len = date_part.length + 1  # +1 for the hyphen

      rendered = Tui::Text.dim(date_part)
      # Highlight hyphen if it's in positions
      rendered += positions.include?(10) ? Tui::Text.highlight('-') : Tui::Text.dim('-')
      rendered += highlight_with_positions(name_part, positions, date_len)
      ["#{date_part}-#{name_part}", rendered]
    else
      [basename, highlight_with_positions(basename, positions, 0)]
    end
  end

  def highlight_with_positions(text, positions, offset)
    result = ""
    text.chars.each_with_index do |char, i|
      if positions.include?(i + offset)
        result += Tui::Text.highlight(char)
      else
        result += char
      end
    end
    result
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

  # Rename dialog - dedicated screen similar to delete
  def run_rename_dialog(entry)
    @delete_mode = false
    @marked_for_deletion.clear

    current_name = entry[:basename]
    rename_buffer = current_name.dup
    rename_cursor = rename_buffer.length
    rename_error = nil

    loop do
      render_rename_dialog(current_name, rename_buffer, rename_cursor, rename_error)

      ch = read_key
      case ch
      when "\r"  # Enter - confirm
        result = finalize_rename(entry, rename_buffer)
        if result == true
          break
        else
          rename_error = result  # Error message string
        end
      when "\e", "\x03"  # ESC or Ctrl-C - cancel
        break
      when "\x7F", "\b"  # Backspace
        if rename_cursor > 0
          rename_buffer = rename_buffer[0...(rename_cursor - 1)] + rename_buffer[rename_cursor..].to_s
          rename_cursor -= 1
        end
        rename_error = nil
      when "\x01"  # Ctrl-A - start of line
        rename_cursor = 0
      when "\x05"  # Ctrl-E - end of line
        rename_cursor = rename_buffer.length
      when "\x02"  # Ctrl-B - back one char
        rename_cursor = [rename_cursor - 1, 0].max
      when "\x06"  # Ctrl-F - forward one char
        rename_cursor = [rename_cursor + 1, rename_buffer.length].min
      when "\x0B"  # Ctrl-K - kill to end
        rename_buffer = rename_buffer[0...rename_cursor]
        rename_error = nil
      when "\x17"  # Ctrl-W - delete word backward
        if rename_cursor > 0
          pos = rename_cursor - 1
          pos -= 1 while pos > 0 && rename_buffer[pos] !~ /[a-zA-Z0-9]/
          pos -= 1 while pos > 0 && rename_buffer[pos - 1] =~ /[a-zA-Z0-9]/
          rename_buffer = rename_buffer[0...pos] + rename_buffer[rename_cursor..].to_s
          rename_cursor = pos
        end
        rename_error = nil
      when String
        if ch.length == 1 && ch =~ /[a-zA-Z0-9\-_\.\s\/]/
          rename_buffer = rename_buffer[0...rename_cursor] + ch + rename_buffer[rename_cursor..].to_s
          rename_cursor += 1
          rename_error = nil
        end
      end
    end

    @needs_redraw = true
  end

  def render_rename_dialog(current_name, rename_buffer, rename_cursor, rename_error)
    screen = Tui::Screen.new(io: STDERR)

    screen.header.add_line do |line|
      line.center << emoji("✏️") << Tui::Text.accent("  Rename directory")
    end
    screen.header.add_line { |line| line.write.write_dim(fill("─")) }

    screen.body.add_line do |line|
      line.write << emoji("📁") << " #{current_name}"
    end

    # Add empty lines, then centered input prompt
    2.times { screen.body.add_line }
    screen.body.add_line do |line|
      prefix = "New name: "
      line.center.write_dim(prefix)
      line.center << screen.input("", value: rename_buffer, cursor: rename_cursor).to_s
      # Input displays buffer + trailing space when cursor at end
      # Use (width - 1) to match Line.render's max_content calculation
      input_width = [rename_buffer.length, rename_cursor + 1].max
      prefix_width = Tui::Metrics.visible_width(prefix)
      max_content = screen.width - 1
      center_start = (max_content - prefix_width - input_width) / 2
      line.mark_has_input(center_start + prefix_width)
    end

    if rename_error
      screen.body.add_line
      screen.body.add_line { |line| line.center.write_bold(rename_error) }
    end

    screen.footer.add_line { |line| line.write.write_dim(fill("─")) }
    screen.footer.add_line { |line| line.center.write_dim("Enter: Confirm  Esc: Cancel") }

    screen.flush
  end

  def finalize_rename(entry, rename_buffer)
    new_name = rename_buffer.strip.gsub(/\s+/, '-')
    old_name = entry[:basename]

    return "Name cannot be empty" if new_name.empty?
    return "Name cannot contain /" if new_name.include?('/')
    return true if new_name == old_name  # No change, just exit
    return "Directory exists: #{new_name}" if Dir.exist?(File.join(@base_path, new_name))

    @selected = { type: :rename, old: old_name, new: new_name, base_path: @base_path }
    true
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
      entry = ""
      begin
        clear_screen unless @test_no_cls
        show_cursor
        STDERR.puts "Enter new try name"
        STDERR.puts
        STDERR.print("> #{date_prefix}-")
        STDERR.flush

        STDERR.cooked do
          STDIN.iflush
          entry = STDIN.gets&.chomp.to_s
        end
      ensure
        hide_cursor unless @test_no_cls
      end

      return if entry.nil? || entry.empty?

      final_name = "#{date_prefix}-#{entry}".gsub(/\s+/, '-')
      full_path = File.join(@base_path, final_name)

      @selected = { type: :mkdir, path: full_path }
      end
  end

  def confirm_batch_delete(tries)
    # Find marked items with their info
    marked_items = tries.select { |t| @marked_for_deletion.include?(t[:path]) }
    return if marked_items.empty?

    confirmation_buffer = ""
    confirmation_cursor = 0

    # Handle test mode
    if @test_keys && !@test_keys.empty?
      while @test_keys && !@test_keys.empty?
        ch = @test_keys.shift
        break if ch == "\r" || ch == "\n"
        confirmation_buffer << ch
        confirmation_cursor = confirmation_buffer.length
      end
      process_delete_confirmation(marked_items, confirmation_buffer)
      return
    elsif @test_confirm || !STDERR.tty?
      confirmation_buffer = (@test_confirm || STDIN.gets)&.chomp.to_s
      process_delete_confirmation(marked_items, confirmation_buffer)
      return
    end

    # Interactive delete confirmation dialog
    # Clear screen once before dialog to ensure clean slate
    clear_screen unless @test_no_cls
    loop do
      render_delete_dialog(marked_items, confirmation_buffer, confirmation_cursor)

      ch = read_key
      case ch
      when "\r"  # Enter - confirm
        process_delete_confirmation(marked_items, confirmation_buffer)
        break
      when "\e"  # Escape - cancel
        @delete_status = "Delete cancelled"
        @marked_for_deletion.clear
        @delete_mode = false
        break
      when "\x7F", "\b"  # Backspace
        if confirmation_cursor > 0
          confirmation_buffer = confirmation_buffer[0...confirmation_cursor-1] + confirmation_buffer[confirmation_cursor..]
          confirmation_cursor -= 1
        end
      when "\x03"  # Ctrl-C
        @delete_status = "Delete cancelled"
        @marked_for_deletion.clear
        @delete_mode = false
        break
      when String
        if ch.length == 1 && ch.ord >= 32
          confirmation_buffer = confirmation_buffer[0...confirmation_cursor] + ch + confirmation_buffer[confirmation_cursor..]
          confirmation_cursor += 1
        end
      end
    end

    @needs_redraw = true
  end

  def render_delete_dialog(marked_items, confirmation_buffer, confirmation_cursor)
    screen = Tui::Screen.new(io: STDERR)

    count = marked_items.length
    screen.header.add_line do |line|
      line.center << emoji("🗑️") << Tui::Text.accent("  Delete #{count} #{count == 1 ? 'directory' : 'directories'}?")
    end
    screen.header.add_line { |line| line.write.write_dim(fill("─")) }

    marked_items.each do |item|
      screen.body.add_line(background: Tui::Palette::DANGER_BG) do |line|
        line.write << emoji("🗑️") << " #{item[:basename]}"
      end
    end

    # Add empty lines, then centered confirmation prompt
    2.times { screen.body.add_line }
    screen.body.add_line do |line|
      prefix = "Type YES to confirm: "
      line.center.write_dim(prefix)
      line.center << screen.input("", value: confirmation_buffer, cursor: confirmation_cursor).to_s
      # Input displays buffer + trailing space when cursor at end
      # Use (width - 1) to match Line.render's max_content calculation
      input_width = [confirmation_buffer.length, confirmation_cursor + 1].max
      prefix_width = Tui::Metrics.visible_width(prefix)
      max_content = screen.width - 1
      center_start = (max_content - prefix_width - input_width) / 2
      line.mark_has_input(center_start + prefix_width)
    end

    screen.footer.add_line { |line| line.write.write_dim(fill("─")) }
    screen.footer.add_line { |line| line.center.write_dim("Enter: Confirm  Esc: Cancel") }

    screen.flush
  end

  def process_delete_confirmation(marked_items, confirmation)
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
        @delete_status = "Deleted: #{names}"
        @all_tries = nil  # Clear cache
        @fuzzy = nil
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
  end
end

# Main execution with OptionParser subcommands
if __FILE__ == $0

  VERSION = "1.7.1"

  def print_global_help
    text = <<~HELP
      try v#{VERSION} - ephemeral workspace manager

      To use try, add to your shell config:

        # bash/zsh (~/.bashrc or ~/.zshrc)
        eval "$(try init ~/src/tries)"

        # fish (~/.config/fish/config.fish)
        eval (try init ~/src/tries | string collect)

      Usage:
        try [query]           Interactive directory selector
        try clone <url>       Clone repo into dated directory
        try worktree <name>   Create worktree from current git repo
        try --help            Show this help

      Commands:
        init [path]           Output shell function definition
        clone <url> [name]    Clone git repo into date-prefixed directory
        worktree <name>       Create worktree in dated directory

      Examples:
        try                   Open interactive selector
        try project           Selector with initial filter
        try clone https://github.com/user/repo
        try worktree feature-branch

      Manual mode (without alias):
        try exec [query]      Output shell script to eval

      Defaults:
        Default path: ~/src/tries
        Current: #{TrySelector::TRY_PATH}
    HELP
    STDERR.print(text)
  end

  # Process color-related flags early
  disable_colors = ARGV.delete('--no-colors')
  disable_colors ||= ARGV.delete('--no-expand-tokens')

  Tui.disable_colors! if disable_colors
  Tui.disable_colors! if ENV['NO_COLOR'] && !ENV['NO_COLOR'].empty?

  # Global help: show for --help/-h anywhere
  if ARGV.include?("--help") || ARGV.include?("-h")
    print_global_help
    exit 0
  end

  # Version flag
  if ARGV.include?("--version") || ARGV.include?("-v")
    STDERR.puts "try #{VERSION}"
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
    ["touch #{q(path)}", "echo #{q(path)}", "cd #{q(path)}"]
  end

  def script_mkdir_cd(path)
    ["mkdir -p #{q(path)}"] + script_cd(path)
  end

  def script_clone(path, uri)
    ["mkdir -p #{q(path)}", "echo #{q("Using git clone to create this trial from #{uri}.")}", "git clone '#{uri}' #{q(path)}"] + script_cd(path)
  end

  def script_worktree(path, repo = nil)
    r = repo ? q(repo) : nil
    worktree_cmd = if r
      "/usr/bin/env sh -c 'if git -C #{r} rev-parse --is-inside-work-tree >/dev/null 2>&1; then repo=$(git -C #{r} rev-parse --show-toplevel); git -C \"$repo\" worktree add --detach #{q(path)} >/dev/null 2>&1 || true; fi; exit 0'"
    else
      "/usr/bin/env sh -c 'if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then repo=$(git rev-parse --show-toplevel); git -C \"$repo\" worktree add --detach #{q(path)} >/dev/null 2>&1 || true; fi; exit 0'"
    end
    src = repo || Dir.pwd
    ["mkdir -p #{q(path)}", "echo #{q("Using git worktree to create this trial from #{src}.")}", worktree_cmd] + script_cd(path)
  end

  def script_delete(paths, base_path)
    cmds = ["cd #{q(base_path)}"]
    paths.each { |item| cmds << "test -d #{q(item[:basename])} && rm -rf #{q(item[:basename])}" }
    cmds << "( cd #{q(Dir.pwd)} 2>/dev/null || cd \"$HOME\" )"
    cmds
  end

  def script_rename(base_path, old_name, new_name)
    new_path = File.join(base_path, new_name)
    [
      "cd #{q(base_path)}",
      "mv #{q(old_name)} #{q(new_name)}",
      "echo #{q(new_path)}",
      "cd #{q(new_path)}"
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
