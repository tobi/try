#!/usr/bin/env ruby

require 'io/console'
require 'time'
require 'fileutils'

# Lightweight token-based printer for all UI output with double buffering
module UI
  TOKEN_MAP = {
    '{text}' => "\e[39m",
    '{dim_text}' => "\e[90m",
    '{h1}' => "\e[1;33m",
    '{h2}' => "\e[1;36m",
    '{highlight}' => "\e[1;33m",
    '{reset}' => "\e[0m\e[39m\e[49m", '{reset_bg}' => "\e[49m",
    '{clear_screen}' => "\e[2J", '{clear_line}' => "\e[2K", '{home}' => "\e[H", '{clear_below}' => "\e[0J",
    '{hide_cursor}' => "\e[?25l", '{show_cursor}' => "\e[?25h",
    '{start_selected}' => "\e[6m",
    '{end_selected}' => "\e[0m"
  }.freeze

  @@buffer = []
  @@last_buffer = []
  @@current_line = ""

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
    # Position cursor at home
    io.print("\e[H")

    max_lines = [@@buffer.length, @@last_buffer.length].max
    reset = TOKEN_MAP['{reset}']

    (0...max_lines).each do |i|
      current_line = @@buffer[i] || ""
      last_line = @@last_buffer[i] || ""

      if current_line != last_line
        # Move to line and clear it, then write new content
        io.print("\e[#{i + 1};1H\e[2K")
        if !current_line.empty?
          processed_line = current_line.gsub(/\{.*?\}/) do |match|
            TOKEN_MAP.fetch(match) { raise "Unknown token: #{match}" }
          end
          io.print(processed_line)
          io.print(reset)
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
    @@buffer.clear
    @@current_line = ""
    @@last_buffer.clear
    io.print("\e[2J\e[H")  # Clear screen and go home
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
    h = `tput lines 2>/dev/null`.strip.to_i
    h > 0 ? h : 24
  end

  def self.width
    w = `tput cols 2>/dev/null`.strip.to_i
    w > 0 ? w : 80
  end
end

class TrySelector
  TRY_PATH = ENV['TRY_PATH'] || File.expand_path("~/src/tries")

  def initialize(search_term = "", base_path: TRY_PATH)
    @search_term = search_term.gsub(/\s+/, '-')
    @cursor_pos = 0
    @scroll_offset = 0
    @input_buffer = @search_term
    @selected = nil
    @all_trials = nil  # Memoized trials
    @base_path = base_path
    @delete_status = nil  # Status message for deletions

    FileUtils.mkdir_p(@base_path) unless Dir.exist?(@base_path)
  end

  def run
    # Always use STDERR for UI (it stays connected to TTY)
    # This allows stdout to be captured for the shell commands
    setup_terminal

    # Check if we have a TTY
    if !STDIN.tty? || !STDERR.tty?
      UI.puts "Error: try requires an interactive terminal"
      return nil
    end

    STDERR.raw do
      main_loop
    end
  ensure
    restore_terminal
  end

  private

  def setup_terminal
    UI.cls
    STDERR.print("\e[2J\e[H\e[?25l")  # Direct clear screen, home, hide cursor
  end

  def restore_terminal
    # Clear screen completely before restoring
    STDERR.print("\e[2J\e[H\e[?25h")  # Direct clear, home, show cursor
  end

  def load_all_tries
    # Load trials only once - single pass through directory
    @all_tries ||= begin
      tries = []
      Dir.foreach(@base_path) do |entry|
        next if entry == '.' || entry == '..'

        path = File.join(@base_path, entry)
        stat = File.stat(path)

        # Only include directories
        next unless stat.directory?

        tries << {
          name: "📁 #{entry}",
          basename: entry,
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

    # Always score trials (for time-based sorting even without search)
    scored_tries = @all_tries.map do |try_dir|
      score = calculate_score(try_dir[:basename], @input_buffer, try_dir[:ctime], try_dir[:mtime])
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

  def calculate_score(text, query, ctime = nil, mtime = nil)
    score = 0.0

    # generally we are looking for default date-prefixed directories
    if text.start_with?(/\d\d\d\d\-\d\d\-\d\d\-/)
      score += 2.0
    end

    # If there's a search query, calculate match score
    if !query.empty?
      text_lower = text.downcase
      query_lower = query.downcase
      query_chars = query_lower.chars

      last_pos = -1
      query_idx = 0

      text_lower.chars.each_with_index do |char, pos|
        break if query_idx >= query_chars.length
        next unless char == query_chars[query_idx]

        # Base point + word boundary bonus
        score += 1.0
        score += 1.0 if pos == 0 || text_lower[pos-1] =~ /\W/

        # Proximity bonus: 1/sqrt(distance) gives nice decay
        if last_pos >= 0
          gap = pos - last_pos - 1
          score += 1.0 / Math.sqrt(gap + 1)
        end

        last_pos = pos
        query_idx += 1
      end

      # Return 0 if not all query chars matched
      return 0.0 if query_idx < query_chars.length

      # Prefer shorter matches (density bonus)
      score *= (query_chars.length.to_f / (last_pos + 1)) if last_pos >= 0

      # Length penalty - shorter text scores higher for same match
      # e.g., "v" matches better in "2025-08-13-v" than "2025-08-13-vbo-viz"
      score *= (10.0 / (text.length + 10.0))  # Smooth penalty that doesn't dominate
    end

    # Always apply time-based scoring (but less aggressively)
    now = Time.now

    # Creation time bonus - newer is better
    if ctime
      days_old = (now - ctime) / 86400.0
      score += 2.0 / Math.sqrt(days_old + 1)
    end

    # Access time bonus - recently accessed is better
    if mtime
      hours_since_access = (now - mtime) / 3600.0
      score += 3.0 / Math.sqrt(hours_since_access + 1)  # Reduced weight
    end

    score
  end

  def main_loop
    loop do
      tries = get_tries
      total_items = tries.length + 1  # +1 for "Create new" option

      # Ensure cursor is within bounds
      @cursor_pos = [[@cursor_pos, 0].max, total_items - 1].min

      render(tries)

      key = UI.read_key

      case key
      when "\e[A", "\x10"  # Up arrow or Ctrl-P
        @cursor_pos = [@cursor_pos - 1, 0].max
      when "\e[B", "\x0E"  # Down arrow or Ctrl-N
        @cursor_pos = [@cursor_pos + 1, total_items - 1].min
      when "\e[C"  # Right arrow - ignore
        # Do nothing
      when "\e[D"  # Left arrow - ignore
        # Do nothing
      when "\r", "\n"  # Enter
        if @cursor_pos < tries.length
          handle_selection(tries[@cursor_pos])
        else
          # Selected "Create new"
          handle_create_new
        end
        break if @selected
      when "\x7F", "\b"  # Backspace
        @input_buffer = @input_buffer[0...-1] if @input_buffer.length > 0
        @cursor_pos = 0
      when "\x04"  # Ctrl-D
        if @cursor_pos < tries.length
          handle_delete(tries[@cursor_pos])
        end
      when "\x03", "\e"  # Ctrl-C or ESC
        @selected = nil
        break
      when String
        # Only accept printable characters, not escape sequences
        if key.length == 1 && key =~ /[a-zA-Z0-9\-\_\. ]/
          @input_buffer += key
          @cursor_pos = 0
        end
      end
    end

    @selected
  end

  def render(tries)
    term_width = UI.width
    term_height = UI.height

    # Use actual terminal width for separator lines
    separator = "─" * (term_width - 1)

    # Header
    UI.puts "{h1}📁 Try Directory Selection"
    UI.puts "{dim_text}#{separator}"

    # Search input
    UI.puts "{highlight}Search: {reset}#{@input_buffer}"
    UI.puts "{dim_text}#{separator}"

    # Calculate visible window based on actual terminal height
    max_visible = [term_height - 8, 3].max
    total_items = tries.length + 1  # +1 for "Create new"

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
      UI.print(is_selected ? "{highlight}→ {reset}" : "  ")

      # Display try directory or "Create new" option
      if idx < tries.length
        try_dir = tries[idx]

        # Render the folder icon (always outside selection)
        UI.print "📁 "

        # Start selection highlighting after icon
        UI.print "{start_selected}" if is_selected

        # Format directory name with date styling
        if try_dir[:basename] =~ /^(\d{4}-\d{2}-\d{2})-(.+)$/
          date_part = $1
          name_part = $2

          # Render the date part (faint)
          UI.print "{dim_text}#{date_part}{reset}"

          # Render the separator (very faint)
          separator_matches = !@input_buffer.empty? && @input_buffer.include?('-')
          if separator_matches
            UI.print "{highlight}-{reset}"
          else
            UI.print "{dim_text}-{reset}"
          end

          # Render the name part with match highlighting
          if !@input_buffer.empty?
            UI.print highlight_matches_for_selection(name_part, @input_buffer, is_selected)
          else
            UI.print name_part
          end

          # Store plain text for width calculation
          display_text = "#{date_part}-#{name_part}"
        else
          # No date prefix - render folder icon then content
          if !@input_buffer.empty?
            UI.print highlight_matches_for_selection(try_dir[:basename], @input_buffer, is_selected)
          else
            UI.print try_dir[:basename]
          end
          display_text = try_dir[:basename]
        end

        # Format score and time for display (time first, then score)
        time_text = format_relative_time(try_dir[:mtime])
        score_text = sprintf("%.1f", try_dir[:score])

        # Combine time and score
        meta_text = "#{time_text}, #{score_text}"

        # Calculate padding (account for icon being outside selection)
        meta_width = meta_text.length + 1  # +1 for space before meta
        text_width = display_text.length  # Plain text width
        padding_needed = term_width - 5 - text_width - meta_width  # -5 for arrow + icon + space
        padding = " " * [padding_needed, 1].max

        # Print padding and metadata
        UI.print padding
        UI.print " {dim_text}#{meta_text}{reset}"

      else
        # This is the "Create new" option
        UI.print "+ "  # Plus sign outside selection

        UI.print "{start_selected}" if is_selected

        display_text = if @input_buffer.empty?
          "Create new"
        else
          "Create new: #{@input_buffer}"
        end

        UI.print display_text

        # Pad to full width
        text_width = display_text.length
        padding_needed = term_width - 5 - text_width  # -5 for arrow + "+ "
        UI.print " " * [padding_needed, 1].max
      end

      # End selection and reset all formatting
      UI.print "{end_selected}"
      UI.puts
    end

    # Scroll indicator if needed
    if total_items > max_visible
      UI.puts "{dim_text}#{separator}"
      UI.puts "{dim_text}[#{@scroll_offset + 1}-#{visible_end}/#{total_items}]"
    end

    # Instructions at bottom
    UI.puts "{dim_text}#{separator}"

    # Show delete status if present, otherwise show instructions
    if @delete_status
      UI.puts "{highlight}#{@delete_status}{reset}"
      @delete_status = nil  # Clear after showing
    else
      UI.puts "{dim_text}↑↓: Navigate  Enter: Select  Ctrl-D: Delete  ESC: Cancel{reset}"
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

    if seconds < 10
      "just now"
    elsif minutes < 60
      "#{minutes.to_i}m ago"
    elsif hours < 24
      "#{hours.to_i}h ago"
    elsif days < 30
      "#{days.to_i}d ago"
    elsif days < 365
      "#{(days/30).to_i}mo ago"
    else
      "#{(days/365).to_i}y ago"
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
        result += "{highlight}#{char}{text}"  # Yellow bold for matches (preserve bg)
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
        # Use same yellow for matches regardless of selection
        result += "{highlight}#{char}{text}"  # Preserve bg with text token
        query_index += 1
      else
        # Regular text
        result += char
      end
    end

    result
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

      STDERR.print("\e[2J\e[H\e[?25h")  # Clear, home, show cursor
      UI.puts "{h2}Enter new try name"
      UI.print "> {dim_text}#{date_prefix}-{reset}#{suggested_name}"
      UI.flush

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

  def handle_delete(try_dir)
    # Show delete confirmation dialog

    size = `du -sh #{try_dir[:path]}`.strip.split(/\s+/).first rescue "???"
    files = `find #{try_dir[:path]} -type f | wc -l`.strip.split(/\s+/).first rescue "???"

    UI.cls
    UI.puts "{h2}Delete Directory"
    UI.puts
    UI.puts "Are you sure you want to delete: {highlight}#{try_dir[:basename]}{reset}"
    UI.puts "  {dim_text}in #{try_dir[:path]}{reset}"
    UI.puts "  {dim_text}files: #{files} files{reset}"
    UI.puts "  {dim_text}size: #{size}{reset}"
    UI.puts
    UI.puts "{highlight}Type {text}YES{highlight} to confirm: "
    UI.flush
    STDERR.print("\e[?25h")  # Show cursor after flushing

    confirmation = ""
    # Read user input in cooked mode
    STDERR.cooked do
      STDIN.iflush
      confirmation = gets.chomp
    end

    if confirmation == "YES"
      begin
        FileUtils.rm_rf(try_dir[:path])
        @delete_status = "Deleted: #{try_dir[:basename]}"
        @all_tries = nil  # Clear cache to reload tries
      rescue => e
        @delete_status = "Error: #{e.message}"
      end
    else
      @delete_status = "Delete cancelled"
    end

    # Hide cursor again for main UI
    STDERR.print("\e[?25l")
  end
end

# Main execution with OptionParser subcommands
if __FILE__ == $0

  def print_global_help
    UI.print <<~HELP
      {h1}try something!{reset}

      Lightweight experiments for people with ADHD

      this tool is not meant to be used directly,
      but added to your ~/.zshrc or ~/.bashrc:

        {highlight}eval "$(#$0 init ~/src/tries)"{reset}

      for fish shell, add to ~/.config/fish/config.fish:

        {highlight}eval "$(#$0 init ~/src/tries | string collect)"{text}

      {h2}Usage:{text}

        init [--path PATH]  # Initialize shell function for aliasing
        cd [QUERY]          # Interactive selector; prints shell cd commands


      {h2}Defaults:{reset}
        Default path: {dim_text}~/src/tries{reset} (override with --path on commands)
        Current default: {dim_text}#{TrySelector::TRY_PATH}{reset}
    HELP
  end

  # Global help: show for --help/-h anywhere
  if ARGV.include?("--help") || ARGV.include?("-h")
    print_global_help
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

  command = ARGV.shift

  tries_path = extract_option_with_value!(ARGV, '--path') || TrySelector::TRY_PATH
  tries_path = File.expand_path(tries_path)

  def fish?
    ENV['SHELL']&.include?('fish')
  end

  case command
  when nil
    print_global_help
    exit 2
  when 'init'
    script_path = File.expand_path($0)

    if ARGV[0] && ARGV[0].start_with?('/')
      tries_path = File.expand_path(ARGV[0])
      ARGV.shift
    end

    path_arg = tries_path ? " --path \"#{tries_path}\"" : ""
    bash_or_zsh_script = <<~SHELL
      try() {
        script_path='#{script_path}';
        cmd=$(/usr/bin/env ruby "$script_path" cd#{path_arg} "$@" 2>/dev/tty);
        [ $? -eq 0 ] && eval "$cmd" || echo "$cmd";
      }
    SHELL

    fish_script = <<~SHELL
      function try
        set -l script_path "#{script_path}"
        set -l cmd (/usr/bin/env ruby "$script_path" cd#{path_arg} $argv 2>/dev/tty | string collect)
        test $status -eq 0 && eval $cmd || echo $cmd
      end
    SHELL

    puts fish? ? fish_script : bash_or_zsh_script

    exit 0
  when 'cd'
    search_term = ARGV.join(' ')
    selector = TrySelector.new(search_term, base_path: tries_path)
    result = selector.run

    if result
      parts = []
      parts << (fish? ? "set -l dir '#{result[:path]}'" : "dir='#{result[:path]}'")
      parts << "mkdir -p \"$dir\"" if result[:type] == :mkdir
      parts << "touch \"$dir\""
      parts << "cd \"$dir\""
      puts parts.join(' && ')
    end
  else
    warn "Unknown command: #{command}"
    print_global_help
    exit 2
  end
end
