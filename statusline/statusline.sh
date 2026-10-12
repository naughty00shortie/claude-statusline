#!/bin/sh
# Claude Code status line:
#   <account> 5h <bar> % <reset>  7d <bar> % <reset> │ <dir> [⎇ <branch>] │ <model>
#   <account> 5h <bar> % <reset>  7d <bar> % <reset> │ ctx <bar> %
#   <account> ...   (further accounts, aligned)
# Reads the status line JSON payload on stdin. Every segment after the
# directory is omitted entirely when its field is absent.

input=$(cat)
# Every script and cache lives next to this one (the installer puts them in
# ~/.claude/statusline).
SL_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SL_DIR/statusline-sys.sh"

# Now-playing line from the Spotify desktop app (empty when paused/closed).
spotify_line() {
  raw=$(spotify_raw)
  [ -n "$raw" ] || return 0
  sampled=${raw%%|*}; track=${raw#*|}
  [ -n "$track" ] || return 0
  # "Artist - Title m:ss/m:ss": the time is the last word, the artist is before the first " - ".
  time=${track##* }
  case $time in
    [0-9]*:[0-9][0-9]/[0-9]*:[0-9][0-9]) track=${track% *} ;;
    *) time= ;;
  esac
  case $track in
    *' - '*) artist=${track%% - *}; title=${track#* - } ;;
    *) artist=; title=$track ;;
  esac
  printf '\033[1;32m♫\033[0m'
  [ -n "$artist" ] && printf ' \033[1;95m%s\033[0m \033[90m-\033[0m' "$artist"
  printf ' \033[1;96m%s\033[0m' "$title"
  if [ -n "$time" ]; then
    # Progress bar from "m:ss/m:ss". Seconds have their leading zero stripped so
    # the shell doesn't read "08" as octal.
    cur=${time%/*}; tot=${time#*/}
    cs=${cur#*:}; cs=${cs#0}; cs=${cs:-0}
    ts=${tot#*:}; ts=${ts#0}; ts=${ts:-0}
    cur_s=$(( ${cur%:*} * 60 + cs ))
    tot_s=$(( ${tot%:*} * 60 + ts ))
    # The reading is a few seconds old: advance it by its age (capped at the end).
    cur_s=$(( cur_s + ${EPOCHSECONDS:-$(date +%s)} - sampled ))
    [ "$cur_s" -gt "$tot_s" ] && cur_s=$tot_s
    cur=$(printf '%d:%02d' $((cur_s / 60)) $((cur_s % 60)))
    width=12
    filled=0
    [ "$tot_s" -gt 0 ] && filled=$(( cur_s * width / tot_s ))
    [ "$filled" -gt "$width" ] && filled=$width
    bar_on=; bar_off=; i=0
    while [ "$i" -lt "$width" ]; do
      if [ "$i" -lt "$filled" ]; then bar_on="${bar_on}━"; else bar_off="${bar_off}─"; fi
      i=$((i + 1))
    done
    printf '   \033[1;93m%s\033[0m \033[1;92m%s\033[90m%s\033[0m \033[1;93m%s\033[0m' "${cur}" "$bar_on" "$bar_off" "${tot}"
  fi
}

get() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

# Windows reports C:\Users\x while the shell's HOME is /c/Users/x, so both
# sides are folded to the same form before the home prefix is stripped.
# A no-op on paths that are already POSIX.
to_posix() {
  p=$(printf '%s' "$1" | tr '\\' '/')
  case $p in
    [A-Za-z]:/*)
      drive=$(printf '%s' "$p" | cut -c1 | tr '[:upper:]' '[:lower:]')
      p="/$drive$(printf '%s' "$p" | cut -c3-)"
      ;;
  esac
  printf '%s' "$p"
}

cwd=$(get '.workspace.current_dir')
[ -z "$cwd" ] && cwd=$(pwd)
dir=$(to_posix "$cwd")
home=$(to_posix "$HOME")
case $dir in
  "$home") dir='~' ;;
  "$home"/*) dir="~${dir#"$home"}" ;;
esac

model=$(get '.model.display_name')
ctx=$(get '.context_window.used_percentage')
cost=$(get '.cost.total_cost_usd')

# Current git branch, or the short commit hash when HEAD is detached.
# Empty outside a repository. --no-optional-locks keeps a repaint from
# contending with git commands running in the same repo.
branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short -q HEAD 2>/dev/null)
[ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short -q HEAD 2>/dev/null)

# Requests go through 9router, which spreads them over several Claude
# accounts, so the payload's own rate_limits don't describe any one account.
# Per-account quota comes from a cache written by a background fetcher; it is
# refreshed at most every 2 minutes and never blocks a repaint. The fetcher
# only runs when a 9router dashboard password is configured (see README).
usage_cache="$HOME/.cache/9router-usage.json"
usage_fetcher="$SL_DIR/statusline-9router-usage.mjs"
usage_lock="$HOME/.cache/9router-usage.lock"
if [ -f "$usage_fetcher" ] && { [ -n "${NINEROUTER_DASHBOARD_PASSWORD:-}" ] || [ -f "$HOME/.config/9router/dashboard-password" ]; }; then
  now=$(date +%s)
  fetched=$(jq -r '.fetchedAt // 0' "$usage_cache" 2>/dev/null)
  [ -z "$fetched" ] && fetched=0
  lock_age=$now
  [ -f "$usage_lock" ] && lock_age=$((now - $(date -r "$usage_lock" +%s 2>/dev/null || echo 0)))
  if [ $((now - fetched)) -ge 120 ] && [ "$lock_age" -ge 60 ]; then
    mkdir -p "$HOME/.cache" 2>/dev/null
    touch "$usage_lock"
    (node "$usage_fetcher" >/dev/null 2>&1 &)
  fi
fi

bar() {
  pct=${1%.*}
  [ -z "$pct" ] && pct=0
  width=$2

  filled=$(((pct * width + 50) / 100))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0

  # Ramps by how much is consumed: the closer to depleted, the louder.
  if [ "$pct" -ge 90 ]; then
    colour='1;31' # bold red — effectively out
  elif [ "$pct" -ge 75 ]; then
    colour='0;38;5;208' # orange — running low
  elif [ "$pct" -ge 50 ]; then
    colour='0;33' # yellow — past halfway
  else
    colour='0;32' # green — plenty left
  fi

  i=0
  s=''
  while [ "$i" -lt "$filled" ]; do
    s="$s▰"
    i=$((i + 1))
  done
  while [ "$i" -lt "$width" ]; do
    s="$s▱"
    i=$((i + 1))
  done

  printf '\033[%sm%s\033[0m \033[%sm%3d%%\033[0m' "$colour" "$s" "$colour" "$pct"
}

# Epoch seconds -> compact time remaining, e.g. 5d10h / 2h04m / 47m / now.
until_reset() {
  target=${1%.*}
  case $target in
    '' | *[!0-9]*) return ;;
  esac

  remaining=$((target - $(date +%s)))
  [ "$remaining" -lt 0 ] && remaining=0

  days=$((remaining / 86400))
  hours=$(((remaining % 86400) / 3600))
  mins=$(((remaining % 3600) / 60))

  if [ "$days" -gt 0 ]; then
    printf '%dd%dh' "$days" "$hours"
  elif [ "$hours" -gt 0 ]; then
    printf '%dh%02dm' "$hours" "$mins"
  elif [ "$mins" -gt 0 ]; then
    printf '%dm' "$mins"
  else
    printf 'now'
  fi
}

# Dimmed and padded to a fixed 5 columns (the longest form, e.g. 6d12h), so
# the account rows below line up whatever each countdown's length.
reset_col() { printf '\033[2m%-5s\033[0m' "$(until_reset "$1")"; }

label() { printf '\033[2m%s\033[0m' "$1"; }

# Dim divider between sections of the first line.
sep=$(printf ' \033[2m│\033[0m ')

info=$(printf '\033[1;34m%s\033[0m' "$dir")
[ -n "$branch" ] && info="$info $(printf '\033[0;33m⎇ %s\033[0m' "$branch")"
[ -n "$model" ] && info="$info$sep$(printf '\033[0;36m%s\033[0m' "$model")"
ctx_seg=''
[ -n "$ctx" ] && ctx_seg="$(label ctx) $(bar "$ctx" 10)"
if [ -n "$cost" ] && [ -n "$ctx_seg" ]; then
  ctx_seg="$ctx_seg $(printf '\033[1;93m$%.2f\033[0m' "$cost")"
fi
sys=$(sys_line)
if [ -n "$sys" ] && [ -n "$ctx_seg" ]; then
  ctx_seg="$ctx_seg$sep$(printf '%s' "$sys" | awk '{printf "\033[2mcpu\033[0m \033[1;91m%s%%\033[0m \033[2mram\033[0m \033[1;94m%s%%\033[0m", $1, $2}')"
fi

# Accounts form a column on the left, one per line, with bars lined up; the
# directory/model info follows the first account and the context bar follows
# the second.
# Row format: "5h <bar> % <reset>  7d <bar> % <reset>". Every field is
# fixed-width, so rows align without padding. Account names are not shown.
out=''
n=0
if [ -r "$usage_cache" ]; then
  # "|" rather than tabs: tab is IFS whitespace, so empty fields would
  # collapse and shift the columns. Missing values are written as "-".
  rows=$(jq -r '.accounts[] | [.name, (.five // "-"), (.fiveReset // "-"), (.week // "-"), (.weekReset // "-")] | map(tostring) | join("|")' \
    "$usage_cache" 2>/dev/null | tr -d '\r')
  old_ifs=$IFS
  while IFS='|' read -r name five five_reset week week_reset; do
    [ -z "$name" ] && continue
    [ "$five" = - ] && five=''
    [ "$five_reset" = - ] && five_reset=''
    [ "$week" = - ] && week=''
    [ "$week_reset" = - ] && week_reset=''
    row=''
    [ -n "$five" ] && row="$(label 5h) $(bar "$five" 10) $(reset_col "$five_reset")"
    if [ -n "$week" ]; then
      [ -n "$row" ] && row="$row  "
      row="$row$(label 7d) $(bar "$week" 10) $(reset_col "$week_reset")"
    fi
    n=$((n + 1))
    case $n in
      1) out="$row$sep$info" ;;
      2)
        out="$out
$row"
        [ -n "$ctx_seg" ] && out="$out$sep$ctx_seg"
        ;;
      *) out="$out
$row" ;;
    esac
  done <<EOF
$rows
EOF
  IFS=$old_ifs
fi
# Fewer than two accounts: the info and context bar go on the lines they
# would otherwise have followed.
case $n in
  0)
    out=$info
    [ -n "$ctx_seg" ] && out="$out
$ctx_seg"
    ;;
  1) [ -n "$ctx_seg" ] && out="$out
$ctx_seg" ;;
esac

sp=$(spotify_line)
[ -n "$sp" ] && out="$out
$sp"

printf '%s' "$out"
