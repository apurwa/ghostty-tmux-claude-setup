#!/bin/bash
# Claude Code status line, themed for gruvbox light (morhetz/gruvbox).
#
#    ~/full/path/to/cwd › ◇ worktree
#    username › repo › branch* ↑n↓n Δn › PR #n
#    5h ███░░░░░ 43% (2h10m) ↓ › 7d ███████░ 86% (3d5h) ↑ cap ~4h › ctx ██░░░░░░ 31%
#    codex 5h ██████░░ 72% (4h47m) → › 7d █████░░░ 59% (2d6h) ↓   (opt-in, see below)
#    model › effort › thinking › ~$1.23
#
# The ↓ → ↑ after a limit is the burn-rate pace: ↓ under pace, → on pace,
# ↑ over pace with "cap ~<Xh>" — the ETA to 100% if the current rate holds.
#
# The "codex" row is optional (set STATUSLINE_CODEX=1). Codex has no scriptable
# status line, but it logs its own 5h/weekly rate limits to ~/.codex, so this
# reads them and shows both agents' usage in one place. See codex_usage() below.
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

# ── palette: one calm colour + alarm-only heat, themeable ─────────────────────
# The whole line is a single calm colour (gruvbox-light's faded maroon by
# default) EXCEPT the heat tones, used ONLY by the 5h/7d/ctx percentages, the bar
# fill, and the over-pace ↑. Everything else — the dirty *, the ↑↓ track, PR
# states — stays the calm colour, so the line reads flat almost always and only
# lights up when a metric runs hot:
#   <60%  calm  → HEAT_CALM  = the calm colour (no visible change)
#   60-79 warn  → HEAT_WARN  = the theme's amber/yellow
#   >=80  alarm → HEAT_ALARM = the theme's bright red
#
# Pick a palette with STATUSLINE_THEME (default gruvbox-light). Each theme is four
# colours as "R;G;B": the calm primary (every glyph until a metric runs hot), the
# warn and alarm heat tones, and the empty-bar track. Light themes carry a
# coloured primary (the signature look); dark themes use the theme's foreground as
# the calm colour with yellow→red heat, which is what those palettes expect. Add a
# theme by adding a case; to go fully flat, set warn/alarm equal to the primary.
case "${STATUSLINE_THEME:-gruvbox-light}" in
  gruvbox-dark) c_text='235;219;178'; c_warn='250;189;47';  c_alarm='251;73;52';  c_empty='102;92;84'   ;; # bg #282828
  catppuccin)   c_text='205;214;244'; c_warn='249;226;175'; c_alarm='243;139;168'; c_empty='69;71;90'   ;; # mocha, bg #1e1e2e
  tokyonight)   c_text='192;202;245'; c_warn='224;175;104'; c_alarm='247;118;142'; c_empty='65;72;104'  ;; # night, bg #1a1b26
  nord)         c_text='216;222;233'; c_warn='235;203;139'; c_alarm='191;97;106';  c_empty='76;86;106'  ;; # bg #2e3440
  gruvbox-light|*) c_text='157;0;6'; c_warn='181;118;20'; c_alarm='204;36;29';   c_empty='226;169;173' ;; # bg #fbf1c7 (default)
esac
#
# Careful with the comments below: `VAR=$'...'# text` with no space folds the
# '#' into the value and prints a stray '#' in the status line.
R=$'\033[0m'
# SGR 1 (bold) plus the colour, in one sequence. Bold also helps the text hold
# up against the dimming Claude Code applies to the status line. $'...' does not
# expand variables, so each colour is the ANSI-C-quoted prefix concatenated with
# the expanded "R;G;B" and a literal 'm'.
TEXT=$'\033[1;38;2;'"$c_text"'m'   # calm — every glyph of text
D="$TEXT"                        # separators, countdowns
GREY="$TEXT"                     # labels: 5h / 7d / ctx / model
MAROON="$TEXT"                   # primary identity
MAROON_LT="$TEXT"                # secondary — subdir, branch
MAROON_DK="$TEXT"                # bullets, worktree
GREEN="$TEXT"                    # ahead ↑, PR approved — kept calm (flat)
YELLOW="$TEXT"                   # dirty *, PR pending — kept calm (flat)
RED="$TEXT"                      # behind ↓, PR changes-requested — kept calm (flat)
# Heat has its own colours so ONLY the climbing metrics (5h/7d/ctx % and the bar)
# and the over-pace ↑ ever leave the calm colour; the dirty *, ↑↓ track and PR
# states above stay calm. calm <60 / warn 60-79 / alarm >=80.
HEAT_CALM="$TEXT"                        # <60% — the calm colour, no visible change
HEAT_WARN=$'\033[1;38;2;'"$c_warn"'m'    # 60-79% — theme amber/yellow
HEAT_ALARM=$'\033[1;38;2;'"$c_alarm"'m'  # >=80% — theme bright red
BLUE="$TEXT"                     # cost
# Not text — the empty track of the bar. A muted theme tint so the bar still
# reads as a bar; at the primary colour it would be a solid indistinct block.
BAR_EMPTY=$'\033[38;2;'"$c_empty"'m'
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
ICON_PR=$(printf '\357\220\207')        # U+F407  nf-oct-git-pull-request

# Heat on the maroon ramp: light under 50%, mid under 80%, deepest above.
heat() { local p=${1%%.*}; if [ "${p:-0}" -lt 60 ]; then printf '%s' "$HEAT_CALM"
       elif [ "${p:-0}" -lt 80 ]; then printf '%s' "$HEAT_WARN"
       else printf '%s' "$HEAT_ALARM"; fi; }

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

# Burn-rate pace for a rolling window. Projects the current spend rate to the
# window's end and warns when you're on track to hit the cap before it resets:
# ↓ under pace, → on pace, ↑ over pace with "cap ~<Xh>" (the ETA to 100%). It
# stays silent until enough of the window has elapsed for the projection to mean
# anything — an early burst shouldn't scream. Args: used%, resets_at epoch,
# window length in seconds (5h=18000, 7d=604800).
pace() {
  local used=$1 reset=$2 window=$3 u now elapsed projected eta
  case "$reset" in ''|*[!0-9]*) return ;; esac
  u=${used%%.*}
  case "$u" in ''|*[!0-9]*) return ;; esac
  [ "$u" -le 0 ] && return                          # nothing spent yet
  now=$(date +%s)
  elapsed=$(( now - (reset - window) ))
  [ "$elapsed" -le 0 ] && return                    # window not started / clock skew
  [ $(( reset - now )) -le 0 ] && return            # already reset
  [ "$elapsed" -lt $(( window / 10 )) ] && return   # too early to extrapolate
  projected=$(( u * window / elapsed ))             # final % if the rate holds
  if [ "$projected" -ge 110 ]; then
    eta=$(( elapsed * (100 - u) / u ))              # seconds until 100%
    printf ' %s↑ cap ~%s%s' "$HEAT_ALARM" "$(countdown $(( now + eta )))" "$R"
  elif [ "$projected" -ge 90 ]; then
    printf ' %s→%s' "$D" "$R"
  else
    printf ' %s↓%s' "$BAR_EMPTY" "$R"
  fi
}

# Count of your own open PRs in this repo, via gh. gh hits the network and the
# status line re-renders often, so this NEVER blocks on it: it prints whatever
# the cache holds and, when that is stale (>60s) or missing, refreshes it in a
# background subshell whose result the next render picks up. A cold cache shows
# nothing for one render. Prints nothing when gh is absent/unauthed, there is no
# origin remote, or the count is zero — so the caller simply omits the segment.
pr_open() {
  local dir=$1 remote key cache now age n
  command -v gh >/dev/null 2>&1 || return
  remote=$(git -C "$dir" remote get-url origin 2>/dev/null)
  [ -n "$remote" ] || return
  key=$(printf '%s' "$remote" | md5 -q 2>/dev/null \
        || printf '%s' "$remote" | md5sum 2>/dev/null | awk '{print $1}')
  cache="$HOME/.claude/cache/statusline/pr-${key:-x}"
  mkdir -p "$(dirname "$cache")" 2>/dev/null || return
  now=$(date +%s); age=99999
  [ -f "$cache" ] && age=$(( now - $(stat -f%m "$cache" 2>/dev/null || echo 0) ))
  if [ "$age" -ge 60 ]; then
    ( cd "$dir" 2>/dev/null && gh pr list --author @me --state open \
        --json number --jq 'length' 2>/dev/null > "$cache.tmp" \
        && mv "$cache.tmp" "$cache" ) &
  fi
  n=$(cat "$cache" 2>/dev/null)
  case "$n" in ''|*[!0-9]*) return ;; esac
  [ "$n" -gt 0 ] || return
  printf '%s' "$n"
}

# Codex (OpenAI) usage, shown alongside Claude's when STATUSLINE_CODEX is set.
# Codex has no scriptable status line of its own, but it records rate limits into
# its session rollouts (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl) on every
# turn, in token_count events: payload.rate_limits.primary is the 5-hour window
# (window_minutes 300) and .secondary is the weekly one (10080), each with the
# same used_percent + resets_at(epoch) shape as Claude's rate_limits — so bar(),
# heat(), countdown() and pace() all apply unchanged. Like pr_open this NEVER
# blocks: it prints from a cache and refreshes in the background by reading the
# most recent rollout that carries a rate_limits record. The figure reflects your
# LAST Codex turn, so it can lag if you haven't run Codex recently; the reset
# countdown still shows where the window stands. Prints raw "p5 r5 p7 r7" to the
# cache; formatting happens per-render so the countdown/pace stay live.
codex_usage() {
  case "${STATUSLINE_CODEX:-}" in ''|0|no|off|false) return ;; esac
  [ -d "$HOME/.codex/sessions" ] || return
  command -v jq >/dev/null 2>&1 || return
  local cache="$HOME/.claude/cache/statusline/codex-usage" now age p5 r5 p7 r7 seg
  mkdir -p "$(dirname "$cache")" 2>/dev/null || return
  now=$(date +%s); age=99999
  [ -f "$cache" ] && age=$(( now - $(stat -f%m "$cache" 2>/dev/null || echo 0) ))
  if [ "$age" -ge 45 ]; then
    ( cand=""
      # newest rollout (by mtime) that actually carries a rate_limits record;
      # find+stat avoids an ls glob blowing up on a large session history.
      for f in $(find "$HOME/.codex/sessions" -type f -name 'rollout-*.jsonl' \
                   -exec stat -f '%m %N' {} + 2>/dev/null | sort -rn | head -8 | cut -d' ' -f2-); do
        grep -q '"rate_limits":{' "$f" 2>/dev/null && { cand="$f"; break; }
      done
      [ -n "$cand" ] || exit 0
      line=$(grep '"rate_limits":{' "$cand" 2>/dev/null | tail -1)
      [ -n "$line" ] || exit 0
      printf '%s' "$line" | jq -r '.payload.rate_limits
        | "\(.primary.used_percent // "") \(.primary.resets_at // "") \(.secondary.used_percent // "") \(.secondary.resets_at // "")"' \
        2>/dev/null > "$cache.tmp" && mv "$cache.tmp" "$cache" ) &
  fi
  read -r p5 r5 p7 r7 < "$cache" 2>/dev/null || return
  case "$p5" in ''|*[!0-9.]*) return ;; esac
  seg="${GREY}5h ${R}$(bar "$p5") $(heat "$p5")$(printf '%.0f' "$p5")%${R}"
  [ -n "$r5" ] && seg+="${D} ($(countdown "$r5"))${R}$(pace "$p5" "$r5" 18000)"
  if [ -n "$p7" ]; then
    seg+="$SEP${GREY}7d ${R}$(bar "$p7") $(heat "$p7")$(printf '%.0f' "$p7")%${R}"
    [ -n "$r7" ] && seg+="${D} ($(countdown "$r7"))${R}$(pace "$p7" "$r7" 604800)"
  fi
  printf '%s' "$seg"
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

# Each row is appended to this array and emitted at the end with a blank line
# between rows (see "Emit"). Collecting first keeps the spacing correct no
# matter which rows are present — a skipped row never leaves a double gap.
rows=()

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
  rows+=("$line1")
fi

# ── Line 2:  username › repo › branch › PR ───────────────────────────────────
branch="$wt_branch"
[ -z "$branch" ] && branch=$(git -C "$current_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

# The payload's .workspace.repo is only present sometimes; when it is missing,
# parse owner (username) and repo name out of the origin remote so the GitHub
# identity always shows. Handles both git@host:owner/name.git and
# https://host/owner/name.git — strip .git, take the last two path components.
if [ -z "$repo_name" ]; then
  ru=$(git -C "$current_dir" remote get-url origin 2>/dev/null)
  if [ -n "$ru" ]; then
    ru=${ru%.git}; rn=${ru##*/}; rr=${ru%/*}; ro=${rr##*[:/]}
    [ -n "$rn" ] && [ -n "$ro" ] && [ "$rn" != "$ro" ] && { repo_name=$rn; repo_owner=$ro; }
  fi
fi

if [ -n "$branch" ] || [ -n "$repo_name" ]; then
  line2=""
  if [ -n "$repo_name" ]; then
    # username › repo, as two separate segments (not owner/repo).
    line2="${MAROON}${ICON_REPO} ${R}"
    [ -n "$repo_owner" ] && line2+="${GREY}${repo_owner}${R}${SEP}"
    line2+="${MAROON}${repo_name}${R}"
    # Your open PRs in this repo, appended to the repo identity as "⑂ n".
    pr_n=$(pr_open "$current_dir")
    [ -n "$pr_n" ] && line2+=" ${MAROON}${ICON_PR} ${pr_n}${R}"
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
  rows+=("$line2")
fi

# ── Line 3: ▪ 5h (bar) › 7d (bar) › ctx (bar) ─────────────────────────────────
# All three usage metrics get a bar so the line reads as one scannable set — the
# eye compares fill levels at a glance instead of translating one bare number
# against two bars. The 7d window moves slowly, but a bar is exactly what a slow
# number lacks: an at-a-glance "how full is the tank", and 7d is the limit that
# hurts most when it binds (locked out for days, not hours). Each keeps its reset
# countdown and burn-rate pace.
line3=""
if [ -n "$five_pct" ]; then
  line3+="${GREY}5h ${R}$(bar "$five_pct") $(heat "$five_pct")$(printf '%.0f' "$five_pct")%${R}"
  [ -n "$five_reset" ] && line3+="${D} ($(countdown "$five_reset"))${R}$(pace "$five_pct" "$five_reset" 18000)"
fi
if [ -n "$seven_pct" ]; then
  [ -n "$line3" ] && line3+="$SEP"
  line3+="${GREY}7d ${R}$(bar "$seven_pct") $(heat "$seven_pct")$(printf '%.0f' "$seven_pct")%${R}"
  [ -n "$seven_reset" ] && line3+="${D} ($(countdown "$seven_reset"))${R}$(pace "$seven_pct" "$seven_reset" 604800)"
fi
if [ -n "$ctx_pct" ]; then
  [ -n "$line3" ] && line3+="$SEP"
  # "ctx" label, bar, then the exact figure. The bar is 8 cells and so resolves
  # only to ~12% steps; the number carries the precision.
  c=$(heat "$ctx_pct")
  line3+="${GREY}ctx ${R}$(bar "$ctx_pct") ${c}$(printf '%.0f' "$ctx_pct")%${R}"
fi
[ -n "$line3" ] && rows+=("${MAROON_DK}${ICON_LIMITS} ${R}${line3}")

# Optional Codex usage row, directly under Claude's, labelled so the two agents
# are unmistakable. Off unless STATUSLINE_CODEX is set. See codex_usage() above.
cx=$(codex_usage)
[ -n "$cx" ] && rows+=("${MAROON_DK}${ICON_LIMITS} ${R}${GREY}codex ${R}${cx}")

# ── Line 4: ▫ model › effort › thinking › cost ────────────────────────────────
cost=$(session_cost "$transcript" "$session_id")
if [ -n "$model" ] || [ -n "$effort" ] || [ -n "$cost" ]; then
  line4="${MAROON_DK}${ICON_SESSION} ${R}${GREY}${model}${R}"
  [ -n "$effort" ]   && line4+="${SEP}${GREY}${effort}${R}"
  [ -n "$thinking" ] && line4+="${SEP}${MAROON_DK}${thinking}${R}"
  [ -n "$style" ] && [ "$style" != "default" ] && line4+="${SEP}${GREY}${style}${R}"
  # "~" because this is derived from transcript usage, not billed figures.
  [ -n "$cost" ] && line4+="${SEP}${BLUE}~\$${cost}${R}"
  rows+=("$line4")
fi

# ── Emit: one row per line, no blank spacers ──────────────────────────────────
# Each populated row on its own line — four lines, not seven. The earlier version
# put a blank line between rows for vertical spacing, but blank rows count against
# the status line's visible height, so the lower rows (usage, session) got pushed
# off and never showed. Compact output keeps all four rows visible; if a row is
# skipped it simply leaves no gap.
for row in "${rows[@]}"; do
  printf '%s\n' "$row"
done
