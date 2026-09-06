#!/usr/bin/env bash
# Fresh-machine setup for the Ghostty + tmux + Claude Code status line described
# in README.md. Idempotent: safe to re-run. Backs up anything it would replace
# to <file>.bak-<timestamp>. Nothing here is destructive without a backup.
#
#   ./install.sh                       apply everything
#   ./install.sh --statusline-only     just the Claude Code status line + settings
#                                      (skip the Ghostty and tmux configs)
#   ./install.sh --theme <name>        set the status line theme (default is
#                                      gruvbox-light). One of: gruvbox-light,
#                                      gruvbox-dark, catppuccin, tokyonight, nord
#   ./install.sh --codex               also show OpenAI Codex CLI's 5h/weekly
#                                      limits (reads ~/.codex; needs Codex)
#   ./install.sh --link                symlink the repo's files instead of
#                                      copying, so a future `git pull` updates
#                                      the live config in place
#
# Flags combine, e.g. ./install.sh --statusline-only --theme nord --codex
#
# macOS-oriented (Homebrew, Ghostty.app). On Linux, install jq + a Nerd Font
# with your package manager and copy the config files by hand; the tmux and
# status line pieces work unchanged.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
LINK=0; STATUSLINE_ONLY=0; THEME=""; CODEX=0
VALID_THEMES="gruvbox-light gruvbox-dark catppuccin tokyonight nord"
say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! \033[0m%s\n' "$*"; }
die()  { printf '\033[1;31m  ✗ \033[0m%s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --link)             LINK=1 ;;
    --statusline-only)  STATUSLINE_ONLY=1 ;;
    --theme)            THEME="${2:-}"; shift ;;
    --theme=*)          THEME="${1#--theme=}" ;;
    --codex)            CODEX=1 ;;
    -h|--help)          sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                  die "unknown option: $1 (try --help)" ;;
  esac
  shift
done
if [ -n "$THEME" ]; then
  case " $VALID_THEMES " in *" $THEME "*) : ;; *) die "unknown theme: $THEME (one of: $VALID_THEMES)";; esac
fi

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
if [ "$STATUSLINE_ONLY" = 0 ]; then
  place "$REPO/ghostty/config"            "$HOME/.config/ghostty/config"
  place "$REPO/tmux/tmux.conf"            "$HOME/.tmux.conf"
else
  say "statusline-only — skipping the Ghostty and tmux configs"
fi
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
    # --statusline-only merges only the statusLine key (leaves your theme alone);
    # a full install also sets theme:"light" so Claude Code's UI text stays
    # legible on the cream background.
    if [ "$STATUSLINE_ONLY" = 1 ]; then
      jq --slurpfile s "$REPO/claude/settings.snippet.json" '.statusLine = $s[0].statusLine' "$SET" > "$SET.tmp"
    else
      jq --slurpfile s "$REPO/claude/settings.snippet.json" '. * $s[0]' "$SET" > "$SET.tmp"
    fi
    mv "$SET.tmp" "$SET" && say "merged statusLine into $SET (backup: $SET.bak-$STAMP)"
    # Bake the chosen options into the command as env prefixes the script reads.
    if [ -n "$THEME" ] || [ "$CODEX" = 1 ]; then
      PREFIX=""
      [ -n "$THEME" ] && PREFIX="STATUSLINE_THEME=$THEME "
      [ "$CODEX" = 1 ] && PREFIX="${PREFIX}STATUSLINE_CODEX=1 "
      jq --arg c "${PREFIX}bash ~/.claude/statusline-command.sh" '.statusLine.command = $c' \
        "$SET" > "$SET.tmp" && mv "$SET.tmp" "$SET"
      [ -n "$THEME" ] && say "status line theme: $THEME"
      [ "$CODEX" = 1 ] && say "codex usage row: on"
    fi
  else
    warn "$SET is not valid JSON — add the statusLine block from claude/settings.snippet.json by hand."
  fi
else
  warn "jq missing — add the statusLine block from claude/settings.snippet.json to $SET by hand."
fi

# ── 4. reload what is already running ──────────────────────────────────────────
[ "$STATUSLINE_ONLY" = 0 ] && [ -n "${TMUX:-}" ] && tmux source-file "$HOME/.tmux.conf" 2>/dev/null && say "reloaded tmux"

if [ "$STATUSLINE_ONLY" = 1 ]; then
  cat <<'DONE'

Done. The status line is live and re-renders on its own — no restart needed.
Change the theme any time by re-running with --theme <name>, or by editing the
statusLine command in ~/.claude/settings.json.
DONE
else
  cat <<'DONE'

Done. Two things the running programs can't pick up on their own:
  • Ghostty  — reload config with Cmd+Shift+, (or restart the app) for the
               Shift+Enter newline key and the Gruvbox Light theme.
  • tmux     — start a fresh window/pane so the extended-keys protocol is
               renegotiated (needed for Shift+Enter inside tmux).

The status line and the right-click pane menu are already live.
DONE
fi
