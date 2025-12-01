# Token System Specification

## Overview

The token system provides a declarative way to apply text formatting without hardcoding ANSI escape sequences. Text containing tokens is processed through an expansion function that replaces tokens with their corresponding ANSI codes.

## Token Format

Tokens are placeholder strings enclosed in curly braces: `{token_name}`

- Opening tokens apply formatting: `{b}`, `{dim}`
- Closing tokens reset formatting: `{/b}`, `{/fg}`

## Available Tokens

### Text Formatting

| Token | Effect | Description |
|-------|--------|-------------|
| `{b}` | Bold + Yellow | Highlighted text, fuzzy match characters |
| `{/b}` | Reset bold + foreground | End bold formatting |
| `{dim}` | Gray (bright black) | Secondary/de-emphasized text |
| `{text}` | Full reset | Normal text |
| `{reset}` | Full reset | Complete reset of all formatting |
| `{/fg}` | Reset foreground | Reset foreground color only |

### Headings

| Token | Effect | Description |
|-------|--------|-------------|
| `{h1}` | Bold + Orange | Primary headings |
| `{h2}` | Bold + Blue | Secondary headings |

### Selection

| Token | Effect | Description |
|-------|--------|-------------|
| `{section}` | Bold | Start of selected/highlighted section |
| `{/section}` | Full reset | End of selected section |

### Deletion

| Token | Effect | Description |
|-------|--------|-------------|
| `{strike}` | Dark red background | Deleted/removed items |
| `{/strike}` | Reset background | End deletion formatting |

## Token Expansion

### Process

1. Scan input string for `{...}` patterns
2. Replace each known token with its ANSI sequence
3. Leave unknown tokens unchanged
4. Return formatted string

### Example

```
Input:  "Status: {b}OK{/b} - {dim}completed{/fg}"
Output: "Status: [bold yellow]OK[reset] - [gray]completed[reset fg]"
```

## Usage Patterns

### Fuzzy Match Highlighting

```
Input text: "2025-11-29-test"
Query: "te"
Rendered: "2025-11-29-{b}te{/b}st"
Displayed: "2025-11-29-" + [bold yellow]"te"[reset] + "st"
```

### Date Prefix Dimming

```
Directory: "2025-11-29-project"
Rendered: "{dim}2025-11-29-{/fg}project"
Displayed: [gray]"2025-11-29-"[reset] + "project"
```

### UI Elements

```
"{h1}Try Selector{reset}"
"{dim}Query:{/fg} {b}user-input{/b}"
```

## Design Principles

- **Declarative**: Styling defined in data, not code
- **Consistent**: Centralized token definitions ensure uniform appearance
- **Extensible**: New tokens can be added without changing usage patterns
- **Graceful degradation**: Unknown tokens pass through unchanged

## Validation Rules

- Unknown tokens are preserved as-is in output
- Malformed tokens (missing closing `}`) are preserved as-is
- Nested tokens are not supported
