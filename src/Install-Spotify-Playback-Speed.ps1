[CmdletBinding()]
param(
    [string]$WindhawkCli,
    [string]$SpotifyPath,
    [string]$InstallDir=(Join-Path $env:LOCALAPPDATA 'Programs\Spotify Playback Speed')
)
$ErrorActionPreference='Stop'
$files=@('Start-Spotify-Playback-Speed.ps1','keep-speed-control.mjs','speed-control.js','spotify-playback-speed.wh.cpp','Uninstall-Spotify-Playback-Speed.ps1','Windhawk-Operations.ps1')
$sourceFiles=@($files | ForEach-Object { Join-Path $PSScriptRoot $_ })
$packageRoot=Split-Path -Parent $PSScriptRoot
$sourceFiles+=@((Join-Path $packageRoot 'LICENSE'),(Join-Path $packageRoot 'README.md'))
# Upgrade older installs in place so their portable runtime and custom files stay intact.
if(-not $PSBoundParameters.ContainsKey('InstallDir') -and -not (Test-Path -LiteralPath $InstallDir)) {
    $legacyRoot=Join-Path $env:LOCALAPPDATA 'Programs\Spotify Audio Speed'
    $legacyMarker=Join-Path $legacyRoot 'installation.json'
    if(Test-Path -LiteralPath $legacyMarker -PathType Leaf) {
        try { if((Get-Content -LiteralPath $legacyMarker -Raw | ConvertFrom-Json).appId -eq 'spotify-audio-speed') { $InstallDir=$legacyRoot } } catch {}
    }
}

function Find-Windhawk {
    $command=Get-Command windhawk-cli.exe -ErrorAction SilentlyContinue
    $candidates=@($WindhawkCli,$command.Source,"$env:LOCALAPPDATA\Programs\Windhawk\windhawk-cli.exe","$env:ProgramFiles\Windhawk\windhawk-cli.exe","${env:ProgramFiles(x86)}\Windhawk\windhawk-cli.exe")
    $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}

try {
    Write-Host 'Spotify Playback Speed Setup' -ForegroundColor Green
    Write-Host 'Installs the speed control and creates a desktop shortcut. Spotify and Windhawk remain separate apps.'
    if([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        throw 'This version requires Windows x64.'
    }
    foreach($file in $sourceFiles) { if(-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing $(Split-Path -Leaf $file). Extract the entire ZIP before running Setup." } }
    if(-not $SpotifyPath) {
        $SpotifyPath=@("$env:APPDATA\Spotify\Spotify.exe","$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe") | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }
    if(-not $SpotifyPath -or -not (Test-Path -LiteralPath $SpotifyPath -PathType Leaf)) { throw 'Install Spotify first. For a custom location, run .\src\Install-Spotify-Playback-Speed.ps1 -SpotifyPath with its executable path from the extracted folder.' }
    $cli=Find-Windhawk
    if(-not $cli) { throw 'Windhawk 2 was not found. Install it from https://github.com/ramensoftware/windhawk/releases/download/2.0.0-alpha.8/windhawk_setup.exe with Development tools, then run Setup again.' }
    $windhawkRoot=Split-Path -Parent $cli
    if(-not (Test-Path -LiteralPath (Join-Path $windhawkRoot 'Compiler\bin\clang++.exe') -PathType Leaf)) {
        throw 'Windhawk development tools are missing. Add Development tools in Windhawk, then run Setup again.'
    }
    # Upgrades keep the portable Node copy that older Setup versions downloaded.
    $node=Join-Path $InstallDir 'runtime\node\node.exe'
    if(-not (Test-Path -LiteralPath $node -PathType Leaf)) { $node=@((Get-Command node.exe -ErrorAction SilentlyContinue).Source,"$env:ProgramFiles\nodejs\node.exe") | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1 }
    $nodeMajor=0
    if($node) { $nodeMajor=& $node -p "Number(process.versions.node.split('.')[0])"; if($LASTEXITCODE -ne 0) { $nodeMajor=0 } }
    if([int]$nodeMajor -lt 22) { throw 'Node.js 22 or newer was not found. Install it from https://nodejs.org/dist/v26.13.1/node-v26.13.1-x64.msi, then run Setup again.' }
    if(Test-Path -LiteralPath $InstallDir) {
        $marker=Join-Path $InstallDir 'installation.json'
        $partial=Join-Path $InstallDir '.installing'
        $owned=(Test-Path -LiteralPath $partial -PathType Leaf) -and (Get-Content -LiteralPath $partial -Raw).Trim() -eq 'spotify-audio-speed'
        if(Test-Path -LiteralPath $marker -PathType Leaf) { $owned=(Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json).appId -eq 'spotify-audio-speed' }
        if(-not $owned -and @(Get-ChildItem -LiteralPath $InstallDir -Force).Count -gt 0) { throw 'The install folder contains other files. Choose an empty folder with -InstallDir.' }
    }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Set-Content -LiteralPath (Join-Path $InstallDir '.installing') -Value 'spotify-audio-speed'
    Write-Host 'Installing the speed control...'
    $installedHelper=Join-Path $InstallDir 'keep-speed-control.mjs'
    Get-CimInstance Win32_Process -Filter "name='node.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($installedHelper) } | ForEach-Object { Stop-Process -Id $_.ProcessId }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    foreach($file in $sourceFiles) {
        $from=[IO.Path]::GetFullPath($file);$to=[IO.Path]::GetFullPath((Join-Path $InstallDir (Split-Path -Leaf $file)))
        if($from -ne $to) { Copy-Item -LiteralPath $from -Destination $to -Force }
    }
    . (Join-Path $InstallDir 'Windhawk-Operations.ps1')
    Invoke-SpotifyWindhawk -Action Install -CliPath $cli -SourceFile (Join-Path $InstallDir 'spotify-playback-speed.wh.cpp')
    @{appId='spotify-audio-speed';nodePath=$node;windhawkCli=$cli;spotifyPath=$SpotifyPath;needsRestart=$true} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallDir 'installation.json') -Encoding UTF8
    $shell=New-Object -ComObject WScript.Shell
    $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $InstallDir 'Start-Spotify-Playback-Speed.ps1')+'" -ShowErrors'
    # Store Spotify's Spotify.exe is an app alias with no icon, so point at the package's real exe.
    # shortcut: the Store package path changes when Spotify updates, blanking the icon until Setup runs again; extract a .ico if users notice.
    $iconPath=$SpotifyPath
    if($SpotifyPath -like '*\WindowsApps\*') { $package=Get-AppxPackage SpotifyAB.SpotifyMusic -ErrorAction SilentlyContinue | Select-Object -First 1; if($package) { $iconPath=Join-Path $package.InstallLocation 'Spotify.exe' } }
    $startMenu=Join-Path ([Environment]::GetFolderPath('Programs')) 'Spotify Playback Speed'
    New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
    foreach($path in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Spotify Playback Speed.lnk'),(Join-Path $startMenu 'Spotify Playback Speed.lnk'))) {
        $shortcut=$shell.CreateShortcut($path);$shortcut.TargetPath=$powershell;$shortcut.Arguments=$arguments;$shortcut.WorkingDirectory=$InstallDir;$shortcut.IconLocation="$iconPath,0";$shortcut.Description='Spotify with live speed control';$shortcut.Save()
    }
    $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SpotifyAudioSpeed'
    New-Item -Path $key -Force | Out-Null
    $uninstall='"'+$powershell+'" -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $InstallDir 'Uninstall-Spotify-Playback-Speed.ps1')+'"'
    foreach($entry in @{DisplayName='Spotify Playback Speed';DisplayVersion='0.3.2';Publisher='Spotify Playback Speed contributors';InstallLocation=$InstallDir;UninstallString=$uninstall}.GetEnumerator()) { New-ItemProperty -Path $key -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null }
    New-ItemProperty -Path $key -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $key -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
    Remove-Item -LiteralPath (Join-Path $InstallDir '.installing')
    Write-Host "Installed in $InstallDir" -ForegroundColor Green
    foreach($oldLink in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Spotify Speed.lnk'),(Join-Path ([Environment]::GetFolderPath('Programs')) 'Spotify Audio Speed\Spotify Speed.lnk'))) {
        if(Test-Path -LiteralPath $oldLink -PathType Leaf) {
            $oldShortcut=$shell.CreateShortcut($oldLink)
            if($oldShortcut.Arguments.Contains((Join-Path $InstallDir 'Start-Spotify-Speed.ps1'))) { Remove-Item -LiteralPath $oldLink }
        }
    }
    foreach($oldFile in @('Start-Spotify-Speed.ps1','Uninstall-Spotify-Speed.ps1','spotify-audio-speed.wh.cpp')) {
        $oldPath=Join-Path $InstallDir $oldFile
        if(Test-Path -LiteralPath $oldPath -PathType Leaf) { Remove-Item -LiteralPath $oldPath }
    }
    $oldMenu=Join-Path ([Environment]::GetFolderPath('Programs')) 'Spotify Audio Speed'
    if((Test-Path -LiteralPath $oldMenu -PathType Container) -and @(Get-ChildItem -LiteralPath $oldMenu -Force).Count -eq 0) { Remove-Item -LiteralPath $oldMenu }
    Write-Host 'Open Spotify Playback Speed from your desktop or Start menu. Its first launch may restart Spotify.'
    Write-Host 'You can delete the extracted download folder. Remove the app later through Windows Installed apps.'
} catch { Write-Host ("Setup failed: "+$_.Exception.Message) -ForegroundColor Red;exit 1 }
