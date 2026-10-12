#!/bin/sh
# Sourced by the status line (defines sys_line and spotify_raw). Both only read
# cache files written by statusline-helper.ps1, a single long-lived hidden
# PowerShell. The status line never runs powershell.exe itself: one started from
# here inherits Claude Code's hidden console, which is torn down when the run
# ends, and PowerShell 5.1 then crashes ("powershell has stopped working").
_now() { printf '%s' "${EPOCHSECONDS:-$(date +%s)}"; }

# Keeps the helper alive: tells it a status line is still in use, and relaunches
# it (via wscript, which gives it its own hidden console) when its heartbeat is
# older than 15s. A launch lock stops every repaint from re-launching while it
# starts up; the helper's mutex makes duplicate launches harmless anyway.
_helper() {
  _hd="$SL_DIR"
  [ -f "$_hd/statusline-helper.ps1" ] || return 0
  # The helper is Windows-only (PowerShell + WScript); elsewhere cpu/ram and
  # now-playing are simply omitted.
  command -v wscript.exe >/dev/null 2>&1 || return 0
  _n=$(_now)
  _p=$(stat -c %Y "$_hd/.statusline-ping" 2>/dev/null || echo 0)
  [ $((_n - _p)) -ge 30 ] && touch "$_hd/.statusline-ping"
  _b=$(stat -c %Y "$_hd/.statusline-helper.beat" 2>/dev/null || echo 0)
  [ $((_n - _b)) -le 15 ] && return 0
  _l=$(stat -c %Y "$_hd/.statusline-helper.launch" 2>/dev/null || echo 0)
  [ $((_n - _l)) -le 20 ] && return 0
  touch "$_hd/.statusline-ping" "$_hd/.statusline-helper.launch"
  wscript.exe //B //NoLogo "$(cygpath -w "$_hd/statusline-helper.vbs")" >/dev/null 2>&1 &
}
_helper

# Prints "cpu% ram%" from the cache.
sys_line() {
  _cache="$SL_DIR/.sys-cache"
  [ -s "$_cache" ] && read -r _line < "$_cache" && printf '%s' "$_line"
}

# Prints "<epoch-of-sample>|<Artist - Title m:ss/m:ss>" from the cache (empty
# when nothing is playing). The caller advances the position by the age of the
# sample, so the bar keeps moving smoothly between refreshes.
spotify_raw() {
  _cache="$SL_DIR/.spotify-cache"
  [ -s "$_cache" ] && read -r _line < "$_cache" && printf '%s' "$_line"
}
