[CmdletBinding()]
param([string]$SpotifyPath,[switch]$ShowErrors)

$ErrorActionPreference='Stop'
$taskRoot=$PSScriptRoot
try {
$configPath=Join-Path $taskRoot 'installation.json'
$config=if(Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json } else { $null }
# Check prerequisites before closing a running player.
$nodePath=if($config) { $config.nodePath } else { (Get-Command node.exe -ErrorAction Stop).Source }
if(-not $nodePath -or -not (Test-Path -LiteralPath $nodePath -PathType Leaf)) { throw 'Node.js is missing. Run Setup again to repair this installation.' }
$nodeMajor=& $nodePath -p "Number(process.versions.node.split('.')[0])"
if($LASTEXITCODE -ne 0 -or [int]$nodeMajor -lt 22) { throw 'Node.js 22 or newer is required.' }
$helperPath=Join-Path $taskRoot 'keep-speed-control.mjs'
if(-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'UI helper is missing. Keep the project files together.' }
if($config -and -not (Get-Process -Name windhawk -ErrorAction SilentlyContinue)) {
    $windhawkExe=Join-Path (Split-Path -Parent $config.windhawkCli) 'windhawk.exe'
    if(-not (Test-Path -LiteralPath $windhawkExe -PathType Leaf)) { throw 'Windhawk is missing. Run Setup again.' }
    Start-Process -FilePath $windhawkExe -ArgumentList '-tray-only'
}
$debugReady=$false
try { $pages=Invoke-RestMethod 'http://127.0.0.1:9222/json/list' -TimeoutSec 2 } catch { $pages=$null }
if($null -ne $pages) {
    $debugReady=@($pages | Where-Object { $_.type -eq 'page' -and $_.url -like 'https://xpui.app.spotify.com/*' }).Count -gt 0
    if(-not $debugReady -and @($pages).Count -gt 0) { throw 'Port 9222 is serving another debugger. Close it before starting Spotify Playback Speed.' }
}
if($config -and $config.needsRestart) { $debugReady=$false }
if(-not $debugReady) {
    if(-not $SpotifyPath) {
        if($config) { $SpotifyPath=$config.spotifyPath }
    }
    if(-not $SpotifyPath) {
        $SpotifyPath=@("$env:APPDATA\Spotify\Spotify.exe", "$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe") |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }
    if(-not $SpotifyPath -or -not (Test-Path -LiteralPath $SpotifyPath -PathType Leaf)) {
        throw 'Spotify was not found. Pass -SpotifyPath with the full path to Spotify.exe.'
    }
    Get-Process -Name Spotify -ErrorAction SilentlyContinue | Stop-Process
    Start-Process -FilePath $SpotifyPath -ArgumentList '--remote-debugging-address=127.0.0.1','--remote-debugging-port=9222'
}
$watcher=Get-CimInstance Win32_Process -Filter "name='node.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($helperPath) }
$runtime=Join-Path $taskRoot '.runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
if(-not $watcher) {
    Remove-Item -LiteralPath (Join-Path $runtime 'ready.json') -ErrorAction SilentlyContinue
    Start-Process -FilePath $nodePath -ArgumentList ('"'+$helperPath+'"') -WorkingDirectory $taskRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runtime 'host.log') -RedirectStandardError (Join-Path $runtime 'host-errors.log')
}
$deadline=(Get-Date).AddSeconds(40)
do {
    try {
        $bridge=Invoke-RestMethod 'http://127.0.0.1:8758/speed' -TimeoutSec 1
        $ready=Get-Content -LiteralPath (Join-Path $runtime 'ready.json') -Raw -ErrorAction Stop | ConvertFrom-Json
        if($bridge.ok -and [DateTimeOffset]::FromUnixTimeMilliseconds($ready.timestamp).UtcDateTime -gt [DateTime]::UtcNow.AddSeconds(-8)) {
            if($config -and $config.needsRestart) { $config.needsRestart=$false;$config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8 }
            Write-Output 'Spotify speed control is ready.';return
        }
    } catch {}
    Start-Sleep -Milliseconds 500
} while((Get-Date) -lt $deadline)
throw 'Spotify speed control did not become ready. Finish signing into Spotify and make sure a track is available. Check that the mod is enabled in Windhawk, then try again. Details are in .runtime\host-errors.log in the installation folder.'
} catch {
    if($ShowErrors) { $shell=New-Object -ComObject WScript.Shell;$null=$shell.Popup($_.Exception.Message,0,'Spotify Playback Speed',16);exit 1 }
    throw
}
