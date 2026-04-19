# wms hardening plan

Goal: fix the data-safety and correctness issues found in review. Leave stylistic and performance nits for a separate pass.

## Status legend

- [x] done + tested
- [ ] not started
- [~] partial

---

## Pass 1 - Data safety + correctness (DONE, v1.1.2)

Senior-eng lens: never lose or corrupt user data, never silently misbehave after an upgrade.

| # | Change | Site | Verify | Status |
|---|--------|------|--------|--------|
| 1 | `mktemp` now writes sibling of data file (`$WMS_FILE.XXXXXX`), so `mv` is intra-FS atomic rename | wms:391, wms:503, wms:658 | proved temp + data share device | [x] |
| 2 | `backup_data` rotates `.bak.1` → `.bak.2` → `.bak.3` instead of clobbering a single slot | wms:26-28 | v3/v2/v1 in expected slots after 3 calls | [x] |
| 3 | `init_data` compares existing file's first line against `TSV_HEADER`; aborts on mismatch | wms:20-23 | bad header + legacy 4-col both exit 1; valid + fresh pass | [x] |
| 4 | Install PATH check uses delimited `[[ ":$PATH:" == *":$bin_dir:"* ]]` instead of `grep -qF` | wms:514 | superstring warns, exact match silent | [x] |
| - | Version bump 1.1.1 → 1.1.2 | wms:5 | `./wms version` prints `wms 1.1.2` | [x] |

Smoke tests (`add`, `ls`, `find` single-term, `find` multi-term AND) all green.

---

## Pass 2 - Remaining work

### Correctness bugs

- [ ] **`format_table` header prints literal `\tLOCATION\t...`** (wms:91, wms:93). `printf "%s\n" "$header"` does not expand `\t`. `column -t` then treats the whole string as one field so the header row never aligns with data rows. Fix: build the header with actual tab chars (`$'\t'`) or use `printf` with `\t` in the format string, not the argument. Low risk, visible regression of table output.

### Data safety - deferred

- [ ] **No write lock.** Two concurrent `wms add` / `rm` / `edit` can corrupt TSV. `flock(1)` is not installed by default on macOS (requires `brew install util-linux`). For a single-user desktop tool the risk is low; decide whether to ship a `flock`-based guard with a graceful no-op fallback when missing, or document the single-writer assumption.

### Design / maintainability

- [ ] **`parse_item` leaks globals** (wms:64). Sets `item_name`, `item_location`, etc. in caller scope. Every caller must remember to declare them `local` first. Consider zsh name refs (`typeset -n`) or returning a packed string.
- [ ] **`strip_tabs` forks two procs per field** (wms:45). Replace with pure-zsh substitution: `${1//[$'\t\r\n']/}`.
- [ ] **`cmd_find` runs N sequential greps** (wms:274). For small data it is fine; a single awk pass with IGNORECASE and AND semantics would be one read.
- [ ] **`format_table` + ANSI header alignment** (wms:91). `column -t` counts ANSI escape bytes as width, so the colored header misaligns. Strip color before `column`, re-apply after, or pad manually.
- [ ] **Help-text duplicated** across `help_add`, `help_find`, `help_ls`, `help_rm`, `help_edit`, and the ADD FLAGS block inside `cmd_help`. Single source of truth (assoc array) or drop per-command help blocks.
- [ ] **`cmd_search` receives `"$@"` but ignores it** (wms:665 dispatch, wms:202 body). Drop the pass-through or implement it.

### Nits

- [ ] `cmd__preview` trailing `return 0` after last statement is dead (wms:611).
- [ ] `main` uses `shift 2>/dev/null || true` (wms:654). `(( $# )) && shift` reads clearer.
- [ ] `item_count` via `wc -l` (wms:51) assumes a trailing newline. Script always writes one, but hand-edits could break the count.
- [ ] `vared` is single-line, so notes cannot contain `\n`. Document in `help_edit` / `cmd_help`.
- [ ] `cmd__list_items` uses `%06d` (wms:579), capping the inventory at 999999 items. Acceptable; document.

### Process / tooling

- [ ] **No automated tests.** Add a `tests/` harness that sets `XDG_DATA_HOME=$(mktemp -d)/share` and drives the CLI non-interactively (`add`, `ls`, `find`). Diff output against fixtures. Skip fzf-driven commands or exercise them via the private `_edit_line` / `_delete_line` subcommands.
- [ ] **No CI.** GitHub Actions with zsh + fzf + a zsh-aware lint pass would catch regressions.
- [ ] **`PLAN.md` disposition.** Decide whether to keep this file in-repo (living doc) or move it under `.claude/plans/` or delete after each pass.
- [ ] **Commit strategy.** Pass 1 changes are currently unstaged. Options: one conventional commit `fix: harden data writes + schema check + install PATH match`, or split per fix.

---

## Open decisions for the user

1. Commit Pass 1 as one commit or split per fix?
2. Keep `PLAN.md` in repo, move under `.claude/`, or delete once landed?
3. Tackle Pass 2 items this session or a future branch?
4. Ship `flock`-based locking with macOS fallback, or formally document wms as a single-writer tool?

---

## Test strategy (reusable)

No test harness yet. Drive the real binary against a throwaway data dir:

```sh
export XDG_DATA_HOME=$(mktemp -d)/share
./wms add "Passport" -l "Drawer 2" -c Documents
./wms add "Keys" -l "Hook by door"
./wms add "HDMI Cable" -l "Box A" -c Electronics -t "tv"
./wms find passport
./wms find tv cable
./wms ls
```

Schema check:

```sh
printf 'bogus\theader\n' > "$XDG_DATA_HOME/wms/items.tsv"
./wms ls   # expect exit 1
```

PATH check:

```sh
PATH="/usr/bin:/bin:/foo/.local/binbaz" ./wms install    # expect Note
PATH="/usr/bin:/bin:$HOME/.local/bin" ./wms install       # expect no Note
```

Backup rotation (requires sourcing the script with `main` stubbed out, since `rm` / `edit` need fzf + tty):

```sh
cp wms /tmp/wms_test
sed -i.orig 's|^main "\$@"$|true|' /tmp/wms_test && rm -f /tmp/wms_test.orig
export XDG_DATA_HOME=$(mktemp -d)/share
mkdir -p "$XDG_DATA_HOME/wms"
printf 'name\tlocation\tcategory\ttags\tnotes\nv1\t\t\t\t\n' > "$XDG_DATA_HOME/wms/items.tsv"
zsh -c '
  source /tmp/wms_test
  for v in v2 v3 v4; do
    backup_data
    printf "%s\n%s\t\t\t\t\n" "$TSV_HEADER" "$v" > "$WMS_FILE"
  done
  ls -1 "$(dirname "$WMS_FILE")"
'
```

## Done when

Pass 1: all four fixes landed and tested. [x]
Pass 2: triage decisions recorded above; execution deferred to next session.
