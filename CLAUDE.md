# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`wms` is a terminal tool for tracking where physical items are stored. Single zsh script, no build system. Requires `fzf` for interactive features.

## Running and Testing

```sh
# Run directly from the repo (no install needed)
./wms [command]

# Install symlink to ~/.local/bin/wms
./wms install

# Test a specific command manually
./wms add "Test Item" -l "Shelf 1" -c "Test"
./wms find "Test Item"
./wms ls
```

There is no automated test suite. Test changes manually by exercising the affected commands. Check that data in `~/.local/share/wms/items.tsv` remains valid TSV after operations.

## Architecture

All logic lives in a single file: `wms` (zsh script, ~676 lines).

**Command routing**: `main()` at the bottom parses the first argument and calls `cmd_<subcommand>`. Aliases (`s`=search, `f`=find, `e`=edit, `list`=ls, `remove`=rm) are resolved in the same `case` statement before dispatch.

**Data model**: Plain TSV file at `${XDG_DATA_HOME:-$HOME/.local/share}/wms/items.tsv`. Five fields: `name`, `location`, `category`, `tags`, `notes`. First line is a header row. `item_count()` always subtracts 1 to exclude the header. `parse_item()` splits a TSV line into named variables (`item_name`, `item_location`, etc.) using zsh parameter expansion - no external tools. `backup_data()` copies the TSV to `items.tsv.bak` before any destructive operation (delete, edit).

**Versioning**: `WMS_VERSION` is a `readonly` global at the top. Exposed via `wms version`, `wms -v`, and `wms --version`.

**fzf integration**: Interactive commands (`cmd_search`, `cmd_edit`, `cmd_rm`) launch fzf with `--bind` options that invoke the script itself as `wms _preview`, `wms _edit_line`, and `wms _delete_line` (private subcommands prefixed with `_`). This allows fzf to reload the list after edits/deletes using `reload(...)`. Items are identified by line numbers passed through fzf: `cmd__list_items` uses a single `awk` pass that prints a zero-padded `NR-1` prefix, so all consumers coerce with `$((10#$item_num))` to force base-10 interpretation.

**Line number stability**: Edits and deletes use `sed -n "${file_line}p"` to fetch by line number. Deletes use `sed "${file_line}d"` via a temp file. Edits use `head/printf/tail` to reconstruct the file, which preserves all characters literally without awk's newline/escape edge cases. After any write, fzf reloads the full list, so stale line numbers are not a concern.

**Input sanitization**: `strip_tabs()` removes tab, carriage return, and newline characters from all user input before writing to TSV to prevent field corruption.

**Non-interactive mode**: `cmd_add` checks `[[ -t 0 ]]` before prompting for optional fields - when stdin is not a terminal (scripts, pipes), omitted fields are written as empty strings without prompting.

**Exit vs return**: All functions use `return N` rather than `exit N` to avoid terminating the shell when the script is sourced. `exit` is only used at the very end of `main()` via its implicit return.

## Key Conventions

- Functions are named `cmd_<subcommand>` for public commands and `cmd__<name>` (double underscore) for internal fzf callbacks. Exception: `_do_edit()` is a shared helper called by both `cmd_edit` and `cmd__edit_line` - it doesn't follow either pattern.
- `cmd_add` and `_do_edit` call `stty sane` at entry to reset terminal state. fzf's `execute()` binding runs subcommands while the terminal is in raw mode; without this reset, `read` and `vared` prompts behave incorrectly.
- Interactive field editing uses zsh's `vared` builtin, which pre-populates the input buffer with the current value. This is zsh-specific and has no portable shell equivalent.
- Color constants (`C_BOLD`, `C_RED`, etc.) are defined at the top and used throughout for consistent terminal output.
- Error output goes to stderr via `print -u2`. Normal output uses `print -r --` when the line contains user data (prevents zsh from interpreting backslash escapes), plain `print` for static text.
- `cmd_add` rejects multiple positional arguments to catch unquoted multi-word names (e.g. `wms add TV Remote` errors instead of silently dropping "Remote").
- `readonly` globals are set at the top of the script for paths and the TSV header string.
