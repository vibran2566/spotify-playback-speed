param([ValidateSet('Install','Remove')][string]$Action,[string]$CliPath,[string]$SourceFile,[string]$LogPath)
$script:spotifyWindhawkOperations=$PSCommandPath

function Invoke-SpotifyWindhawk {
    param([Parameter(Mandatory)][ValidateSet('Install','Remove')][string]$Action,
          [Parameter(Mandatory)][string]$CliPath,[string]$SourceFile,[string]$LogPath)
    $CliPath=[IO.Path]::GetFullPath($CliPath)
    if($Action -eq 'Install') { $SourceFile=[IO.Path]::GetFullPath($SourceFile) }
    if(-not (Test-Path -LiteralPath $CliPath -PathType Leaf)) { throw 'Windhawk CLI was not found.' }
    if($Action -eq 'Install' -and -not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) { throw 'The mod source file is missing.' }

    function Invoke-SpeedCli([string[]]$Arguments) {
        $previous=$ErrorActionPreference
        try {
            $ErrorActionPreference='Continue'
            $output=@(& $CliPath @Arguments 2>&1)
            $code=$LASTEXITCODE
        } finally { $ErrorActionPreference=$previous }
        if($LogPath) { $output | Out-File -LiteralPath $LogPath -Append -Encoding UTF8 }
        else { $output | ForEach-Object { Write-Host $_ } }
        return [int]$code
    }

    # Reads work without elevation; an already-removed mod needs no UAC prompt.
    if($Action -eq 'Remove') {
        $code=Invoke-SpeedCli -Arguments @('mod','show','local@spotify-audio-speed')
        if($code -eq 4) { Write-Host 'The Windhawk mod is already removed.';return }
        if($code -ne 0) { throw "Could not inspect the Windhawk mod (exit $code)." }
    }
    $ini=Join-Path (Split-Path -Parent $CliPath) 'windhawk.ini'
    $portable=(Test-Path -LiteralPath $ini -PathType Leaf) -and (Get-Content -LiteralPath $ini -Raw) -match '(?m)^\s*Portable\s*=\s*1\s*$'
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try { $admin=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } finally { $identity.Dispose() }
    if(-not $portable -and -not $admin) {
        Write-Host 'Windows will ask permission for the Windhawk mod operation. App files and shortcuts stay in your user account.'
        $resultLog=Join-Path ([IO.Path]::GetTempPath()) ('spotify-windhawk-'+[guid]::NewGuid()+'.log')
        $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$script:spotifyWindhawkOperations+'" -Action '+$Action+' -CliPath "'+$CliPath+'" -LogPath "'+$resultLog+'"'
        if($Action -eq 'Install') { $arguments+=' -SourceFile "'+$SourceFile+'"' }
        try {
            $process=Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
            $details=if(Test-Path -LiteralPath $resultLog) { Get-Content -LiteralPath $resultLog -Raw } else { '' }
            if($process.ExitCode -ne 0) { throw "Windhawk $Action failed. $details" }
            if($details) { Write-Host $details }
        } finally { Remove-Item -LiteralPath $resultLog -ErrorAction SilentlyContinue }
        return
    }
    if($Action -eq 'Install') {
        $code=Invoke-SpeedCli -Arguments @('mod','install','--file',$SourceFile,'--disabled')
        if($code -ne 0) { throw "Windhawk could not compile/install the mod (exit $code). Check its Development tools and the error above." }
        $code=Invoke-SpeedCli -Arguments @('mod','enable','local@spotify-audio-speed')
    } else { $code=Invoke-SpeedCli -Arguments @('--yes','mod','remove','local@spotify-audio-speed') }
    if($code -ne 0 -and -not ($Action -eq 'Remove' -and $code -eq 4)) { throw "Windhawk $Action failed (exit $code)." }
}

if($Action) {
    try { Invoke-SpotifyWindhawk -Action $Action -CliPath $CliPath -SourceFile $SourceFile -LogPath $LogPath;exit 0 }
    catch {
        if($LogPath) { $_.Exception.Message | Out-File -LiteralPath $LogPath -Append -Encoding UTF8 }
        else { Write-Host $_.Exception.Message -ForegroundColor Red }
        exit 1
    }
}
