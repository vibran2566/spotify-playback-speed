[CmdletBinding()]
param([string]$SpotifyPath)

$ErrorActionPreference='Stop'
$taskRoot=$PSScriptRoot
# Check prerequisites before closing a running player.
$nodePath=(Get-Command node.exe -ErrorAction Stop).Source
$nodeMajor=& $nodePath -p "Number(process.versions.node.split('.')[0])"
if($LASTEXITCODE -ne 0 -or [int]$nodeMajor -lt 22) { throw 'Node.js 22 or newer is required.' }
$helperPath=Join-Path $taskRoot 'keep-speed-control.mjs'
if(-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'UI helper is missing. Keep the project files together.' }
$debugReady=$false
try { $pages=Invoke-RestMethod 'http://127.0.0.1:9222/json/list' -TimeoutSec 2 } catch { $pages=$null }
if($null -ne $pages) {
    $debugReady=@($pages | Where-Object { $_.type -eq 'page' -and $_.url -like 'https://xpui.app.spotify.com/*' }).Count -gt 0
    if(-not $debugReady -and @($pages).Count -gt 0) { throw 'Port 9222 is serving another debugger. Close it before starting Spotify Speed.' }
}
if(-not $debugReady) {
    if(-not $SpotifyPath) {
        $SpotifyPath=@("$env:APPDATA\Spotify\Spotify.exe", "$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe") |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }
    if(-not $SpotifyPath -or -not (Test-Path -LiteralPath $SpotifyPath -PathType Leaf)) {
        throw 'Spotify was not found. Pass -SpotifyPath with the full path to Spotify.exe.'
    }
    Get-Process -Name Spotify -ErrorAction SilentlyContinue | Stop-Process
    Start-Process -FilePath $SpotifyPath -ArgumentList '--remote-debugging-address=127.0.0.1','--remote-debugging-port=9222' -WindowStyle Hidden
}
$watcher=Get-CimInstance Win32_Process -Filter "name='node.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($helperPath) }
if(-not $watcher) {
    $runtime=Join-Path $taskRoot '.runtime'
    New-Item -ItemType Directory -Force -Path $runtime | Out-Null
    Start-Process -FilePath $nodePath -ArgumentList ('"'+$helperPath+'"') -WorkingDirectory $taskRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runtime 'host.log') -RedirectStandardError (Join-Path $runtime 'host-errors.log')
}
