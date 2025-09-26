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
    '{reset}' => "\e[0m\e[39m\e[49m", '{reset_bg}' => "\e[49m", '{reset_fg}' => "\e[39m",
    '{clear_screen}' => "\e[2J", '{clear_line}' => "\e[2K", '{home}' => "\e[H", '{clear_below}' => "\e[0J",
    '{hide_cursor}' => "\e[?25l", '{show_cursor}' => "\e[?25h",
    '{start_selected}' => "\e[1m", '{end_selected}' => "\e[0m", '{bold}' => "\e[1m"
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
    # Always fine into the buffer
    unless @@current_line.empty?
      @@buffer << @@current_line
      @@current_line = ""
    end

    # In non-TTY contexts, print plain text without control codes or tokens
    unless io.tty?
      plain = @@buffer.join("\n").gsub(/\{.*?\}/, '')
      io.print(plain)
      io.print("\n") unless plain.end_with?("\n")
      @@last_buffer = []
      @@buffer.clear
      @@current_line = ""
      io.flush
      return
    end

    # Position cursor at home for TTY
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
          processed_line = expand_tokens(current_line)
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
    @@current_line = ""
    @@buffer.clear
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

  # Expand tokens in a string to ANSI sequences
  def self.expand_tokens(str)
    str.gsub(/\{.*?\}/) do |match|
      TOKEN_MAP.fetch(match) { raise "Unknown token: #{match}" }
    end
  end

end

class TrySelector
  TRY_PATH = ENV['TRY_PATH'] || File.expand_path("~/src/tries")

  def initialize(search_term = "", base_path: TRY_PATH, initial_input: nil, test_render_once: false, test_no_cls: false, test_keys: nil, test_confirm: nil)
    @search_term = search_term.gsub(/\s+/, '-')
    @cursor_pos = 0
    @scroll_offset = 0
    @input_buffer = initial_input ? initial_input.gsub(/\s+/, '-') : @search_term
    @selected = nil
    @all_trials = nil  # Memoized trials
    @base_path = base_path
    @delete_status = nil  # Status message for deletions
    @test_render_once = test_render_once
    @test_no_cls = test_no_cls
    @test_keys = test_keys
    @test_confirm = test_confirm

    FileUtils.mkdir_p(@base_path) unless Dir.exist?(@base_path)
  end

  def run
    # Always use STDERR for UI (it stays connected to TTY)
    # This allows stdout to be captured for the shell commands
    setup_terminal

    # In test mode, render once and exit without TTY requirements
    if @test_render_once
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
      STDERR.print("\e[2J\e[H\e[?25l")  # Direct clear screen, home, hide cursor
    end
  end

  def restore_terminal
    # Clear screen completely before restoring (skip in test mode)
    unless @test_no_cls
      STDERR.print("\e[2J\e[H\e[?25h")  # Direct clear, home, show cursor
    end
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

      key = read_key

      case key
      when "\r"  # Enter (carriage return)
        if @cursor_pos < tries.length
          handle_selection(tries[@cursor_pos])
        else
          # Selected "Create new"
          handle_create_new
        end
        break if @selected
      when "\e[A", "\x10", "\x0B"  # Up arrow or Ctrl-P or Ctrl-K
        @cursor_pos = [@cursor_pos - 1, 0].max
      when "\e[B", "\x0E", "\n"  # Down arrow or Ctrl-N or Ctrl-J
        @cursor_pos = [@cursor_pos + 1, total_items - 1].min
      when "\e[C"  # Right arrow - ignore
        # Do nothing
      when "\e[D"  # Left arrow - ignore
        # Do nothing
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

  def read_key
    if @test_keys && !@test_keys.empty?
      return @test_keys.shift
    end
    UI.read_key
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
      UI.print(is_selected ? "{highlight}→ {reset_fg}" : "  ")

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
          UI.print "{dim_text}#{date_part}{reset_fg}"

          # Render the separator (very faint)
          separator_matches = !@input_buffer.empty? && @input_buffer.include?('-')
          if separator_matches
            UI.print "{highlight}-{reset_fg}"
          else
            UI.print "{dim_text}-{reset_fg}"
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
        UI.print "{end_selected}" if is_selected
        UI.print " {dim_text}#{meta_text}{reset_fg}"

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
      UI.puts "{dim_text}↑↓/Ctrl-P,N,J,K: Navigate  Enter: Select  Ctrl-D: Delete  ESC: Cancel{reset}"
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

      UI.cls  # Clear screen using UI system
      UI.puts "{h2}Enter new try name"
      UI.puts
      UI.puts "> {dim_text}#{date_prefix}-{reset}"
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

    # Confirmation input: in tests, use injected value; otherwise read from TTY
    confirmation = ""
    if @test_confirm || !STDERR.tty?
      confirmation = (@test_confirm || STDIN.gets)&.chomp.to_s
    else
      STDERR.cooked do
        STDIN.iflush
        confirmation = gets.chomp
      end
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
    text = <<~HELP
      {h1}try something!{reset}

      Lightweight experiments for people with ADHD

      this tool is not meant to be used directly,
      but added to your ~/.zshrc or ~/.bashrc:

        {highlight}eval "$(#$0 init ~/src/tries)"{reset}

      for fish shell, add to ~/.config/fish/config.fish:

        {highlight}eval (#$0 init ~/src/tries | string collect){reset}

      {h2}Usage:{text}

        init [--path PATH]  # Initialize shell function for aliasing
        cd [QUERY] [name?]  # Interactive selector; Git URL shorthand supported
        clone <git-uri> [name]  # Clone git repo into date-prefixed directory
        worktree dir [name]  # Create date-prefixed dir; add worktree from CWD if git repo
        worktree <repo-path> [name]  # Same as above, but source repo is <repo-path>

      {h2}Clone Examples:{text}

        try clone https://github.com/tobi/try.git
        # Creates: 2025-08-27-tobi-try

        try clone https://github.com/tobi/try.git my-fork
        # Creates: my-fork

        try https://github.com/tobi/try.git
        # Shorthand for clone (same as first example)

      {h2}Worktree Examples:{text}

        try worktree dir
        # From current git repo, creates: 2025-08-27-repo-name and adds detached worktree

        try worktree ~/src/github.com/tobi/try my-branch
        # From given repo path, creates: 2025-08-27-my-branch and adds detached worktree

      {h2}Defaults:{reset}
        Default path: {dim_text}~/src/tries{reset} (override with --path on commands)
        Current default: {dim_text}#{TrySelector::TRY_PATH}{reset}
    HELP
    # Help should not manipulate the screen; print plainly to STDOUT.
    # Expand tokens to ANSI only when STDOUT is a TTY; otherwise strip tokens.
    out = if STDOUT.tty?
      UI.expand_tokens(text)
    else
      text.gsub(/\{.*?\}/, '')
    end
    STDOUT.print(out)
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

  tries_path = extract_option_with_value!(ARGV, '--path') || TrySelector::TRY_PATH
  
  command = ARGV.shift
  tries_path = File.expand_path(tries_path)

  # Test-only flags (undocumented; aid acceptance tests)
  and_type = extract_option_with_value!(ARGV, '--and-type')
  and_exit = !!ARGV.delete('--and-exit')
  and_keys_raw = extract_option_with_value!(ARGV, '--and-keys')
  and_confirm = extract_option_with_value!(ARGV, '--and-confirm')

  def parse_test_keys(spec)
    return nil unless spec && !spec.empty?
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
      when 'CTRL-D', 'CTRLD' then keys << "\x04"
      when 'CTRL-P', 'CTRLP' then keys << "\x10"
      when 'CTRL-N', 'CTRLN' then keys << "\x0E"
      when 'CTRL-J', 'CTRLJ' then keys << "\n"
      when 'CTRL-K', 'CTRLK' then keys << "\x0B"
      when /^TYPE=(.*)$/
        $1.each_char { |ch| keys << ch }
      else
        keys << tok if tok.length == 1
      end
    end
    keys
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

    full_path = File.join(tries_path, dir_name)
    [
      { type: 'target', path: full_path },
      { type: 'mkdir' },
      { type: 'echo', msg: "Using {highlight}git clone{reset_fg} to create this trial from #{git_uri}." },
      { type: 'git-clone', uri: git_uri },
      { type: 'touch'},
      { type: 'cd' }
    ]
  end

  def cmd_init!(args, tries_path)
    script_path = File.expand_path($0)

    if args[0] && args[0].start_with?('/')
      tries_path = File.expand_path(args.shift)
    end

    path_arg = tries_path ? " --path \"#{tries_path}\"" : ""
    bash_or_zsh_script = <<~SHELL
      try() {
        script_path='#{script_path}'
        # Check if first argument is a known command
        case "$1" in
          clone|worktree|init)
            cmd=$(/usr/bin/env ruby "$script_path"#{path_arg} "$@" 2>/dev/tty)
            ;;
          *)
            cmd=$(/usr/bin/env ruby "$script_path" cd#{path_arg} "$@" 2>/dev/tty)
            ;;
        esac
        rc=$?
        if [ $rc -eq 0 ]; then
          case "$cmd" in
            *" && "*) eval "$cmd" ;;
            *) printf %s "$cmd" ;;
          esac
        else
          printf %s "$cmd"
        fi
      }
    SHELL

    fish_script = <<~SHELL
      function try
        set -l script_path "#{script_path}"
        # Check if first argument is a known command
        switch $argv[1]
          case clone worktree init
            set -l cmd (/usr/bin/env ruby "$script_path"#{path_arg} $argv 2>/dev/tty | string collect)
          case '*'
            set -l cmd (/usr/bin/env ruby "$script_path" cd#{path_arg} $argv 2>/dev/tty | string collect)
        end
        set -l rc $status
        if test $rc -eq 0
          if string match -r ' && ' -- $cmd
            eval $cmd
          else
            printf %s $cmd
          end
        else
          printf %s $cmd
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
      base = if custom && !custom.strip.empty?
        custom.gsub(/\s+/, '-')
      else
        File.basename(repo_dir)
      end
      date_prefix = Time.now.strftime("%Y-%m-%d")
      # Prefer bumping numeric suffix if base ends with digits and today's name exists
      base = resolve_unique_name_with_versioning(tries_path, date_prefix, base)
      dir_name = "#{date_prefix}-#{base}"
      full_path = File.join(tries_path, dir_name)
      tasks = [
        { type: 'target', path: full_path },
        { type: 'mkdir' }
      ]
      # Only add worktree when a .git directory exists at that path
      if File.directory?(File.join(repo_dir, '.git'))
        tasks << { type: 'echo', msg: "Using {highlight}git worktree{reset_fg} to create this trial from #{repo_dir}." }
        tasks << { type: 'git-worktree', repo: repo_dir }
      end
      tasks += [
        { type: 'touch' },
        { type: 'cd' }
      ]
      return tasks
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
      return [
        { type: 'target', path: full_path },
        { type: 'mkdir' },
        { type: 'echo', msg: "Using {highlight}git clone{reset_fg} to create this trial from #{git_uri}." },
        { type: 'git-clone', uri: git_uri },
        { type: 'touch' },
        { type: 'cd' }
      ]
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
    if and_exit
      selector.run
      exit 0
    end
    result = selector.run
    return nil unless result
    tasks = [{ type: 'target', path: result[:path] }]
    tasks += [{ type: 'mkdir' }] if result[:type] == :mkdir
    tasks += [{ type: 'touch' }, { type: 'cd' }]
    tasks
  end

  # --- Shell emission helpers (moved out of UI) ---
  def join_commands(parts)
    parts.join(" \\\n  && ")
  end

  def emit_script(parts)
    puts join_commands(parts)
  end

  # tasks: [{type: 'target', path: '/abs/dir'}, {type: 'mkdir'|'touch'|'cd'|'git-clone'|'git-worktree', ...}]
  def emit_tasks_script(tasks)
    target = tasks.find { |t| t[:type] == 'target' }
    full_path = target && target[:path]
    raise 'emit_tasks_script requires a target path' unless full_path

    parts = []
    q = "'" + full_path.gsub("'", %q('"'"'')) + "'"
    tasks.each do |t|
      case t[:type]
      when 'echo'
        msg = t[:msg] || ''
        expanded = UI.expand_tokens(msg)
        m = "'" + expanded.gsub("'", %q('"'"'')) + "'"
        parts << "echo #{m}"
      when 'mkdir'
        parts << "mkdir -p #{q}"
      when 'git-clone'
        parts << "git clone '#{t[:uri]}' #{q}"
      when 'git-worktree'
        if t[:repo]
          r = "'" + t[:repo].gsub("'", %q('"'"'')) + "'"
          parts << "/usr/bin/env sh -c 'if git -C " + r + " rev-parse --is-inside-work-tree >/dev/null 2>&1; then repo=\$(git -C " + r + " rev-parse --show-toplevel); git -C \"$repo\" worktree add --detach #{q} >/dev/null 2>&1 || true; fi; exit 0'"
        else
          parts << "/usr/bin/env sh -c 'if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then repo=\$(git rev-parse --show-toplevel); git -C \"$repo\" worktree add --detach #{q} >/dev/null 2>&1 || true; fi; exit 0'"
        end
      when 'touch'
        parts << "touch #{q}"
      when 'cd'
        parts << "cd #{q}"
      end
    end
    emit_script(parts)
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
  def fish?
    ENV['SHELL']&.include?('fish')
  end


  case command
  when nil
    print_global_help
    exit 2
  when 'clone'
    tasks = cmd_clone!(ARGV, tries_path)
    emit_tasks_script(tasks)
    exit 0
  when 'init'
    cmd_init!(ARGV, tries_path)
    exit 0
  when 'worktree'
    sub = ARGV.shift
    case sub
    when nil, 'dir'
      # try worktree dir [name]  (or no subcommand -> current directory)
      custom = ARGV.join(' ')
      base = if custom && !custom.strip.empty?
        custom.gsub(/\s+/, '-')
      else
        begin
          File.basename(File.realpath(Dir.pwd))
        rescue
          File.basename(Dir.pwd)
        end
      end
      date_prefix = Time.now.strftime("%Y-%m-%d")
      base = resolve_unique_name_with_versioning(tries_path, date_prefix, base)
      dir_name = "#{date_prefix}-#{base}"
      full_path = File.join(tries_path, dir_name)
      tasks = [
        { type: 'target', path: full_path },
        { type: 'mkdir' }
      ]
      if File.directory?(File.join(Dir.pwd, '.git'))
        tasks << { type: 'echo', msg: "Using {highlight}git worktree{reset_fg} to create this trial from #{Dir.pwd}." }
        tasks << { type: 'git-worktree' }
      end
      tasks += [ { type: 'touch' }, { type: 'cd' } ]
      emit_tasks_script(tasks)
      exit 0
    else
      # try worktree <repo-path> [name]
      repo_dir = File.expand_path(sub)
      custom = ARGV.join(' ')
      base = if custom && !custom.strip.empty?
        custom.gsub(/\s+/, '-')
      else
        begin
          File.basename(File.realpath(repo_dir))
        rescue
          File.basename(repo_dir)
        end
      end
      date_prefix = Time.now.strftime("%Y-%m-%d")
      base = resolve_unique_name_with_versioning(tries_path, date_prefix, base)
      dir_name = "#{date_prefix}-#{base}"
      full_path = File.join(tries_path, dir_name)
      tasks = [
        { type: 'target', path: full_path },
        { type: 'mkdir' }
      ]
      # We’ll ask emit_tasks_script to add a worktree from the given repo path
      tasks << { type: 'echo', msg: "Using {highlight}git worktree{reset_fg} to create this trial from #{repo_dir}." }
      tasks << { type: 'git-worktree', repo: repo_dir }
      tasks += [ { type: 'touch' }, { type: 'cd' } ]
      emit_tasks_script(tasks)
      exit 0
    end
  when 'cd'
    tasks = cmd_cd!(ARGV, tries_path, and_type, and_exit, and_keys, and_confirm)
    emit_tasks_script(tasks) if tasks
    exit 0
  else
    warn "Unknown command: #{command}"
    print_global_help
    exit 2
  end

end
