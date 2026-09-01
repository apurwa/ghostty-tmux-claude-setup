#!/bin/bash
# Claude Code status line, themed for gruvbox light (morhetz/gruvbox).
#
#    ~/full/path/to/cwd › ◇ worktree
#    owner/repo › branch* ↑n↓n › PR #n
#    5h 43% (2h10m) › 7d 86% (3d5h) › ██░░░░░░ 31%
#    model › effort › thinking › ~$1.23
#
# Field names come from the payload schema documented inside the Claude Code
# binary (v2.1.236). Note there is no daily or monthly limit in the payload —
# Anthropic's windows are rolling 5-hour and 7-day, exposed as
# .rate_limits.five_hour and .rate_limits.seven_day. Cost is not in the payload
# at all; it is derived from the transcript (see session_cost below).
#
# The three leading icons are Nerd Font glyphs, defined near BAR_W below. They
# are ordinary font characters rather than emoji, which is what lets them take
# the maroon ANSI colour and stay one column wide. Emoji cannot do either: the
# system colour-emoji font ignores ANSI colour and renders two columns wide.
#
# The remaining glyphs (◇ █ ░) are single-width, from Geometric Shapes and
# Block Elements, which monospace fonts cover reliably. Avoid symbols like
# ⟳ (U+27F3) and ⑂ (U+2442): the font lacks them, the terminal substitutes a
# wider glyph, and following text overlaps. Use glyph-test.sh to check a new one.

input=$(cat)

# One jq pass; the status line re-renders often, so avoid a call per field.
# jq emits shell assignments and @sh does the quoting. A tab-separated read
# would be wrong here: tab is an IFS whitespace character, so bash collapses
# runs of empty fields and every later value shifts left.
eval "$(printf '%s' "$input" | jq -r '
  @sh "project_dir=\(.workspace.project_dir // "")",
  @sh "current_dir=\(.workspace.current_dir // "")",
  @sh "wt_name=\(.worktree.name // .workspace.git_worktree // "")",
  @sh "repo_owner=\(.workspace.repo.owner // "")",
  @sh "repo_name=\(.workspace.repo.name // "")",
  @sh "five_pct=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "five_reset=\(.rate_limits.five_hour.resets_at // "")",
  @sh "seven_pct=\(.rate_limits.seven_day.used_percentage // "")",
  @sh "seven_reset=\(.rate_limits.seven_day.resets_at // "")",
  @sh "ctx_pct=\(.context_window.used_percentage // "")",
  @sh "model=\(.model.display_name // "")",
  @sh "effort=\(.effort.level // "")",
  @sh "thinking=\(if .thinking.enabled then "thinking" else "" end)",
  @sh "style=\(.output_style.name // "")",
  @sh "pr_num=\(.pr.number // "")",
  @sh "pr_state=\(.pr.review_state // "")",
  @sh "wt_branch=\(.worktree.branch // "")",
  @sh "session_id=\(.session_id // "")",
  @sh "transcript=\(.transcript_path // "")"
' 2>/dev/null)"

# ── flat maroon palette on the gruvbox light background (#fbf1c7) ─────────────
# Every piece of text is #9d0006 — gruvbox's faded red. The names below are kept
# so the rest of the script needs no changes; they all now point at one colour.
#
# Consequence worth knowing: the heat signal is gone from the text. 5h/7d/ctx
# percentages no longer change colour as they climb, so the numbers themselves
# are the only warning. The progress bar still shows load by how full it is.
# To bring heat back, give GREEN/YELLOW/RED distinct values again — they are
# already wired to the <50 / <80 / >=80 thresholds in heat().
#
# Careful with the comments below: `VAR=$'...'# text` with no space folds the
# '#' into the value and prints a stray '#' in the status line.
R=$'\033[0m'
# SGR 1 (bold) plus the colour, in one sequence. Bold also helps the text hold
# up against the dimming Claude Code applies to the status line.
TEXT=$'\033[1;38;2;157;0;6m'     # #9d0006 bold — every glyph of text
D="$TEXT"                        # separators, countdowns
GREY="$TEXT"                     # labels: 5h / 7d / ctx / model
MAROON="$TEXT"                   # primary identity
MAROON_LT="$TEXT"                # secondary — subdir, branch
MAROON_DK="$TEXT"                # bullets, worktree
GREEN="$TEXT"                    # heat: low
YELLOW="$TEXT"                   # heat: mid
RED="$TEXT"                      # heat: high
BLUE="$TEXT"                     # cost
# Not text — the empty track of the bar. Kept as a light tint of the same hue so
# the bar still reads as a bar; at #9d0006 it would be a solid indistinct block.
BAR_EMPTY=$'\033[38;2;226;169;173m' # #e2a9ad
SEP="${D} › ${R}"

BAR_W=8

# Nerd Font icons, supplied by Symbols Nerd Font Mono:
#   brew install --cask font-symbols-only-nerd-font
# macOS resolves it automatically as a fallback for codepoints the text font
# lacks, so Ghostty needs no font-family change.
#
# These are written as octal escapes on purpose. The glyphs live in the Unicode
# private use area (U+E000–U+F8FF), and PUA characters are routinely stripped or
# mangled when a file passes through editors, clipboards, and tooling — pasting
# them literally silently leaves behind an empty string. The escapes are plain
# ASCII in the file and expand to the right bytes at runtime.
ICON_PROJECT=$(printf '\357\201\273')   # U+F07B  nf-fa-folder
ICON_REPO=$(printf '\357\202\233')      # U+F09B  nf-fa-github (the cat logo)
ICON_LIMITS=$(printf '\357\200\227')    # U+F017  nf-fa-clock-o
ICON_SESSION=$(printf '\357\213\233')   # U+F2DB  nf-fa-microchip

# Heat on the maroon ramp: light under 50%, mid under 80%, deepest above.
heat() { local p=${1%%.*}; if [ "${p:-0}" -lt 50 ]; then printf '%s' "$GREEN"
       elif [ "${p:-0}" -lt 80 ]; then printf '%s' "$YELLOW"
       else printf '%s' "$RED"; fi; }

# Percentage -> "███░░░░░". Filled cells round to nearest, and a non-zero
# percentage always shows at least one cell so "in use" never reads as empty.
# The two halves are coloured separately — filled in the heat colour, unfilled
# in a pale tint. Painting the whole bar one colour makes the trough read as a
# solid block on a light background instead of as an empty track.
bar() {
  local p=${1%%.*} w=$BAR_W i filled full='' empty=''
  [ -z "$p" ] && p=0
  [ "$p" -gt 100 ] && p=100
  filled=$(( (p * w + 50) / 100 ))
  [ "$filled" -eq 0 ] && [ "$p" -gt 0 ] && filled=1
  for (( i = 0; i < w; i++ )); do
    if [ "$i" -lt "$filled" ]; then full+='█'; else empty+='░'; fi
  done
  printf '%s%s%s%s%s' "$(heat "$p")" "$full" "$BAR_EMPTY" "$empty" "$R"
}

# The default branch's ref, for "commits on this branch vs the default branch".
# origin/HEAD is the correct source but isn't always set locally (e.g. after a
# plain `gh repo create --push`), so fall back through the usual names. Prints
# nothing when none resolve, which makes the caller omit the indicator.
default_base() {
  local dir=$1 b c
  b=$(git -C "$dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
    && { printf '%s' "$b"; return; }
  for c in origin/main origin/master main master; do
    git -C "$dir" rev-parse --verify --quiet "$c" >/dev/null 2>&1 && { printf '%s' "$c"; return; }
  done
}

# Unix epoch -> compact "2h14m" / "3d4h" countdown.
countdown() {
  local d=$(( $1 - $(date +%s) ))
  [ "$d" -le 0 ] && { printf 'now'; return; }
  if   [ "$d" -ge 86400 ]; then printf '%dd%dh' $((d/86400)) $(((d%86400)/3600))
  elif [ "$d" -ge 3600 ];  then printf '%dh%dm' $((d/3600))  $(((d%3600)/60))
  else printf '%dm' $((d/60)); fi
}

# Session cost. Claude Code does not put cost in the status line payload, so it
# is summed from the transcript's per-response usage records and priced with the
# table below. Cache tiers are billed differently and the transcript breaks them
# out (ephemeral_5m vs ephemeral_1h), so they are priced separately rather than
# lumped together. Treat the number as an estimate: update RATES on price
# changes, and note that a resumed session bills only what this transcript holds.
#
# Rates are USD per million tokens. Cache multipliers are Anthropic's standard
# ones: read 0.1x input, 5-minute write 1.25x, 1-hour write 2x.
session_cost() {
  local tp=$1 sid=$2
  [ -n "$tp" ] && [ -f "$tp" ] || return
  local cdir="$HOME/.claude/cache/statusline" cf size now csize ctime ccost cost
  mkdir -p "$cdir" 2>/dev/null || return
  cf="$cdir/cost-${sid:-unknown}"
  size=$(stat -f%z "$tp" 2>/dev/null) || return
  now=$(date +%s)
  # Reuse the cached figure when the transcript has not grown, and re-derive at
  # most every 15s otherwise, so a long transcript never stalls a render.
  if [ -f "$cf" ]; then
    read -r csize ctime ccost < "$cf" 2>/dev/null
    if [ "$size" = "$csize" ] || [ $(( now - ${ctime:-0} )) -lt 15 ]; then
      printf '%s' "$ccost"; return
    fi
  fi
  cost=$(jq -r 'select(.message.usage) | [
      (.message.model // ""),
      (.message.usage.input_tokens // 0),
      (.message.usage.cache_read_input_tokens // 0),
      (.message.usage.cache_creation.ephemeral_5m_input_tokens // 0),
      (.message.usage.cache_creation.ephemeral_1h_input_tokens // 0),
      (.message.usage.output_tokens // 0),
      (.message.usage.cache_creation_input_tokens // 0)
    ] | @tsv' "$tp" 2>/dev/null | awk -F'\t' '
      function rin(m)  { if (m ~ /haiku/) return 1; if (m ~ /sonnet/) return 3;
                         if (m ~ /fable|mythos/) return 10; return 5 }
      function rout(m) { if (m ~ /haiku/) return 5; if (m ~ /sonnet/) return 15;
                         if (m ~ /fable|mythos/) return 50; return 25 }
      {
        i = rin($1); o = rout($1); w5 = $4; w1 = $5
        # Older records lack the per-tier split; fall back to the 5m rate.
        if (w5 + w1 == 0) { w5 = $7 }
        t += ($2*i + $3*i*0.1 + w5*i*1.25 + w1*i*2 + $6*o) / 1000000
      }
      END { printf "%.2f", t + 0 }')
  [ -z "$cost" ] && return
  printf '%s %s %s\n' "$size" "$now" "$cost" > "$cf" 2>/dev/null
  printf '%s' "$cost"
}

# ── Line 1: ◆ full-working-directory-path › ◇ worktree ────────────────────────
# The full absolute path of the current directory, with ~ standing in for $HOME.
cwd_disp="${current_dir:-$project_dir}"
case "$cwd_disp" in
  "$HOME")   cwd_disp="~" ;;
  "$HOME"/*) cwd_disp="~${cwd_disp#"$HOME"}" ;;
esac
if [ -n "$cwd_disp" ] || [ -n "$wt_name" ]; then
  line1=""
  [ -n "$cwd_disp" ] && line1="${MAROON}${ICON_PROJECT} ${cwd_disp}${R}"
  [ -n "$wt_name" ] && line1+="${SEP}${MAROON_DK}◇ ${wt_name}${R}"
  printf '%s\n' "$line1"
fi

# ── Line 2:  repo › branch › PR ──────────────────────────────────────────────
branch="$wt_branch"
[ -z "$branch" ] && branch=$(git -C "$current_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -n "$branch" ] || [ -n "$repo_name" ]; then
  line2=""
  if [ -n "$repo_name" ]; then
    line2="${MAROON}${ICON_REPO} ${R}${GREY}${repo_owner}/${R}${MAROON}${repo_name}${R}"
  fi
  if [ -n "$branch" ]; then
    dirty=""
    [ -n "$(git -C "$current_dir" status --porcelain 2>/dev/null | head -1)" ] && dirty="${YELLOW}*${R}"
    # Ahead/behind the upstream (the remote tracking branch), when configured.
    track=""
    if ab=$(git -C "$current_dir" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null); then
      behind=${ab%%	*}; ahead=${ab##*	}
      [ "$ahead"  -gt 0 ] 2>/dev/null && track+=" ${GREEN}↑${ahead}${R}"
      [ "$behind" -gt 0 ] 2>/dev/null && track+=" ${RED}↓${behind}${R}"
    fi
    # Δn: commits on this branch not in the DEFAULT branch — the size of the
    # branch's changes, distinct from ↑↓ above (which is vs the upstream). Zero
    # (e.g. when sitting on the default branch itself) is omitted.
    base=$(default_base "$current_dir")
    if [ -n "$base" ] && vs=$(git -C "$current_dir" rev-list --count "$base..HEAD" 2>/dev/null); then
      [ "${vs:-0}" -gt 0 ] 2>/dev/null && track+=" ${MAROON}Δ${vs}${R}"
    fi
    # Lead with the GitHub icon only when no repo segment already carries it.
    if [ -n "$line2" ]; then line2+="$SEP"; else line2="${MAROON}${ICON_REPO} ${R}"; fi
    line2+="${MAROON_LT}${branch}${R}${dirty}${track}"
  fi
  if [ -n "$pr_num" ]; then
    case "$pr_state" in
      approved)          pr_col="$GREEN" ;;
      changes_requested) pr_col="$RED" ;;
      draft)             pr_col="$GREY" ;;
      *)                 pr_col="$YELLOW" ;;
    esac
    line2+="${SEP}${pr_col}PR #${pr_num}${R}"
    [ -n "$pr_state" ] && line2+="${D} ${pr_state}${R}"
  fi
  printf '%s\n' "$line2"
fi

# ── Line 3: ▪ limits (plain %) › context (bar) ────────────────────────────────
# Only the context window gets a bar. The 5h/7d windows move slowly and a
# percentage plus a reset countdown says everything a bar would.
line3=""
if [ -n "$five_pct" ]; then
  line3+="${GREY}5h ${R}$(heat "$five_pct")$(printf '%.0f' "$five_pct")%${R}"
  [ -n "$five_reset" ] && line3+="${D} ($(countdown "$five_reset"))${R}"
fi
if [ -n "$seven_pct" ]; then
  [ -n "$line3" ] && line3+="$SEP"
  line3+="${GREY}7d ${R}$(heat "$seven_pct")$(printf '%.0f' "$seven_pct")%${R}"
  [ -n "$seven_reset" ] && line3+="${D} ($(countdown "$seven_reset"))${R}"
fi
if [ -n "$ctx_pct" ]; then
  [ -n "$line3" ] && line3+="$SEP"
  # Bar plus the exact figure, no "ctx" label. The bar is 8 cells and so
  # resolves only to ~12% steps; the number carries the precision.
  c=$(heat "$ctx_pct")
  line3+="$(bar "$ctx_pct") ${c}$(printf '%.0f' "$ctx_pct")%${R}"
fi
[ -n "$line3" ] && printf '%s\n' "${MAROON_DK}${ICON_LIMITS} ${R}${line3}"

# ── Line 4: ▫ model › effort › thinking › cost ────────────────────────────────
cost=$(session_cost "$transcript" "$session_id")
if [ -n "$model" ] || [ -n "$effort" ] || [ -n "$cost" ]; then
  line4="${MAROON_DK}${ICON_SESSION} ${R}${GREY}${model}${R}"
  [ -n "$effort" ]   && line4+="${SEP}${GREY}${effort}${R}"
  [ -n "$thinking" ] && line4+="${SEP}${MAROON_DK}${thinking}${R}"
  [ -n "$style" ] && [ "$style" != "default" ] && line4+="${SEP}${GREY}${style}${R}"
  # "~" because this is derived from transcript usage, not billed figures.
  [ -n "$cost" ] && line4+="${SEP}${BLUE}~\$${cost}${R}"
  printf '%s\n' "$line4"
fi
