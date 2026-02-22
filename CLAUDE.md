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

All logic lives in a single file: `wms` (zsh script, ~640 lines).

**Command routing**: `main()` at the bottom parses the first argument and calls `cmd_<subcommand>`. Aliases are handled via a `case` statement before dispatch.

**Data model**: Plain TSV file at `${XDG_DATA_HOME:-$HOME/.local/share}/wms/items.tsv`. Five fields: `name`, `location`, `category`, `tags`, `notes`. First line is a header row. `item_count()` always subtracts 1 to exclude the header. `parse_item()` splits a TSV line into named variables (`item_name`, `item_location`, etc.) using zsh parameter expansion - no external tools.

**fzf integration**: Interactive commands (`cmd_search`, `cmd_edit`, `cmd_rm`) launch fzf with `--bind` options that invoke the script itself as `wms _preview`, `wms _edit_line`, and `wms _delete_line` (private subcommands prefixed with `_`). This allows fzf to reload the list after edits/deletes using `reload(...)`. Items passed between the shell and fzf use line numbers (1-based data index) to identify records.

**Line number stability**: Edits and deletes use `sed -n "${file_line}p"` to fetch by line number and `sed -i "${file_line}d"` to delete. After any write, fzf reloads the full list, so stale line numbers are not a concern.

**Input sanitization**: `strip_tabs()` removes tab characters from all user input before writing to TSV to prevent field corruption.

## Key Conventions

- Functions are named `cmd_<subcommand>` for public commands and `cmd__<name>` (double underscore) for internal fzf callbacks.
- Color constants (`C_BOLD`, `C_RED`, etc.) are defined at the top and used throughout for consistent terminal output.
- Error output goes to stderr via `print -u2`. Normal output uses `print`.
- `readonly` globals are set at the top of the script for paths and the TSV header string.
