# claude-statusline

A multi-line status line for [Claude Code](https://claude.com/claude-code):

```
5h ▰▰▰▱▱▱▱▱▱▱  31% 2h04m  7d ▰▱▱▱▱▱▱▱▱▱  12% 5d10h │ ~/projects/app ⎇ main │ Sonnet 5.5
5h ▰▰▰▰▰▰▱▱▱▱  58% 47m    7d ▰▰▰▱▱▱▱▱▱▱  27% 3d02h │ ctx ▰▰▱▱▱▱▱▱▱▱  23% $0.41 │ cpu 12% ram 48%
♫ Artist - Title 1:12/3:45 ━━━━──────
```

- **Directory, git branch, model**, a **context-window bar** with session cost.
- **Per-account 5h / 7d quota bars** with reset countdowns, one row per Claude account, when you route Claude Code through a self-hosted 9router gateway.
- **CPU / RAM** and a **now-playing Spotify** line with a live progress bar (Windows only; omitted elsewhere).

Bars go green → yellow → orange → red as quota is consumed.

## Requirements

| Needed for | Requirement |
| --- | --- |
| Everything | `sh` (Git for Windows provides it), [`jq`](https://jqlang.github.io/jq/) |
| 9router usage bars | Node.js 18+ |
| CPU/RAM, Spotify | Windows (PowerShell 5.1 + WScript, both built in) |

## Install

Windows:

```powershell
git clone https://github.com/naughty00shortie/claude-statusline
cd claude-statusline
powershell -ExecutionPolicy Bypass -File install.ps1
```

macOS / Linux:

```sh
git clone https://github.com/naughty00shortie/claude-statusline
cd claude-statusline
./install.sh
```

This copies the scripts to `~/.claude/statusline/` and sets `statusLine` in `~/.claude/settings.json` (the old file is saved as `settings.json.bak`). Restart Claude Code. Re-run the installer to update. Uninstall with `install.ps1 -Uninstall` / `./install.sh --uninstall`.

To install by hand instead, copy `statusline/*` to `~/.claude/statusline/` and add:

```json
"statusLine": {
  "type": "command",
  "command": "sh \"$HOME/.claude/statusline/statusline.sh\"",
  "refreshInterval": 2
}
```

## 9router usage bars

Nothing about your gateway is baked in. The fetcher reads two things:

| Setting | Where from |
| --- | --- |
| Gateway URL | `NINEROUTER_URL`, else `ANTHROPIC_BASE_URL` (Claude Code already exports your `settings.json` `env` block, so if you use 9router the URL is picked up automatically) |
| Dashboard password | `NINEROUTER_DASHBOARD_PASSWORD`, else the file `~/.config/9router/dashboard-password` |

Simplest setup: put your dashboard password in that file.

```sh
mkdir -p ~/.config/9router
printf '%s' 'your-dashboard-password' > ~/.config/9router/dashboard-password
chmod 600 ~/.config/9router/dashboard-password
```

The fetcher logs in to the dashboard, reads each active Claude connection's `session (5h)` and `weekly (7d)` quota, and caches the result in `~/.cache/9router-usage.json`. It runs in the background at most every 2 minutes and never blocks a repaint. With no password configured, or a gateway that isn't 9router, the quota rows are skipped and you still get the directory/model/context lines.

This uses the dashboard password, not your API key. The password is only sent to your own gateway.

## How it works

`statusline.sh` reads Claude Code's JSON payload on stdin and prints the lines. It never starts PowerShell itself: on Windows a single long-lived hidden helper (`statusline-helper.ps1`, launched via `statusline-helper.vbs`) refreshes CPU/RAM and Spotify caches, and exits on its own ten minutes after the status line stops being used.

## License

MIT
