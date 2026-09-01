# Ghostty + tmux + Claude Code setup

A reproducible terminal setup: [Ghostty](https://ghostty.org) as the terminal,
[tmux](https://github.com/tmux/tmux) for panes and sessions, and a custom
[Claude Code](https://claude.com/claude-code) status line. Gruvbox Light theme,
everything in maroon (`#9d0006`).

One command on a fresh machine:

```bash
git clone https://github.com/apurwa/ghostty-tmux-claude-setup.git
cd ghostty-tmux-claude-setup
./install.sh          # copy configs   (or: ./install.sh --link to symlink)
```

Then reload Ghostty (`Cmd+Shift+,`) and open a fresh tmux window. That's it.

The installer is idempotent and backs up anything it replaces to
`<file>.bak-<timestamp>`, so it is safe to re-run and easy to undo.

---

## What you get

**Status line** — four lines, all bold maroon, single icon per line:

```
 ~/Projects/slrepo/src › ◇ fix-auth
 apurwa › ai-job-search › feature/auth* › PR #128 changes_requested
 5h 43% (1h49m) › 7d 86% (3d5h) › ██░░░░░░ 31%
 Opus 5 › high › thinking › ~$35.11
```

|  | Line | Shows |
|---|---|---|
|  | project | full working-directory path (~ for home) › `◇` worktree |
|  | repo | `username` › `repo` › branch (`*` dirty, `↑n↓n` vs upstream, `Δn` vs default) › PR # + review state |
|  | usage | 5-hour and 7-day limits with reset countdowns; context-window bar + % |
|  | session | model › effort › thinking › estimated session cost |

**Ghostty**
- **Shift+Enter inserts a newline** in Claude Code (and other TUIs) instead of
  submitting — sends `ESC`+`Enter`, which passes cleanly through tmux.
- **Gruvbox Light** theme (background `#fbf1c7`).

**Claude Code**
- Theme set to `light` so its own UI text stays legible on the cream
  background (the default dark theme's dimmed text is light-grey and washes out).

**tmux**
- **Right-click any pane → Split / New Window / Zoom / Kill menu**, even inside
  a mouse-capturing app like Claude Code (see the note under *Design decisions*).
- `Ctrl-B |` split right, `Ctrl-B -` split down — both open in the current
  directory. `Ctrl-B c` new window, same directory.
- `Alt`+arrow to move between panes with no prefix. Mouse on: click to focus,
  drag borders to resize, wheel to scroll.
- Windows numbered from 1 and renumbered on close; centred window list; maroon
  status bar to match. `Ctrl-B r` reloads the config.

---

## Layout

```
ghostty/config                  → ~/.config/ghostty/config
tmux/tmux.conf                  → ~/.tmux.conf
claude/statusline-command.sh    → ~/.claude/statusline-command.sh
claude/glyph-test.sh            → ~/.claude/glyph-test.sh   (icon/width tester)
claude/settings.snippet.json    → merged into ~/.claude/settings.json
```

The installer never overwrites `settings.json` — it merges only the `theme` and `statusLine`
keys with `jq`, so your existing permissions, model, and other settings survive.

---

## Requirements

- **macOS** with [Homebrew](https://brew.sh) (the installer uses it for deps).
- **Ghostty**, **tmux 3.3+** (3.7+ recommended), and **Claude Code**.
- `jq` and a **Symbols-only Nerd Font** — the installer adds both:
  `brew install jq` and `brew install --cask font-symbols-only-nerd-font`.

The status line reads Claude Code's own usage data, so no API key or network
call is involved. Session cost is estimated from the transcript — see below.

---

## Design decisions

A few choices that aren't obvious, recorded so future-you doesn't re-derive them:

- **Right-click needed an override, and it's a tmux default — not a Ghostty
  limit.** tmux's stock binding only shows the pane menu when no foreground app
  has mouse capture on; inside Claude Code / vim / less it forwards the click to
  the app instead. `tmux.conf` rebinds `MouseDown3Pane` unconditionally so the
  menu always opens. Trade-off: apps no longer receive a right-click (rarely
  used in a terminal).

- **Shift+Enter needs tmux `extended-keys on`**, not just the Ghostty keybind.
  Without it tmux flattens the modified key back to a plain Enter before the app
  sees it. Both halves are in this repo.

- **Status icons are Nerd Font glyphs, not emoji.** Emoji ignore ANSI colour
  (they'd render multicolour, not maroon) and are double-width. The Nerd Font
  glyphs are monochrome, single-width, and inherit the maroon. They're written
  as octal escapes in the script because private-use-area characters get
  stripped when pasted through many editors and tools.

- **"Daily / monthly" limits don't exist.** Claude Code's status line payload
  only exposes rolling **5-hour** and **7-day** windows, so that's what's shown.

- **Session cost is an estimate.** Cost isn't in the status line payload; the
  script sums per-response token usage from the transcript and prices it with a
  rate table (Opus/Sonnet/Haiku/Fable, cache tiers priced separately). Update
  the `RATES` in `session_cost()` if prices change. A resumed session only counts
  what its current transcript holds. Shown with a `~` for that reason.

- **The palette is tuned for a light background.** If you switch Ghostty to a
  dark theme, the maroon may look muddy — retune the colours near the top of
  `statusline-command.sh`.

Run `~/.claude/glyph-test.sh` if you swap in a new icon; it prints candidate
glyphs between alignment pipes so you can spot any that render double-width.

---

## Uninstall

Every file the installer touched has a `.bak-<timestamp>` beside it. Restore the
most recent, or just delete the four installed files and remove the `statusLine`
block from `~/.claude/settings.json`.
