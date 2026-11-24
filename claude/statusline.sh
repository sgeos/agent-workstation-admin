#!/usr/bin/env bash
# Claude Code status line: context-window fill, account usage, model, dir, branch.
#
# Segments, left to right:
#   - a 10-segment bar plus the context-window fill percentage (proximity to
#     automatic compaction),
#   - 5h and 7d account-usage percentages, the proximity to the rolling
#     rate-limit caps. The 7-day window is usually the binding one under heavy
#     agent use.
#   - the model and its thinking level, the working directory, and the git
#     branch.
# Each percentage is coloured green under 70, yellow 70-89, red 90+. The numbers
# are always printed, so the reading never depends on colour (daltonized-safe).
#
# Reads the status JSON that Claude Code passes on stdin. Needs jq. Install by
# copying to ~/.claude/statusline.sh and adding to ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
#
# Trust boundary: the optional per-project segment below runs an executable
# from the session's working directory on every render, so opening a session
# in an untrusted checkout runs that checkout's script. Set
# STATUSLINE_PROJECT_SEGMENT=0 in the environment to turn it off.

input=$(cat)

jq_get() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

pct=$(jq_get '
  ( .context_window.used_percentage
  // .contextWindow.usedPercentage
  // ( if (.context_window.used_tokens and .context_window.context_window_size)
       then (.context_window.used_tokens / .context_window.context_window_size * 100)
       else empty end )
  // empty )
')
five=$(jq_get '.rate_limits.five_hour.used_percentage // empty')
seven=$(jq_get '.rate_limits.seven_day.used_percentage // empty')
model=$(jq_get '.model.display_name // .model.id // "Claude"')
# Thinking level, shown after the model. The payload carries it as
# `.effort.level` (low, medium, high, xhigh, max) and whether thinking is on as
# `.thinking.enabled`, as observed in Claude Code 2.1.323. Either may be absent
# in other versions, in which case the segment is omitted rather than guessed.
effort=$(jq_get '.effort.level // empty')
thinking=$(jq_get 'if .thinking.enabled == false then "off" else empty end')
dir=$(jq_get '.workspace.current_dir // .cwd // empty')
base=""; [ -n "$dir" ] && base=$(basename "$dir")

branch=""
if [ -n "$dir" ] && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
fi

RESET=$'\033[0m'; DIM=$'\033[2m'
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'

# Colour code for an integer percentage.
color_for() {
  if   [ "$1" -ge 90 ] 2>/dev/null; then printf '%s' "$RED"
  elif [ "$1" -ge 70 ] 2>/dev/null; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

# Context bar + percentage.
if [ -n "$pct" ]; then
  p=$(printf '%.0f' "$pct" 2>/dev/null); [ -z "$p" ] && p=0
  filled=$(( (p + 5) / 10 )); [ "$filled" -gt 10 ] && filled=10; [ "$filled" -lt 0 ] && filled=0
  bar=""; i=0
  while [ "$i" -lt 10 ]; do
    if [ "$i" -lt "$filled" ]; then bar="${bar}▰"; else bar="${bar}▱"; fi
    i=$((i + 1))
  done
  ctx="$(color_for "$p")${bar} ${p}%${RESET}"
else
  ctx="${DIM}ctx ?%${RESET}"
fi

# Account-usage segments (omitted if absent from the payload).
sep="${DIM}·${RESET}"
rl=""
if [ -n "$five" ]; then
  f=$(printf '%.0f' "$five" 2>/dev/null); [ -z "$f" ] && f=0
  rl="$rl ${sep} $(color_for "$f")5h ${f}%${RESET}"
fi
if [ -n "$seven" ]; then
  s=$(printf '%.0f' "$seven" 2>/dev/null); [ -z "$s" ] && s=0
  rl="$rl ${sep} $(color_for "$s")7d ${s}%${RESET}"
fi

# --- Optional PER-PROJECT segment -------------------------------------------
#
# A project may provide an executable `scripts/statusline-segment.sh`. If it
# exists, its single line of stdout is appended here. That keeps
# project-specific state, such as a long-running build, a gate or a deploy, out
# of this global script, and version-controls the logic alongside the project it
# describes. A project without the file contributes nothing.
#
# THE CONTRACT IS DELIBERATELY DEFENSIVE, because this runs on every render and
# a project-side bug must never break or hang the status line:
#   - hard timeout, so a slow script degrades to silence rather than a stall;
#   - stderr discarded and a non-zero exit ignored;
#   - newlines stripped and the result truncated, so a runaway script cannot
#     wrap the line or inject control sequences beyond its own colours.
#
# `scripts/` rather than `.claude/`, because `.claude/` is commonly gitignored
# and an integration point that is not version-controlled is one that silently
# differs between machines.
seg_extra=""
if [ "${STATUSLINE_PROJECT_SEGMENT:-1}" != 0 ] && [ -n "$dir" ] &&
  [ -x "$dir/scripts/statusline-segment.sh" ]; then
  if   command -v timeout  >/dev/null 2>&1; then _to="timeout 1"
  elif command -v gtimeout >/dev/null 2>&1; then _to="gtimeout 1"
  else _to=""; fi
  seg_extra=$($_to "$dir/scripts/statusline-segment.sh" 2>/dev/null | tr -d '\n\r' | cut -c1-80)
fi

line="${ctx}${rl}"
[ -n "$model" ]  && line="$line ${sep} ${model}"
if [ "$thinking" = "off" ]; then line="$line ${DIM}thinking off${RESET}"
elif [ -n "$effort" ]; then line="$line ${DIM}${effort}${RESET}"; fi
[ -n "$base" ]   && line="$line ${sep} ${CYAN}${base}${RESET}"
[ -n "$branch" ] && line="$line ${DIM}(${branch})${RESET}"
[ -n "$seg_extra" ] && line="$line ${sep} ${seg_extra}"

printf '%s' "$line"
