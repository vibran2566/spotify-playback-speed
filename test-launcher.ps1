$ErrorActionPreference='Stop'
$launcher=Join-Path $PSScriptRoot 'Start-Spotify-Speed.ps1'
$global:launcherTestStops=0
$global:launcherTestStarts=@()
$global:launcherTestMode='regular'
function Assert($Condition,$Message) { if(-not $Condition) { throw $Message } }
function Invoke-RestMethod { param($Uri,$TimeoutSec)
    if($global:launcherTestMode -eq 'other-debugger') { return @([pscustomobject]@{type='page';url='https://example.invalid/'}) }
    if($global:launcherTestMode -eq 'ready') { return @([pscustomobject]@{type='page';url='https://xpui.app.spotify.com/index.html'}) }
    throw 'No debugger'
}
function Test-Path { param($LiteralPath,$PathType)
    if($LiteralPath -like '*keep-speed-control.mjs') { return $true }
    if($global:launcherTestMode -eq 'missing') { return $false }
    if($LiteralPath -eq 'D:\Music Apps\Spotify\Spotify.exe') { return $global:launcherTestMode -eq 'explicit' }
    if($LiteralPath -eq "$env:APPDATA\Spotify\Spotify.exe") { return $global:launcherTestMode -eq 'regular' }
    if($LiteralPath -eq "$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe") { return $global:launcherTestMode -eq 'store' }
    return $false
}
function Get-Process { param($Name,$ErrorAction) return [pscustomobject]@{Id=42} }
function Stop-Process { param([Parameter(ValueFromPipeline)]$InputObject) process { $global:launcherTestStops++ } }
function Start-Process { param($FilePath,$ArgumentList,$WindowStyle,$WorkingDirectory,$RedirectStandardOutput,$RedirectStandardError)
    $global:launcherTestStarts+=@([pscustomobject]@{path=$FilePath;args=$ArgumentList;style=$WindowStyle})
}
function Get-CimInstance { param($ClassName,$Filter)
    if($global:launcherTestMode -eq 'ready') { return [pscustomobject]@{CommandLine='node "'+(Join-Path $PSScriptRoot 'keep-speed-control.mjs')+'"'} }
}
function New-Item { param($ItemType,[switch]$Force,$Path) }

foreach($case in @('missing','other-debugger','regular','store','explicit','ready')) {
    $global:launcherTestMode=$case;$global:launcherTestStops=0;$global:launcherTestStarts=@();$failed=$false
    try {
        if($case -eq 'explicit') { & $launcher -SpotifyPath 'D:\Music Apps\Spotify\Spotify.exe' }
        else { & $launcher }
    } catch { $failed=$true;if($case -in @('regular','store','explicit','ready')) { Write-Output $_ } }
    if($case -in @('missing','other-debugger')) {
        Assert $failed "$case must fail"
        Assert ($global:launcherTestStops -eq 0 -and $global:launcherTestStarts.Count -eq 0) "$case must not change running processes"
    } elseif($case -eq 'ready') {
        Assert (-not $failed) 'Already-running setup must succeed'
        Assert ($global:launcherTestStops -eq 0 -and $global:launcherTestStarts.Count -eq 0) 'Repeated launch must reuse Spotify and helper'
    } else {
        Assert (-not $failed) "$case setup must succeed"
        Assert ($global:launcherTestStops -eq 1 -and $global:launcherTestStarts.Count -eq 2) "$case must relaunch Spotify and start one helper"
        $expected=if($case -eq 'regular') { "$env:APPDATA\Spotify\Spotify.exe" } elseif($case -eq 'explicit') { 'D:\Music Apps\Spotify\Spotify.exe' } else { "$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe" }
        Assert ($global:launcherTestStarts[0].path -eq $expected) "$case must use correct executable"
        Assert ($global:launcherTestStarts[0].args -contains '--remote-debugging-address=127.0.0.1') 'Debugger must request loopback'
        Assert ($global:launcherTestStarts[1].style -eq 'Hidden') 'Helper must run hidden'
    }
    Write-Output "PASS: $case"
}
