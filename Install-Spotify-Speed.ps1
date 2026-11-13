[CmdletBinding()]
param(
    [string]$WindhawkCli,
    [string]$SpotifyPath,
    [string]$InstallDir=(Join-Path $env:LOCALAPPDATA 'Programs\Spotify Audio Speed')
)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$files=@('Start-Spotify-Speed.ps1','keep-speed-control.mjs','speed-control.js','spotify-audio-speed.wh.cpp','Uninstall-Spotify-Speed.ps1','LICENSE','README.md')

function Find-Windhawk {
    $command=Get-Command windhawk-cli.exe -ErrorAction SilentlyContinue
    $candidates=@($WindhawkCli,$command.Source,"$env:LOCALAPPDATA\Programs\Windhawk\windhawk-cli.exe","$env:ProgramFiles\Windhawk\windhawk-cli.exe","${env:ProgramFiles(x86)}\Windhawk\windhawk-cli.exe")
    $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}
function Download($Url,$Path) {
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Path
}
function Check-Hash($Path,$Expected) {
    if($Expected -notmatch '^[0-9a-fA-F]{64}$' -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) {
        throw 'Downloaded file failed its SHA256 check. Nothing from that download will be run.'
    }
}

try {
    Write-Host 'Spotify Audio Speed Setup' -ForegroundColor Green
    Write-Host 'Installs the speed control and creates a desktop shortcut. Spotify and Windhawk remain separate apps.'
    if([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        throw 'This version requires Windows x64.'
    }
    foreach($file in $files) { if(-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) { throw "Missing $file. Extract the entire ZIP before running Setup." } }
    if(-not $SpotifyPath) {
        $SpotifyPath=@("$env:APPDATA\Spotify\Spotify.exe","$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe") | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }
    if(-not $SpotifyPath -or -not (Test-Path -LiteralPath $SpotifyPath -PathType Leaf)) { throw 'Install Spotify first. For a custom location, run Install-Spotify-Speed.ps1 -SpotifyPath with its executable path.' }
    $cli=Find-Windhawk
    if(-not $cli) {
        Write-Host 'Downloading the official Windhawk 2 installer. In its wizard, include Development tools.' -ForegroundColor Yellow
        $release=(Invoke-RestMethod 'https://api.github.com/repos/ramensoftware/windhawk/releases?per_page=20' -Headers @{'User-Agent'='Spotify-Audio-Speed-Setup'}) |
            Where-Object { -not $_.draft -and $_.tag_name -match '^v?2\.' } | Select-Object -First 1
        $asset=$release.assets | Where-Object name -eq 'windhawk_setup.exe' | Select-Object -First 1
        if(-not $asset -or $asset.browser_download_url -notlike 'https://github.com/ramensoftware/windhawk/releases/download/*' -or $asset.digest -notmatch '^sha256:[0-9a-fA-F]{64}$') { throw 'Could not find a verifiable official Windhawk 2 installer. Install it from https://github.com/ramensoftware/windhawk/releases and rerun Setup.' }
        $downloadDir=Join-Path ([IO.Path]::GetTempPath()) ('spotify-speed-'+[guid]::NewGuid())
        New-Item -ItemType Directory -Path $downloadDir | Out-Null
        $installer=Join-Path $downloadDir 'windhawk_setup.exe'
        Download $asset.browser_download_url $installer
        Check-Hash $installer $asset.digest.Substring(7)
        $process=Start-Process -FilePath $installer -Wait -PassThru
        if($process.ExitCode -ne 0) { throw 'Windhawk installation was cancelled or failed. Run Setup again when ready.' }
        $cli=Find-Windhawk
        if(-not $cli) { throw 'Windhawk CLI was not found after installation. Install Windhawk 2, or pass -WindhawkCli with the full path to windhawk-cli.exe.' }
    }
    $windhawkRoot=Split-Path -Parent $cli
    if(-not (Test-Path -LiteralPath (Join-Path $windhawkRoot 'Compiler\bin\clang++.exe') -PathType Leaf)) {
        throw 'Windhawk development tools are missing. Add Development tools in Windhawk, then run Setup again.'
    }
    if(Test-Path -LiteralPath $InstallDir) {
        $marker=Join-Path $InstallDir 'installation.json'
        $partial=Join-Path $InstallDir '.installing'
        $owned=(Test-Path -LiteralPath $partial -PathType Leaf) -and (Get-Content -LiteralPath $partial -Raw).Trim() -eq 'spotify-audio-speed'
        if(Test-Path -LiteralPath $marker -PathType Leaf) { $owned=(Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json).appId -eq 'spotify-audio-speed' }
        if(-not $owned -and @(Get-ChildItem -LiteralPath $InstallDir -Force).Count -gt 0) { throw 'The install folder contains other files. Choose an empty folder with -InstallDir.' }
    }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Set-Content -LiteralPath (Join-Path $InstallDir '.installing') -Value 'spotify-audio-speed'
    Write-Host 'Checking Node.js...'
    $node=Join-Path $InstallDir 'runtime\node\node.exe'
    if(-not (Test-Path -LiteralPath $node -PathType Leaf)) { $command=Get-Command node.exe -ErrorAction SilentlyContinue;$node=$command.Source }
    $nodeMajor=0
    if($node) { $nodeMajor=& $node -p "Number(process.versions.node.split('.')[0])"; if($LASTEXITCODE -ne 0) { $nodeMajor=0 } }
    if([int]$nodeMajor -lt 22) {
        Write-Host 'Downloading portable Node.js LTS from nodejs.org (no system installation).'
        $nodeRelease=(Invoke-RestMethod 'https://nodejs.org/dist/index.json') | Where-Object { $_.lts -and [version]$_.version.TrimStart('v') -ge [version]'22.0.0' } | Select-Object -First 1
        if(-not $nodeRelease -or $nodeRelease.version -notmatch '^v\d+\.\d+\.\d+$') { throw 'Could not select a supported Node.js LTS release.' }
        $name='node-'+$nodeRelease.version+'-win-x64'
        $base='https://nodejs.org/dist/'+$nodeRelease.version
        $downloadDir=Join-Path ([IO.Path]::GetTempPath()) ('spotify-speed-'+[guid]::NewGuid())
        New-Item -ItemType Directory -Path $downloadDir | Out-Null
        $archive=Join-Path $downloadDir ($name+'.zip')
        Download ($base+'/'+$name+'.zip') $archive
        $checksums=(Invoke-WebRequest -UseBasicParsing ($base+'/SHASUMS256.txt')).Content
        $line=@($checksums -split "`n" | Where-Object { $_.Trim().EndsWith('  '+$name+'.zip') })
        if($line.Count -ne 1) { throw 'Node.js checksum was not found.' }
        Check-Hash $archive (($line[0] -split '\s+')[0])
        $nodeFolder=Join-Path $InstallDir 'runtime\node'
        New-Item -ItemType Directory -Force -Path $nodeFolder | Out-Null
        # Only Node itself and its license are needed; npm is not used.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip=[IO.Compression.ZipFile]::OpenRead($archive)
        try {
            foreach($file in @('node.exe','LICENSE')) {
                $entry=$zip.GetEntry($name+'/'+$file)
                if(-not $entry) { throw "The Node.js archive is missing $file." }
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $nodeFolder $file),$true)
            }
        } finally { $zip.Dispose() }
        $node=Join-Path $nodeFolder 'node.exe'
    }
    $nodeMajor=& $node -p "Number(process.versions.node.split('.')[0])"
    if($LASTEXITCODE -ne 0 -or [int]$nodeMajor -lt 22) { throw 'Node.js could not start. Setup stopped before changing the mod.' }
    Write-Host 'Installing the speed control...'
    $installedHelper=Join-Path $InstallDir 'keep-speed-control.mjs'
    Get-CimInstance Win32_Process -Filter "name='node.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($installedHelper) } | ForEach-Object { Stop-Process -Id $_.ProcessId }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    foreach($file in $files) {
        $from=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $file));$to=[IO.Path]::GetFullPath((Join-Path $InstallDir $file))
        if($from -ne $to) { Copy-Item -LiteralPath $from -Destination $to -Force }
    }
    & $cli mod install --file (Join-Path $InstallDir 'spotify-audio-speed.wh.cpp') --disabled
    if($LASTEXITCODE -ne 0) { throw 'Windhawk could not compile/install the mod. Check its Development tools and the error above.' }
    & $cli mod enable local@spotify-audio-speed
    if($LASTEXITCODE -ne 0) { throw 'Windhawk could not enable the mod. Open Windhawk and enable Spotify Audio Speed.' }
    @{appId='spotify-audio-speed';nodePath=$node;windhawkCli=$cli;spotifyPath=$SpotifyPath;needsRestart=$true} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallDir 'installation.json') -Encoding UTF8
    $shell=New-Object -ComObject WScript.Shell
    $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $InstallDir 'Start-Spotify-Speed.ps1')+'" -ShowErrors'
    $startMenu=Join-Path ([Environment]::GetFolderPath('Programs')) 'Spotify Audio Speed'
    New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
    foreach($path in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Spotify Speed.lnk'),(Join-Path $startMenu 'Spotify Speed.lnk'))) {
        $shortcut=$shell.CreateShortcut($path);$shortcut.TargetPath=$powershell;$shortcut.Arguments=$arguments;$shortcut.WorkingDirectory=$InstallDir;$shortcut.Description='Spotify with live speed control';$shortcut.Save()
    }
    $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SpotifyAudioSpeed'
    New-Item -Path $key -Force | Out-Null
    $uninstall='"'+$powershell+'" -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $InstallDir 'Uninstall-Spotify-Speed.ps1')+'"'
    foreach($entry in @{DisplayName='Spotify Audio Speed';DisplayVersion='0.3.2';Publisher='Spotify Audio Speed contributors';InstallLocation=$InstallDir;UninstallString=$uninstall}.GetEnumerator()) { New-ItemProperty -Path $key -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null }
    New-ItemProperty -Path $key -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $key -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
    Remove-Item -LiteralPath (Join-Path $InstallDir '.installing')
    Write-Host "Installed in $InstallDir" -ForegroundColor Green
    Write-Host 'Open Spotify Speed from your desktop or Start menu. Its first launch may restart Spotify.'
    Write-Host 'You can delete the extracted download folder. Remove the app later through Windows Installed apps.'
} catch { Write-Host ("Setup failed: "+$_.Exception.Message) -ForegroundColor Red;exit 1 }
