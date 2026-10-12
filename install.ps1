# Installs the Claude Code status line into ~/.claude/statusline and points the
# "statusLine" setting in ~/.claude/settings.json at it. Re-run to update.
#
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall

param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$claude = Join-Path $env:USERPROFILE '.claude'
$dest = Join-Path $claude 'statusline'
$settings = Join-Path $claude 'settings.json'
$command = 'sh "$HOME/.claude/statusline/statusline.sh"'

function Read-Settings {
  if (Test-Path $settings) { Get-Content $settings -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
}
function Write-Settings($obj) {
  if (Test-Path $settings) { Copy-Item $settings "$settings.bak" -Force }
  New-Item -ItemType Directory -Force $claude | Out-Null
  [System.IO.File]::WriteAllText($settings, ($obj | ConvertTo-Json -Depth 100), (New-Object System.Text.UTF8Encoding($false)))
}

if ($Uninstall) {
  $s = Read-Settings
  if ($s.PSObject.Properties['statusLine'] -and $s.statusLine.command -eq $command) {
    $s.PSObject.Properties.Remove('statusLine')
    Write-Settings $s
  }
  Get-Process powershell -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*statusline-helper.ps1*' } | Stop-Process -Force -ErrorAction SilentlyContinue
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  Write-Host 'Status line removed. Previous settings.json saved as settings.json.bak.'
  return
}

foreach ($tool in 'sh', 'jq') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "'$tool' was not found on PATH. Install Git for Windows (sh) and jq (e.g. winget install jqlang.jq), then re-run."
  }
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Warning 'node was not found: the 9router per-account usage bars will not appear. Install Node.js 18+ to enable them.'
}

New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'statusline\*') $dest -Force

$s = Read-Settings
$line = [pscustomobject]@{ type = 'command'; command = $command; refreshInterval = 2 }
if ($s.PSObject.Properties['statusLine']) { $s.statusLine = $line } else { $s | Add-Member -NotePropertyName statusLine -NotePropertyValue $line }
Write-Settings $s

Write-Host "Installed to $dest"
Write-Host 'Restart Claude Code to pick it up. For 9router usage bars see the README (dashboard password).'
