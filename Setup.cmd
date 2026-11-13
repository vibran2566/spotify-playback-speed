@echo off
title Spotify Playback Speed Setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Install-Spotify-Playback-Speed.ps1"
if errorlevel 1 (
  echo.
  echo Setup did not finish. See the message above, then run Setup again.
  pause
  exit /b 1
)
echo.
pause
