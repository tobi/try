# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a lightweight experiment directory management utility called "try" that helps create and navigate experiment/prototype directories. It's implemented as a pure Ruby TUI application with fuzzy search and intelligent scoring.

### Current Implementation
- `try.rb`: Pure Ruby implementation with built-in TUI components
- `shell.sh`: Contains the `trial()` shell function (legacy, to be updated to `try()`)
- `refs/trial`: Original bash script with gum (reference implementation)
- `Gemfile`: Basic Ruby project setup

### Key Features
- Interactive TUI with fuzzy search
- Smart scoring algorithm that considers:
  - Character matches (with bonuses for word boundaries and proximity)
  - Directory age (both creation and last access time)
  - Match density and string length
- Auto-prefixes new directories with date (YYYY-MM-DD format)
- Updates access time on directory selection for better recency sorting

## Development Commands

This is a Ruby project using bundler. Common commands:
- `bundle install` - Install gem dependencies
- `ruby try.rb [search_term]` - Run the try selector
- `ruby try.rb --help` - Show help information
- `ruby try.rb --eval` - Output shell function for integration
- Test the shell integration: `eval "$(ruby try.rb --eval)" && try [search_term]`

## Environment Configuration

- `TRY_PATH` - Environment variable to override the default directory location
  - Default: `~/src/tries`
  - Example: `export TRY_PATH=~/projects/experiments`

## Architecture Notes

### Scoring Algorithm
The scoring system balances multiple factors:
- **Match quality**: Points for each matching character, bonuses for word boundaries
- **Proximity**: Consecutive matches score higher (1/sqrt(distance) decay)
- **Length penalty**: Shorter names score higher for the same match
- **Time-based scoring**:
  - Creation time: 2.0 / sqrt(days_old + 1)
  - Access time: 3.0 / sqrt(hours_old + 1)

### Shell Integration
The tool outputs shell commands that:
1. Set a variable with the path
2. Touch the directory (update access time)
3. Change to the directory

Example output:
```bash
dir='/path/to/directory' && \
touch "$dir" && \
cd "$dir"
```