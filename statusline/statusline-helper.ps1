# Background feeder for the Claude Code status line. One long-lived hidden
# PowerShell keeps the CPU/RAM and Spotify caches fresh, so the status line only
# reads files and never spawns powershell.exe itself.
#
# Why: a powershell.exe started from the status line inherits Claude Code's
# hidden console. When the status line run ends or is cancelled, that console is
# torn down while PowerShell is still running, and PowerShell 5.1 then crashes
# in ConsoleControl ("powershell has stopped working"). This process is started
# by statusline-helper.vbs with its own hidden console, so it never loses it.
#
# Caches (same formats statusline-sys.sh has always read):
#   .sys-cache      "<cpu%> <ram%>"
#   .spotify-cache  "<epoch-of-sample>|<Artist - Title m:ss/m:ss>", empty when nothing plays
#   .statusline-helper.beat  touched every loop; the status line relaunches us when it goes stale
#
# Exits on its own once no status line has pinged .statusline-ping for 10 minutes.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeStatuslineHelper')
if (-not $mutex.WaitOne(0)) { exit 0 }

$dir = $PSScriptRoot
$sysCache = Join-Path $dir '.sys-cache'
$spotifyCache = Join-Path $dir '.spotify-cache'
$beat = Join-Path $dir '.statusline-helper.beat'
$ping = Join-Path $dir '.statusline-ping'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Cache($path, $text) {
  $tmp = "$path.$PID.tmp"
  try {
    [System.IO.File]::WriteAllText($tmp, $text, $utf8)
    Move-Item -LiteralPath $tmp -Destination $path -Force
  } catch {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Get-Epoch { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

# --- CPU / RAM -------------------------------------------------------------
# Same measure as Task Manager. A rate counter needs two samples, so take two a
# second apart and use the second. (Get-Counter rather than the .NET
# PerformanceCounter class, which fails on this machine.)
function Get-SysLine {
  $s = Get-Counter '\Processor Information(_Total)\% Processor Utility' -SampleInterval 1 -MaxSamples 2
  $cpu = [math]::Min(100, $s[1].CounterSamples[0].CookedValue)
  $os = Get-CimInstance Win32_OperatingSystem
  $ram = 100 * ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize
  '{0:0} {1:0}' -f $cpu, $ram
}

# --- Spotify (Windows media session) ----------------------------------------
$mgr = $null
$propType = $null
$asTask = $null
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  $mgrType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
  $propType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]
} catch { $asTask = $null }

function Await($op, $type) {
  $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
  [void]$t.Wait(2000)
  $t.Result
}

function Fmt($x) { '{0}:{1:00}' -f [int][math]::Floor($x / 60), [int]($x % 60) }

function Get-SpotifyLine {
  if (-not $asTask) { return '' }
  if (-not $script:mgr) { $script:mgr = Await ($mgrType::RequestAsync()) $mgrType }
  $s = $script:mgr.GetSessions() | Where-Object { $_.SourceAppUserModelId -match 'Spotify|^Chromium\.' } | Select-Object -First 1
  if (-not $s) { return '' }
  if ($s.GetPlaybackInfo().PlaybackStatus.ToString() -ne 'Playing') { return '' }
  $p = Await ($s.TryGetMediaPropertiesAsync()) $propType
  if (-not $p.Title) { return '' }
  $tl = $s.GetTimelineProperties()
  $pos = $tl.Position.TotalSeconds + ([DateTimeOffset]::UtcNow - $tl.LastUpdatedTime).TotalSeconds
  $end = $tl.EndTime.TotalSeconds - $tl.StartTime.TotalSeconds
  if ($pos -lt 0) { $pos = 0 }
  if ($end -gt 0 -and $pos -gt $end) { $pos = $end }
  $name = if ($p.Artist) { "$($p.Artist) - $($p.Title)" } else { $p.Title }
  $name = $name -replace '[\r\n|]', ' '
  $line = if ($end -gt 0) { "$name $(Fmt $pos)/$(Fmt $end)" } else { $name }
  "$(Get-Epoch)|$line"
}

# --- Main loop ---------------------------------------------------------------
$idleLimit = 600
$tick = 0
while ($true) {
  try { [System.IO.File]::WriteAllText($beat, [string](Get-Epoch), $utf8) } catch {}

  # Stop when no Claude Code status line has asked for us in a while.
  try {
    $age = ((Get-Date) - (Get-Item -LiteralPath $ping).LastWriteTime).TotalSeconds
    if ($age -gt $idleLimit) { break }
  } catch { break }

  # CPU/RAM every other loop (~5s, the sample itself takes 1s), Spotify every
  # loop (the status line advances the bar between samples by their age).
  if ($tick % 2 -eq 0) {
    try { $l = Get-SysLine; if ($l) { Write-Cache $sysCache "$l`n" } } catch {}
  }
  try {
    $sp = Get-SpotifyLine
    if ($sp) { Write-Cache $spotifyCache "$sp`n" } else { Write-Cache $spotifyCache '' }
  } catch { $script:mgr = $null }

  $tick++
  Start-Sleep -Seconds 2
}

Remove-Item -LiteralPath $beat -Force -ErrorAction SilentlyContinue
$mutex.ReleaseMutex()
