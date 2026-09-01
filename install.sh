#!/usr/bin/env bash
# Fresh-machine setup for the Ghostty + tmux + Claude Code status line described
# in README.md. Idempotent: safe to re-run. Backs up anything it would replace
# to <file>.bak-<timestamp>. Nothing here is destructive without a backup.
#
#   ./install.sh          apply everything
#   ./install.sh --link   symlink the repo's files instead of copying, so a
#                         future `git pull` updates the live config in place
#
# macOS-oriented (Homebrew, Ghostty.app). On Linux, install jq + a Nerd Font
# with your package manager and copy the three config files by hand; the tmux
# and status line pieces work unchanged.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK=0; [ "${1:-}" = "--link" ] && LINK=1
STAMP="$(date +%Y%m%d-%H%M%S)"
say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! \033[0m%s\n' "$*"; }

# place <src-in-repo> <dest> — back up an existing dest, then copy or symlink.
place() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    # Already the exact symlink we'd create? nothing to do.
    [ "$LINK" = 1 ] && [ "$(readlink "$dest" 2>/dev/null)" = "$src" ] && { say "ok   $dest"; return; }
    cp -a "$dest" "$dest.bak-$STAMP"; warn "backed up existing $dest -> $dest.bak-$STAMP"
  fi
  if [ "$LINK" = 1 ]; then ln -sfn "$src" "$dest"; say "link $dest"
  else rm -f "$dest"; cp "$src" "$dest"; say "copy $dest"; fi
}

# ── 1. dependencies ───────────────────────────────────────────────────────────
if command -v brew >/dev/null 2>&1; then
  command -v jq >/dev/null 2>&1 || { say "installing jq";  brew install jq; }
  # Symbols-only Nerd Font: supplies the folder/clock/microchip status icons.
  # macOS uses it as an automatic fallback, so no Ghostty font-family change.
  if ! ls "$HOME/Library/Fonts/"SymbolsNerdFont* >/dev/null 2>&1; then
    say "installing font-symbols-only-nerd-font"; brew install --cask font-symbols-only-nerd-font
  fi
else
  warn "Homebrew not found — install 'jq' and a Symbols Nerd Font yourself."
fi

# ── 2. config files ───────────────────────────────────────────────────────────
place "$REPO/ghostty/config"            "$HOME/.config/ghostty/config"
place "$REPO/tmux/tmux.conf"            "$HOME/.tmux.conf"
place "$REPO/claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
place "$REPO/claude/glyph-test.sh"      "$HOME/.claude/glyph-test.sh"
chmod +x "$HOME/.claude/statusline-command.sh" "$HOME/.claude/glyph-test.sh" 2>/dev/null

# ── 3. merge the statusLine block into ~/.claude/settings.json ─────────────────
# Merged, not overwritten, so existing permissions / model / other keys survive.
SET="$HOME/.claude/settings.json"
if command -v jq >/dev/null 2>&1; then
  mkdir -p "$HOME/.claude"
  [ -f "$SET" ] || echo '{}' > "$SET"
  cp "$SET" "$SET.bak-$STAMP"
  if jq -e . "$SET" >/dev/null 2>&1; then
    jq --slurpfile s "$REPO/claude/settings.snippet.json" '. * $s[0]' "$SET" > "$SET.tmp" \
      && mv "$SET.tmp" "$SET" && say "merged statusLine into $SET (backup: $SET.bak-$STAMP)"
  else
    warn "$SET is not valid JSON — add the statusLine block from claude/settings.snippet.json by hand."
  fi
else
  warn "jq missing — add the statusLine block from claude/settings.snippet.json to $SET by hand."
fi

# ── 4. reload what is already running ──────────────────────────────────────────
[ -n "${TMUX:-}" ] && tmux source-file "$HOME/.tmux.conf" 2>/dev/null && say "reloaded tmux"

cat <<'DONE'

Done. Two things the running programs can't pick up on their own:
  • Ghostty  — reload config with Cmd+Shift+, (or restart the app) for the
               Shift+Enter newline key and the Gruvbox Light theme.
  • tmux     — start a fresh window/pane so the extended-keys protocol is
               renegotiated (needed for Shift+Enter inside tmux).

The status line and the right-click pane menu are already live.
DONE
