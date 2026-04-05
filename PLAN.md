# wms Fix Plan

## Bugs (data correctness)

- [x] **#1 grep regex bug** - `cmd_find` uses `grep -i` which treats terms as regex. `grep -iF` for literal matching.
- [x] **#2 awk backslash corruption** - `_do_edit` uses `awk -v new=...` which interprets `\` sequences. Replaced with head/tail/printf.
- [x] **#3 strip_tabs missing newlines** - `strip_tabs()` doesn't strip `\n`, allowing multi-line paste to corrupt TSV.
- [x] **#4 PATH check regex** - `cmd_install` uses `grep -q` instead of `grep -qF` for PATH check.

## Robustness

- [x] **#5 Non-interactive add** - Skip prompts for optional fields when stdin is not a tty.
- [x] **#6 Backup before destructive writes** - `cp` backup before mutations in rm, delete_line, _do_edit.
- [x] **#7 exit vs return** - Replace `exit` with `return` in functions for consistency.

## Behavior

- [x] **#9 find exit code** - `wms find` returns 1 on no match (like grep).

## Docs/Cleanup

- [x] **#10 README key table** - Added `ctrl-a` (add item) to the README fzf keys table.
- [x] **#12 list_items consolidation** - Replaced `tail|nl|awk` with single awk in `cmd__list_items`.

## Extras

- [x] **Version** - Added `WMS_VERSION=1.1.0` and `--version` flag.

## Testing

- [x] **Test script** - Created `test.sh` (21 tests: add, find, ls, special chars, backslashes, exit codes, TSV integrity). All passing.
