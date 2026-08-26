#!/usr/bin/env ruby

require 'io/console'
require 'time'
require 'set'
require_relative 'lib/tui'
require_relative 'lib/fuzzy'

# Spinel AOT has no FileUtils, IO#raw/#cooked/#iflush, IO.console, or Gem.
# These helpers are MRI-compatible stand-ins so the same source runs both ways.
module TryCompat
  def self.mkdir_p(path)
    path = File.expand_path(path.to_s)
    return path if Dir.exist?(path)
    stack = []
    dir = path
    while dir && dir != "/" && dir != "." && !Dir.exist?(dir)
      stack.unshift(dir)
      parent = File.dirname(dir)
      break if parent == dir
      dir = parent
    end
    stack.each do |d|
      begin
        Dir.mkdir(d.to_s)
      rescue Errno::EEXIST
      end
    end
    path
  end

  def self.stty_save
    `stty -g 2>/dev/null`.to_s.chomp
  rescue
    ""
  end

  def self.stty_set(state)
    return if state.nil? || state.empty?
    system("stty #{state} 2>/dev/null")
  end

  def self.with_raw_tty
    saved = nil
    if STDIN.tty?
      saved = stty_save
      system("stty raw -echo 2>/dev/null")
    end
    yield
  ensure
    stty_set(saved) if saved && !saved.empty?
  end

  def self.with_cooked_tty
    saved = nil
    if STDIN.tty?
      saved = stty_save
      system("stty cooked echo 2>/dev/null")
    end
    yield
  ensure
    stty_set(saved) if saved && !saved.empty?
  end

  def self.stdin_iflush
    begin
      loop { STDIN.read_nonblock(4096) }
    rescue IO::WaitReadable, EOFError, Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::EINVAL
    end
  end

  def self.win_platform?
    !!(RUBY_PLATFORM.to_s =~ /mswin|mingw|cygwin/i)
  end

  # true when this process is a Spinel-compiled native binary (or any
  # non-.rb executable), so init snippets should invoke $0 directly.
  def self.compiled_binary?
    name = File.basename($0.to_s)
    !name.end_with?(".rb")
  end

  def self.self_exec_prefix(script_path)
    quoted = "'" + script_path.to_s.gsub("'", %q('"'"')) + "'"
    if compiled_binary?
      quoted
    else
      "/usr/bin/env ruby #{quoted}"
    end
  end
end

# Emergency restore if the process exits while the TUI alt-screen is active.
$try_tui_active = false
at_exit do
  next unless $try_tui_active
  begin
    STDERR.print("#{Tui::ANSI::RESET}#{Tui::ANSI::CURSOR_DEFAULT}#{Tui::ANSI::SHOW}#{Tui::ANSI::ALT_SCREEN_OFF}")
  rescue
  end
end

class TrySelector
  include Tui::Helpers
  TRY_PATH = ENV['TRY_PATH'] || File.expand_path("~/src/tries")
  TRY_PROJECTS = ENV['TRY_PROJECTS']

  # Precompiled regex constants
  INPUT_CHAR_RE = /[a-zA-Z0-9\-\_\. ]/
  WORD_CHAR_RE = /[a-zA-Z0-9]/

  def initialize(search_term = "", base_path: TRY_PATH, initial_input: nil, test_render_once: false, test_no_cls: false, test_keys: nil, test_confirm: nil)
    @search_term = search_term.gsub(/\s+/, '-')
    @cursor_pos = 0  # Navigation cursor (list position)
    @scroll_offset = 0
    @search = Tui::InputField.new(
      placeholder: "",
      text: initial_input ? initial_input.gsub(/\s+/, '-') : @search_term
    )
    @selected = nil
    @all_trials = nil  # Memoized trials
    @base_path = base_path.to_s
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

    TryCompat.mkdir_p(@base_path) unless Dir.exist?(@base_path.to_s)
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
      TryCompat.with_raw_tty do
        main_loop
      end
    end
  ensure
    restore_terminal
  end

  private

  def setup_terminal
    @terminal_restored = false
    unless @test_no_cls
      # Switch to alternate screen buffer (like vim, less, etc.)
      STDERR.print("#{Tui::ANSI::ALT_SCREEN_ON}#{Tui::ANSI.set_title("try")}#{Tui::ANSI::CURSOR_BLINK}")
      $try_tui_active = true
    end

    # Spinel can SIGSEGV restoring a previous WINCH handler on process exit.
    unless TryCompat.compiled_binary?
      @old_winch_handler = Signal.trap('WINCH') { @needs_redraw = true } if Signal.list.key?('WINCH')
    end
  end

  def restore_terminal
    return if @terminal_restored
    @terminal_restored = true
    unless @test_no_cls
      STDERR.print(Tui::ANSI::RESET)
      STDERR.print(Tui::ANSI::CURSOR_DEFAULT)
      # Return to main screen buffer
      STDERR.print(Tui::ANSI::ALT_SCREEN_OFF)
      $try_tui_active = false
    end

    Signal.trap('WINCH', @old_winch_handler) if @old_winch_handler
    begin
      TryCompat.stdin_iflush
    rescue
    end
  end

  def load_all_tries
    # Load trials only once - single pass through directory
    @all_tries ||= begin
      tries = []
      now = Time.now
      Dir.foreach(@base_path.to_s) do |entry|
        # exclude . and .. but also .git, and any other hidden dirs.
        next if entry.start_with?('.')

        path = File.join(@base_path, entry)
        begin
          stat = File.stat(path)
        rescue Errno::ENOENT, Errno::EACCES
          next
        end

        # Only include directories
        next unless stat.directory?

        # Compute base_score from recency + date prefix bonus
        mtime = stat.mtime
        hours_since_access = (now - mtime) / 3600.0
        base_score = 3.0 / Math.sqrt(hours_since_access + 1)

        # Bonus for date-prefixed directories
        base_score += 2.0 if entry.match?(/^\d{4}-\d{2}-\d{2}-/)

        is_symlink = File.symlink?(path)

        tries << {
          text: entry,
          basename: entry,
          path: is_symlink ? File.realpath(path) : path,
          is_new: false,
          is_symlink: is_symlink,
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

    def text; data[:text]; end
    def basename; data[:basename]; end
    def path; data[:path]; end
    def is_new; data[:is_new]; end
    def is_symlink; data[:is_symlink]; end
    def ctime; data[:ctime]; end
    def mtime; data[:mtime]; end
    def base_score; data[:base_score]; end

  end

  def get_tries
    load_all_tries
    @fuzzy ||= Fuzzy.new(@all_tries)

    # Cache results - only re-match when query changes
    if @last_query == @search.text && @cached_results
      return @cached_results
    end

    @last_query = @search.text
    height = Tui::Terminal.size(STDERR)[0] || 24
    max_results = [height - 6, 3].max
    results = []
    @fuzzy.match(@search.text).limit(max_results).each do |entry, positions, score|
      results << TryEntry.new(entry, score, positions)
    end
    @cached_results = results
  end

  def main_loop
    loop do
      tries = get_tries
      show_create_new = !@search.text.empty?
      total_items = tries.length + (show_create_new ? 1 : 0)

      # Ensure cursor is within bounds
      @cursor_pos = [[@cursor_pos, 0].max, [total_items - 1, 0].max].min

      render(tries)

      key = read_key
      # nil means terminal resize - just re-render with new dimensions
      next unless key

      before = @search.text
      if @search.handle_key(key)
        @cursor_pos = 0 if @search.text != before
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
      when "\x04"  # Ctrl-D - toggle mark for deletion
        if @cursor_pos < tries.length
          path = tries[@cursor_pos].path
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
      when "\x07"  # Ctrl-G - graduate/ascend selected entry
        if @cursor_pos < tries.length
          run_ascend_dialog(tries[@cursor_pos])
          break if @selected
        end
      when "\x03", "\x1b"  # Ctrl-C or ESC
        if @delete_mode
          # Exit delete mode, clear marks
          @marked_for_deletion.clear
          @delete_mode = false
        else
          # Return a Hash (not nil): Spinel can SIGSEGV if this method's
          # inferred return type is Hash and we break with nil.
          @selected = { type: :cancel }
          break
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
      begin
        nxt = STDIN.read_nonblock(1)
        input << nxt
        if nxt == "["
          # CSI: consume until a final byte in 0x40-0x7E so mouse/unknown
          # sequences never leak into the filter. Bare ESC still returns "\e"
          # when no following byte is available (WaitReadable).
          loop do
            ch = STDIN.read_nonblock(1)
            input << ch
            code = ch.ord
            break if code >= 0x40 && code <= 0x7E
          end
          # X10 mouse: ESC [ M + 3 payload bytes
          if input == "\e[M"
            begin
              input << STDIN.read_nonblock(3)
            rescue IO::WaitReadable, EOFError, Errno::EAGAIN, Errno::EWOULDBLOCK
            end
          end
        elsif nxt == "O"
          input << STDIN.read_nonblock(1)
        end
      rescue IO::WaitReadable, EOFError, Errno::EAGAIN, Errno::EWOULDBLOCK
        # Standalone ESC (or incomplete sequence) — keep what we have
      end
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

    line = screen.header.add_line
    line.write.write(emoji("🏠")).write(Tui::Text.accent(" Try Directory Selection") )
    line = screen.header.add_line
    line.write.write_dim(fill("─")) 
    line = screen.header.add_line
      prefix = "Search: "
      line.write.write_dim(prefix)
      line.write.write(screen.input("", value: @search.text, cursor: @search.cursor).to_s)
      line.mark_has_input(Tui::Metrics.visible_width(prefix))
    line = screen.header.add_line
    line.write.write_dim(fill("─")) 

    # Add footer first to get accurate line count
    line = screen.footer.add_line
    line.write.write_dim(fill("─")) 
    if @delete_status
      line = screen.footer.add_line
      line.write.write_bold(@delete_status) 
      @delete_status = nil
    elsif @delete_mode
      line = screen.footer.add_line(Tui::Palette::DANGER_BG)
        line.write.write_bold(" DELETE MODE ")
        line.write.write(" #{@marked_for_deletion.length} marked  |  Ctrl-D: Toggle  Enter: Confirm  Esc: Cancel")
    else
      line = screen.footer.add_line
        line.center.write_dim("↑/↓: Navigate  Enter: Select  ^R: Rename  ^G: Graduate  ^D: Delete  Esc: Cancel")
    end

    # Calculate max visible from actual header/footer counts
    header_lines = screen.header.lines.length
    footer_lines = screen.footer.lines.length
    max_visible = [height - header_lines - footer_lines, 3].max
    show_create_new = !@search.text.empty?
    total_items = tries.length + (show_create_new ? 1 : 0)

    if @cursor_pos < @scroll_offset
      @scroll_offset = @cursor_pos
    elsif @cursor_pos >= @scroll_offset + max_visible
      @scroll_offset = @cursor_pos - max_visible + 1
    end

    visible_end = [@scroll_offset + max_visible, total_items].min

    (@scroll_offset...visible_end).each do |idx|
      if idx == tries.length && !tries.empty? && idx >= @scroll_offset
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
    is_marked = @marked_for_deletion.include?(entry.path)
    # Marked items keep the danger background; selected rows add a readable foreground.
    background = if is_marked
      Tui::Palette::DANGER_BG + (is_selected ? Tui::Palette::SELECTED_FG : "")
    elsif is_selected
      Tui::Palette::SELECTED_BG + Tui::Palette::SELECTED_FG
    end

    line = screen.body.add_line(background)
    line.write.write((is_selected ? Tui::Text.highlight("→ ") + selected_foreground : "  "))
    icon = if is_marked
      emoji("🗑️")
    elsif entry.is_symlink
      emoji("🔗")
    else
      emoji("📁")
    end
    line.write.write(icon).write(" ")

    plain_name, rendered_name = formatted_entry_name(entry, selected: is_selected)
    prefix_width = 5
    meta_text = "#{format_relative_time(entry.mtime)}, #{format('%.1f', entry.score)}"

    # Only truncate name if it exceeds total line width (not to make room for metadata)
    max_name_width = width - prefix_width - 1
    if plain_name.length > max_name_width && max_name_width > 2
      display_rendered = truncate_with_ansi(rendered_name, max_name_width - 1) + "…"
    else
      display_rendered = rendered_name
    end

    line.write.write(display_rendered)

    # Right content is lower layer - will be overwritten by left if they overlap
    line.right.write(is_selected ? meta_text : Tui::Text.dim(meta_text))
  end

  def render_create_line(screen, is_selected, width)
    background = if is_selected
      Tui::Palette::SELECTED_BG + Tui::Palette::SELECTED_FG
    end
    line = screen.body.add_line(background)
    line.write.write((is_selected ? Tui::Text.highlight("→ ") + selected_foreground : "  "))
    date_prefix = Time.now.strftime("%Y-%m-%d")
    label = if @search.text.empty?
      "📂 Create new: #{date_prefix}-"
    else
      "📂 Create new: #{date_prefix}-#{@search.text}"
    end
    line.write.write(label)
  end

  def formatted_entry_name(entry, selected: false)
    basename = entry.basename
    positions = entry.highlight_positions || []

    if basename =~ /^(\d{4}-\d{2}-\d{2})-(.+)$/
      date_part = $1
      name_part = $2
      date_len = date_part.length + 1  # +1 for the hyphen

      rendered = selected ? date_part : Tui::Text.dim(date_part)
      # Highlight hyphen if it's in positions
      hyphen = if positions.include?(10)
        Tui::Text.highlight('-')
      elsif selected
        '-'
      else
        Tui::Text.dim('-')
      end
      rendered += hyphen
      rendered += selected_foreground if selected && positions.include?(10)
      rendered += highlight_with_positions(name_part, positions, date_len, selected: selected)
      ["#{date_part}-#{name_part}", rendered]
    else
      [basename, highlight_with_positions(basename, positions, 0, selected: selected)]
    end
  end

  def highlight_with_positions(text, positions, offset, selected: false)
    pos_set = positions.is_a?(Set) ? positions : positions.to_set
    result = String.new
    chars = text.chars
    i = 0
    while i < chars.length
      if pos_set.include?(i + offset)
        # Batch consecutive highlighted characters
        batch_start = i
        i += 1
        i += 1 while i < chars.length && pos_set.include?(i + offset)
        result << Tui::Text.highlight(chars[batch_start...i].join)
        result << selected_foreground if selected
      else
        result << chars[i]
        i += 1
      end
    end
    result
  end

  def selected_foreground
    Tui.colors_enabled? ? Tui::Palette::SELECTED_FG : ""
  end

  # Find the position of the previous word boundary for Ctrl-W deletion.
  # Skips non-alphanumeric chars, then skips alphanumeric chars.
  def word_boundary_backward(buffer, cursor)
    Tui::InputField.new(placeholder: "", text: buffer.to_s, cursor: cursor).word_boundary_backward(buffer.to_s, cursor)
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

    current_name = entry.basename
    input = Tui::InputField.new(placeholder: "", text: current_name.dup)
    rename_error = nil

    loop do
      render_rename_dialog(current_name, input.text, input.cursor, rename_error)

      ch = read_key
      next unless ch
      before = input.text
      if input.handle_key(ch)
        rename_error = nil if input.text != before
        next
      end
      case ch
      when "\r"  # Enter - confirm
        result = finalize_rename(entry, input.text)
        if result == true
          break
        else
          rename_error = result  # Error message string
        end
      when "\x1b", "\x03"  # ESC or Ctrl-C - cancel
        break
      end
    end

    @needs_redraw = true
  end

  def render_rename_dialog(current_name, rename_buffer, rename_cursor, rename_error)
    screen = Tui::Screen.new(io: STDERR)

    line = screen.header.add_line
      line.center.write(emoji("✏️")).write(Tui::Text.accent("  Rename directory"))
    line = screen.header.add_line
    line.write.write_dim(fill("─")) 

    line = screen.body.add_line
      line.write.write(emoji("📁")).write(" #{current_name}")

    # Add empty lines, then centered input prompt
    screen.body.add_line
    screen.body.add_line
    line = screen.body.add_line
      prefix = "New name: "
      line.center.write_dim(prefix)
      line.center.write(screen.input("", value: rename_buffer, cursor: rename_cursor).to_s)
      # Input displays buffer + trailing space when cursor at end
      # Use (width - 1) to match Line.render's max_content calculation
      input_width = [rename_buffer.length, rename_cursor + 1].max
      prefix_width = Tui::Metrics.visible_width(prefix)
      max_content = screen.width - 1
      center_start = (max_content - prefix_width - input_width) / 2
      line.mark_has_input(center_start + prefix_width)

    if rename_error
      screen.body.add_line
      line = screen.body.add_line
      line.center.write_bold(rename_error) 
    end

    line = screen.footer.add_line
    line.write.write_dim(fill("─")) 
    line = screen.footer.add_line
    line.center.write_dim("Enter: Confirm  Esc: Cancel") 

    screen.flush
  end

  def finalize_rename(entry, rename_buffer)
    new_name = rename_buffer.strip.gsub(/\s+/, '-')
    old_name = entry.basename

    return "Name cannot be empty" if new_name.empty?
    return "Name cannot contain /" if new_name.include?('/')
    return true if new_name == old_name  # No change, just exit
    return "Directory exists: #{new_name}" if Dir.exist?(File.join(@base_path, new_name))

    @selected = { type: :rename, old: old_name, new: new_name, base_path: @base_path }
    true
  end

  # Ascend dialog - promote a try to a permanent project directory
  def run_ascend_dialog(entry)
    @delete_mode = false
    @marked_for_deletion.clear

    current_name = entry.basename

    # Strip date prefix for the default project name
    project_name = current_name.sub(/^\d{4}-\d{2}-\d{2}-/, '')

    # Compute default destination directory
    projects_dir = if TRY_PROJECTS
      File.expand_path(TRY_PROJECTS)
    else
      File.dirname(@base_path)
    end

    input = Tui::InputField.new(placeholder: "", text: File.join(projects_dir, project_name))
    ascend_error = nil

    loop do
      render_ascend_dialog(current_name, input.text, input.cursor, ascend_error, projects_dir)

      ch = read_key
      next unless ch
      before = input.text
      if input.handle_key(ch)
        ascend_error = nil if input.text != before
        next
      end
      case ch
      when "\r"  # Enter - confirm
        result = finalize_ascend(entry, input.text)
        if result == true
          break
        else
          ascend_error = result
        end
      when "\x1b", "\x03"  # ESC or Ctrl-C - cancel
        break
      end
    end

    @needs_redraw = true
  end

  def render_ascend_dialog(current_name, ascend_buffer, ascend_cursor, ascend_error, projects_dir)
    screen = Tui::Screen.new(io: STDERR)

    line = screen.header.add_line
      line.center.write(emoji("🚀")).write(Tui::Text.accent("  Graduate try to project"))
    line = screen.header.add_line
    line.write.write_dim(fill("─")) 

    line = screen.body.add_line
      line.write.write(emoji("📁")).write(" #{current_name}")
    screen.body.add_line

    env_hint = TRY_PROJECTS ? "$TRY_PROJECTS" : "parent of $TRY_PATH"
    line = screen.body.add_line
      line.center.write_dim("Destination (#{env_hint}: #{projects_dir})")

    line = screen.body.add_line
      prefix = "Move to: "
      line.center.write_dim(prefix)
      line.center.write(screen.input("", value: ascend_buffer, cursor: ascend_cursor).to_s)
      input_width = [ascend_buffer.length, ascend_cursor + 1].max
      prefix_width = Tui::Metrics.visible_width(prefix)
      max_content = screen.width - 1
      center_start = (max_content - prefix_width - input_width) / 2
      line.mark_has_input(center_start + prefix_width)

    screen.body.add_line
    line = screen.body.add_line
      line.center.write_dim("A symlink will be left in the tries directory")

    if ascend_error
      screen.body.add_line
      line = screen.body.add_line
      line.center.write_bold(ascend_error) 
    end

    line = screen.footer.add_line
    line.write.write_dim(fill("─")) 
    line = screen.footer.add_line
    line.center.write_dim("Enter: Confirm  Esc: Cancel") 

    screen.flush
  end

  def finalize_ascend(entry, ascend_buffer)
    dest = ascend_buffer.strip
    dest = File.expand_path(dest)

    return "Destination cannot be empty" if dest.empty?
    return "Destination already exists: #{dest}" if File.exist?(dest)

    parent = File.dirname(dest)
    return "Parent directory does not exist: #{parent}" unless Dir.exist?(parent)

    @selected = {
      type: :ascend,
      source: entry.path,
      dest: dest,
      basename: entry.basename,
      base_path: @base_path
    }
    true
  end

  def handle_selection(try_dir)
    # Select existing try directory
    @selected = { type: :cd, path: try_dir.path }
  end

  def handle_create_new
    # Create new try directory
    date_prefix = Time.now.strftime("%Y-%m-%d")

    # If user already typed a name, use it directly
    if !@search.text.empty?
      final_name = "#{date_prefix}-#{@search.text}".gsub(/\s+/, '-')
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

        TryCompat.with_cooked_tty do
          TryCompat.stdin_iflush
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
    marked_items = tries.select { |t| @marked_for_deletion.include?(t.path) }
    return if marked_items.empty?

    input = Tui::InputField.new(placeholder: "", text: "")

    # Handle test mode
    if @test_keys && !@test_keys.empty?
      while @test_keys && !@test_keys.empty?
        ch = @test_keys.shift
        break if ch == "\r" || ch == "\n"
        input.handle_key(ch)
      end
      process_delete_confirmation(marked_items, input.text)
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
      render_delete_dialog(marked_items, input.text, input.cursor)

      ch = read_key
      next unless ch
      if input.handle_key(ch)
        next
      end
      case ch
      when "\r"  # Enter - confirm
        process_delete_confirmation(marked_items, input.text)
        break
      when "\e", "\x03"  # Escape or Ctrl-C - cancel
        @delete_status = "Delete cancelled"
        @marked_for_deletion.clear
        @delete_mode = false
        break
      end
    end

    @needs_redraw = true
  end

  def render_delete_dialog(marked_items, confirmation_buffer, confirmation_cursor)
    screen = Tui::Screen.new(io: STDERR)

    count = marked_items.length
    line = screen.header.add_line
      line.center.write(emoji("🗑️")).write(Tui::Text.accent("  Delete #{count} #{count == 1 ? 'directory' : 'directories'}?"))
    line = screen.header.add_line
    line.write.write_dim(fill("─")) 

    marked_items.each do |item|
      line = screen.body.add_line(Tui::Palette::DANGER_BG)
        line.write.write(emoji("🗑️")).write(" #{item.basename}")
    end

    # Add empty lines, then centered confirmation prompt
    screen.body.add_line
    screen.body.add_line
    line = screen.body.add_line
      prefix = "Type YES to confirm: "
      line.center.write_dim(prefix)
      line.center.write(screen.input("", value: confirmation_buffer, cursor: confirmation_cursor).to_s)
      # Input displays buffer + trailing space when cursor at end
      # Use (width - 1) to match Line.render's max_content calculation
      input_width = [confirmation_buffer.length, confirmation_cursor + 1].max
      prefix_width = Tui::Metrics.visible_width(prefix)
      max_content = screen.width - 1
      center_start = (max_content - prefix_width - input_width) / 2
      line.mark_has_input(center_start + prefix_width)

    line = screen.footer.add_line
    line.write.write_dim(fill("─")) 
    line = screen.footer.add_line
    line.center.write_dim("Enter: Confirm  Esc: Cancel") 

    screen.flush
  end

  def process_delete_confirmation(marked_items, confirmation)
    if confirmation == "YES"
      begin
        base_real = File.realpath(@base_path)

        # Validate all paths first
        validated_paths = []
        marked_items.each do |item|
          target_real = File.realpath(item.path)
          unless target_real.start_with?(base_real + "/")
            raise "Safety check failed: #{target_real} is not inside #{base_real}"
          end
          validated_paths << { path: target_real, basename: item.basename }
        end

        # Return delete action with all paths
        @selected = { type: :delete, paths: validated_paths, base_path: base_real }
        names = validated_paths.map { |p| p[:basename] }.join(", ")
        @delete_status = "Deleted: #{names}"
        @all_tries = nil  # Clear cache
        @fuzzy = nil
        @cached_results = nil
        @last_query = nil
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
# Spinel AOT: $0 is the native binary, __FILE__ is this source path, so the
# usual `$0 == __FILE__` guard would skip the CLI. try.rb is the program
# entrypoint (tests load lib/* not this file).
if $0 == __FILE__ || TryCompat.compiled_binary?

  VERSION = "1.10.1"

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
        try https://github.com/user/repo/pull/123
        try worktree feature-branch

      Manual mode (without alias):
        try exec [query]      Output shell script to eval

      Environment:
        TRY_PATH          Tries directory (default: ~/src/tries)
        TRY_PROJECTS      Graduate destination (default: parent of TRY_PATH)

      Keyboard:
        ↑/↓, Ctrl-P/N     Navigate
        Enter              Select / Create new
        Ctrl-R             Rename
        Ctrl-G             Graduate (promote try to project)
        Ctrl-D             Mark for deletion
        Ctrl-T             Create new try
        Esc                Cancel
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
    found = -1
    i = args.length - 1
    while i >= 0
      a = args[i]
      if a == opt_name || a.start_with?("#{opt_name}=")
        found = i
        break
      end
      i -= 1
    end
    return nil if found < 0
    arg = args.delete_at(found)
    if arg.include?('=')
      arg.split('=', 2)[1]
    else
      args.delete_at(found)
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
    elsif uri.match(%r{^git@([^:]+):([^/]+)/(.+)})
      # git@host:user/path/to/repo
      host, user, path = $1, $2, $3
      repo = File.basename(path)
      return { user: user, repo: repo, host: host }
    elsif uri.match(%r{^ssh://[^@/]+@([^/]+)/([^/]+)/(.+)})
      # ssh://user@host:port/user/repo
      host, user, path = $1, $2, $3
      repo = File.basename(path)
      return { user: user, repo: repo, host: host }
    elsif uri.match(%r{^([^@/:]+)@([^:]+):(.+)})
      # SCP-style SSH: user@host:path/to/repo
      user, host, path = $1, $2, $3
      repo = File.basename(path)
      return { user: user, repo: repo, host: host }
    else
      return nil
    end
  end

  def github_pr_details(uri)
    return nil unless uri

    match = uri.match(%r{\Ahttps?://(?:www\.)?github\.com/([^/]+)/([^/]+)/pull/(\d+)/?\z})
    return nil unless match

    {
      user: match[1],
      repo: match[2].sub(/\.git\z/, ''),
      pr_id: match[3],
      git_uri: "https://github.com/#{match[1]}/#{match[2].sub(/\.git\z/, '')}.git"
    }
  end

  def generate_clone_directory_name(git_uri, custom_name = nil)
    return custom_name if custom_name && !custom_name.empty?

    parsed = github_pr_details(git_uri) || parse_git_uri(git_uri)
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
        when 'CTRL-G', 'CTRLG' then keys << "\x07"
        when 'CTRL-H', 'CTRLH' then keys << "\x08"
        when 'CTRL-K', 'CTRLK' then keys << "\x0B"
        when 'CTRL-N', 'CTRLN' then keys << "\x0E"
        when 'CTRL-P', 'CTRLP' then keys << "\x10"
        when 'CTRL-R', 'CTRLR' then keys << "\x12"
        when 'CTRL-T', 'CTRLT' then keys << "\x14"
        when 'CTRL-U', 'CTRLU' then keys << "\x15"
        when 'CTRL-W', 'CTRLW' then keys << "\x17"
        when 'DELETE' then keys << "\e[3~"
        when /^TYPE=/i
          tok.sub(/^TYPE=/i, '').each_char { |ch| keys << ch }
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
    custom_name = args.join(" ")

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

    path = File.join(tries_path, dir_name)
    if pr = github_pr_details(git_uri)
      script_clone_pr(path, pr[:git_uri], pr[:pr_id])
    else
      script_clone(path, git_uri)
    end
  end

  def cmd_init!(args, tries_path)
    script_path = File.expand_path($0)

    explicit_path = if args[0] && args[0].start_with?('/')
      File.expand_path(args.shift)
    end

    default_path = tries_path || File.expand_path("~/src/tries")
    shell = fish? ? 'fish' : 'bash'
    puts init_snippet(shell, script_path, explicit_path, default_path)
    exit 0
  end

  def cmd_install!(args, tries_path)
    script_path = File.expand_path($0)

    explicit_path = if args[0] && args[0].start_with?('/')
      File.expand_path(args.shift)
    end

    default_path = tries_path || File.expand_path("~/src/tries")

    shell = detect_shell
    rc_file = shell_rc_file(shell)
    snippet = init_snippet(shell, script_path, explicit_path, default_path)

    unless rc_file
      STDERR.puts "Error: could not determine shell config file"
      STDERR.puts "Your shell was detected as: #{shell || 'unknown'}"
      STDERR.puts "Run 'try init' and manually add the output to your shell config."
      exit 1
    end

    rc_path = File.expand_path(rc_file)

    # Check if already installed
    if File.exist?(rc_path) && File.read(rc_path).include?("# try shell integration")
      STDERR.puts "try is already installed in #{rc_path}"
      STDERR.puts "To reinstall, remove the '# try shell integration' block first."
      exit 0
    end

    block = "\n# try shell integration\n#{snippet}"

    if File.exist?(rc_path) && !File.writable?(rc_path)
      STDERR.puts "Warning: #{rc_path} is read-only, skipping."
      STDERR.puts "Run 'try init' and manually add the output to your shell config."
      exit 1
    end

    TryCompat.mkdir_p(File.dirname(rc_path))
    File.open(rc_path, 'a') { |f| f.write(block) }
    STDERR.puts "Added try shell integration to #{rc_path}"
    STDERR.puts "Restart your shell or run: source #{rc_path}" unless shell == 'pwsh'
    STDERR.puts "Restart your shell or run: . $PROFILE" if shell == 'pwsh'
    exit 0
  end

  def detect_shell
    # Check SHELL env (Unix), then parent process, then PSModulePath for PowerShell
    shell_env = ENV["SHELL"].to_s
    return 'fish' if shell_env.include?('fish')
    return 'zsh' if shell_env.include?('zsh')
    return 'bash' if shell_env.include?('bash')

    # PowerShell detection: PSModulePath is set in pwsh sessions
    return 'pwsh' if ENV["PSModulePath"] && !ENV["PSModulePath"].empty?

    # Fallback: check parent process name
    parent = (`ps c -p #{Process.ppid} -o 'ucomm='`.strip rescue "").to_s
    return 'fish' if parent.include?('fish')
    return 'zsh' if parent.include?('zsh')
    return 'bash' if parent.include?('bash')
    return 'pwsh' if parent.match?(/pwsh|powershell/i)

    nil
  end

  def shell_rc_file(shell)
    case shell
    when 'fish' then '~/.config/fish/config.fish'
    when 'zsh'  then '~/.zshrc'
    when 'bash'
      # Prefer .bashrc, fall back to .bash_profile on macOS
      File.exist?(File.expand_path('~/.bashrc')) ? '~/.bashrc' : '~/.bash_profile'
    when 'pwsh'
      # PowerShell profile path from $PROFILE, or the standard location
      ENV["PROFILE"] || (TryCompat.win_platform? ?
        File.join(ENV["USERPROFILE"] || Dir.home, "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1") :
        File.join(Dir.home, ".config", "powershell", "Microsoft.PowerShell_profile.ps1"))
    end
  end

  def init_snippet(shell, script_path, explicit_path, default_path)
    case shell
    when 'fish'
      fish_path_arg = explicit_path ? " --path '#{explicit_path}'" : " --path (if set -q TRY_PATH; echo \"$TRY_PATH\"; else; echo '#{default_path}'; end)"
      <<~FISH
        function try
          set -l out (#{TryCompat.self_exec_prefix(script_path)} exec#{fish_path_arg} $argv 2>/dev/tty | string collect)
          if test $pipestatus[1] -eq 0
            eval $out
          else
            echo $out
          end
        end
      FISH
    when 'pwsh'
      ps_path_expr = if explicit_path
        "'#{explicit_path}'"
      else
        "$(if ($env:TRY_PATH) { $env:TRY_PATH } else { '#{default_path}' })"
      end
      <<~PWSH
        function try {
          $tryPath = #{ps_path_expr}
          $tempErr = [System.IO.Path]::GetTempFileName()
          $out = & #{TryCompat.compiled_binary? ? q(script_path) : "ruby '#{script_path}'"} exec --path $tryPath @args 2>$tempErr
          if ($LASTEXITCODE -eq 0) {
            $out | Invoke-Expression
          } else {
            Get-Content $tempErr | Write-Host
            $out | Write-Output
          }
          Remove-Item $tempErr -ErrorAction SilentlyContinue
        }
      PWSH
    else # bash, zsh
      path_arg = explicit_path ? " --path '#{explicit_path}'" : " --path \"${TRY_PATH:-#{default_path}}\""
      <<~SH
        try() {
          local out
          out=$(#{TryCompat.self_exec_prefix(script_path)} exec#{path_arg} "$@" 2>/dev/tty)
          if [ $? -eq 0 ]; then
            eval "$out"
          else
            echo "$out"
          fi
        }
      SH
    end
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
      if pr = github_pr_details(git_uri)
        return script_clone_pr(full_path, pr[:git_uri], pr[:pr_id])
      else
        return script_clone(full_path, git_uri)
      end
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
    when :ascend
      script_ascend(result[:source], result[:dest], result[:basename], result[:base_path])
    when :cancel
      nil
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

  # Emit best-effort terminal manager rename commands. Keep these as the final
  # commands so a missing or broken optional CLI never prevents the directory
  # change from completing.
  def terminal_rename_commands(path)
    name = File.basename(path).sub(/\A\d{4}-\d{2}-\d{2}-/, '')
    label = "try: #{name}"

    if ENV['HERDR_ENV'] == '1' && ENV['HERDR_PANE_ID'] && !ENV['HERDR_PANE_ID'].empty?
      commands = [
        "command -v herdr >/dev/null 2>&1 && herdr pane report-metadata #{q(ENV['HERDR_PANE_ID'])} --source try --title #{q(label)} >/dev/null 2>&1 || true"
      ]
      if ENV['HERDR_PANE_ID'].match?(/:p1\z/) && ENV['HERDR_WORKSPACE_ID'] && !ENV['HERDR_WORKSPACE_ID'].empty?
        commands << "command -v herdr >/dev/null 2>&1 && herdr workspace rename #{q(ENV['HERDR_WORKSPACE_ID'])} #{q(label)} >/dev/null 2>&1 || true"
      end
      commands
    elsif (ENV['CMUX_SOCKET_PATH'] && !ENV['CMUX_SOCKET_PATH'].empty?) ||
          (ENV['CMUX_BUNDLE_ID'] && !ENV['CMUX_BUNDLE_ID'].empty?)
      ["command -v cmux >/dev/null 2>&1 && cmux rename-tab #{q(label)} >/dev/null 2>&1 || true"]
    else
      []
    end
  end

  def script_cd(path)
    ["touch #{q(path)}", "echo #{q(path)}", "cd #{q(path)}"] + terminal_rename_commands(path)
  end

  def script_mkdir_cd(path)
    ["mkdir -p #{q(path)}"] + script_cd(path)
  end

  def script_clone(path, uri)
    ["mkdir -p #{q(path)}", "echo #{q("Using git clone to create this trial from #{uri}.")}", "git clone '#{uri}' #{q(path)}"] + script_cd(path)
  end

  def script_clone_pr(path, uri, pr_id)
    ref = "pull/#{pr_id}/head"
    [
      "mkdir -p #{q(path)}",
      "echo #{q("Using git clone to create this trial from #{uri} PR ##{pr_id}.")}",
      "git clone #{q(uri)} #{q(path)}",
      "git -C #{q(path)} fetch origin #{q(ref)}",
      "git -C #{q(path)} checkout --detach FETCH_HEAD"
    ] + script_cd(path)
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
    cmds << "cd #{q(Dir.pwd)} 2>/dev/null || cd #{q(base_path)}"
    cmds
  end

  def script_ascend(source, dest, basename, base_path)
    symlink_path = File.join(base_path, basename)
    # Check if source is a git worktree (has .git file, not directory)
    git_file = File.join(source, '.git')
    is_worktree = File.file?(git_file)

    cmds = []
    if is_worktree
      # Use git worktree move for proper bookkeeping
      cmds << "git worktree move #{q(source)} #{q(dest)}"
    else
      cmds << "mv #{q(source)} #{q(dest)}"
    end
    cmds << "ln -s #{q(dest)} #{q(symlink_path)}"
    cmds << "echo #{q("Graduated: #{basename} → #{dest}")}"
    cmds + script_cd(dest)
  end

  def script_rename(base_path, old_name, new_name)
    new_path = File.join(base_path, new_name)
    [
      "cd #{q(base_path)}",
      "mv #{q(old_name)} #{q(new_name)}",
      "echo #{q(new_path)}",
      "cd #{q(new_path)}"
    ] + terminal_rename_commands(new_path)
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

    if base =~ /^(.*?)(\d+)$/
      stem = $1.to_s
      n = $2.to_i
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
    shell = ENV["SHELL"].to_s
    if shell.empty?
      shell = (`ps c -p #{Process.ppid} -o 'ucomm='`.strip rescue "").to_s
    end
    shell.include?('fish')
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
  when 'install'
    cmd_install!(ARGV, tries_path)
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
