$ErrorActionPreference='Stop'
try {
    $root=$PSScriptRoot
    $config=Get-Content -LiteralPath (Join-Path $root 'installation.json') -Raw | ConvertFrom-Json
    if($config.appId -ne 'spotify-audio-speed') { throw 'This folder is not a Spotify Audio Speed installation.' }
    Write-Host 'Removing Spotify Audio Speed...'
    $helper=Join-Path $root 'keep-speed-control.mjs'
    Get-CimInstance Win32_Process -Filter "name='node.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($helper) } | ForEach-Object { Stop-Process -Id $_.ProcessId }
    if($config.windhawkCli -and (Test-Path -LiteralPath $config.windhawkCli -PathType Leaf)) {
        . (Join-Path $root 'Windhawk-Operations.ps1')
        Invoke-SpotifyWindhawk -Action Remove -CliPath $config.windhawkCli
    } else { Write-Warning 'Windhawk CLI is no longer installed. App cleanup will continue; if Windhawk is still running, remove Spotify Audio Speed in Windhawk too.' }
    foreach($shortcut in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Spotify Speed.lnk'),(Join-Path ([Environment]::GetFolderPath('Programs')) 'Spotify Audio Speed\Spotify Speed.lnk'))) {
        if(Test-Path -LiteralPath $shortcut) {
            $link=(New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
            if($link.Arguments.Contains((Join-Path $root 'Start-Spotify-Speed.ps1'))) { Remove-Item -LiteralPath $shortcut }
        }
    }
    Remove-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SpotifyAudioSpeed' -ErrorAction SilentlyContinue
    # Delete only files installed by this project; keep any user-added files.
    $files=@('Start-Spotify-Speed.ps1','keep-speed-control.mjs','speed-control.js','spotify-audio-speed.wh.cpp','Uninstall-Spotify-Speed.ps1','Windhawk-Operations.ps1','LICENSE','README.md','installation.json','.installing','.runtime\host.log','.runtime\host-errors.log','.runtime\ready.json','runtime\node\node.exe','runtime\node\LICENSE')
    foreach($file in $files) { $path=Join-Path $root $file;if(Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force } }
    foreach($folder in @((Join-Path $root 'runtime\node'),(Join-Path $root 'runtime'),(Join-Path $root '.runtime'),$root,(Join-Path ([Environment]::GetFolderPath('Programs')) 'Spotify Audio Speed'))) {
        if((Test-Path -LiteralPath $folder -PathType Container) -and @(Get-ChildItem -LiteralPath $folder -Force).Count -eq 0) { Remove-Item -LiteralPath $folder }
    }
    Write-Host 'Removed. Close Spotify and reopen it using its ordinary shortcut to close the local debugger.'
} catch { Write-Host ("Removal failed: "+$_.Exception.Message) -ForegroundColor Red;Read-Host 'Press Enter to close';exit 1 }
