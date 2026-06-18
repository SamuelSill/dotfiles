#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

# ANSI-C quoting so the variables hold real escape bytes; this works whether
# or not the shell's `echo` interprets backslash escapes (it doesn't on Linux).
CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'

# Pick bar color based on context usage
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

# Build the bar by repeating the glyphs directly. `tr` operates on bytes, so it
# mangles multibyte UTF-8 chars (█/░) on GNU coreutils; a loop is portable.
FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
BAR=""
for ((i = 0; i < FILLED; i++)); do BAR="${BAR}█"; done
for ((i = 0; i < EMPTY; i++)); do BAR="${BAR}░"; done

MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))

BRANCH=""
git rev-parse --git-dir > /dev/null 2>&1 && BRANCH=" | $(git branch --show-current 2>/dev/null)"

echo "${CYAN}[$MODEL]${RESET} ${DIR##*/}$BRANCH"
COST_FMT=$(printf '$%.2f' "$COST")
echo "${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET} | ${MINS}m ${SECS}s"
