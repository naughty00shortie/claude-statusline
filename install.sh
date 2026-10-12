#!/bin/sh
# Installs the Claude Code status line into ~/.claude/statusline and points the
# "statusLine" setting in ~/.claude/settings.json at it. Re-run to update.
#
#   ./install.sh              install / update
#   ./install.sh --uninstall  remove

set -e
here=$(cd "$(dirname "$0")" && pwd)
claude="$HOME/.claude"
dest="$claude/statusline"
settings="$claude/settings.json"
command='sh "$HOME/.claude/statusline/statusline.sh"'

command -v jq >/dev/null 2>&1 || { echo "jq is required (https://jqlang.github.io/jq/)" >&2; exit 1; }
mkdir -p "$claude"
[ -f "$settings" ] || echo '{}' > "$settings"

if [ "${1:-}" = "--uninstall" ]; then
  cp "$settings" "$settings.bak"
  jq --arg c "$command" 'if .statusLine.command == $c then del(.statusLine) else . end' "$settings.bak" > "$settings"
  rm -rf "$dest"
  echo "Status line removed. Previous settings.json saved as settings.json.bak."
  exit 0
fi

command -v node >/dev/null 2>&1 || echo "warning: node not found; the 9router usage bars will not appear (install Node.js 18+)." >&2

mkdir -p "$dest"
cp "$here"/statusline/* "$dest"/
chmod +x "$dest"/*.sh

cp "$settings" "$settings.bak"
jq --arg c "$command" '.statusLine = {type: "command", command: $c, refreshInterval: 2}' "$settings.bak" > "$settings"

echo "Installed to $dest"
echo "Restart Claude Code to pick it up. For 9router usage bars see the README (dashboard password)."
