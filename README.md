# Spotify Audio Speed

Experimental speed and pitch control for the Spotify Windows desktop app. A button next to Lyrics opens a **0.50x–2.00x** slider with a **1x reset**. Changes apply live after initial setup.

## Known limits

- **Progress bar timing and synchronized lyric scrolling do not account for the changed speed yet.**
- Spotify updates may break the button placement or audio integration. Only the version above has been exercised.
- The audio buffer is increased to 250 ms, which adds latency. Other audio devices, full-range listening, sleep/wake, and reboot recovery are not verified.
- The helper remains running while Spotify is closed. Use this project's launcher when reopening Spotify so the control can return.

This is an independent project, not affiliated with Spotify. No Spotify application files, recordings, or proprietary binaries are distributed.

## Requirements

- Windows x64 with Spotify desktop installed.

Setup reuses [Windhawk](https://windhawk.net/) 2.x and Node.js 22+ when available.

## Install and start

1. [Download the ZIP](https://github.com/vibran2566/spotify-audio-speed/archive/refs/heads/main.zip) and extract it.
2. Double-click **Setup.cmd** inside the extracted folder.
3. If Windhawk's installer opens, finish its wizard with **Development tools** included.
4. Open **Spotify Speed** from your desktop or Start menu.


Start playback, then click the speed button immediately left of Lyrics. The **1x** button resets the rate. Windhawk is started automatically when needed. Startup failures display an error message.

To update, download a new ZIP and run Setup again. Your selected speed is stored in Windhawk. Setup does not change the machine's PowerShell execution policy; the batch launcher permits its included script only for that setup process.

For custom Spotify or portable Windhawk locations, run setup from PowerShell with explicit paths:

```powershell
.\Install-Spotify-Speed.ps1 -SpotifyPath 'D:\Apps\Spotify\Spotify.exe' -WindhawkCli 'D:\Apps\Windhawk\windhawk-cli.exe'
```

## Stop and remove

Remove **Spotify Audio Speed** through Windows **Settings > Apps > Installed apps**. This stops its helper, removes its Windhawk mod, shortcuts and installed files. User-added files are preserved. Spotify and Windhawk stay installed.

Then fully close Spotify and reopen it using its ordinary shortcut to remove the injected UI and close the debugger. To temporarily turn off the audio tweak without uninstalling it, disable **Spotify Audio Speed** in Windhawk.

## Troubleshooting

- **No speed button:** use the Spotify Speed shortcut. If startup fails, read its error message. Logs are in `%LOCALAPPDATA%\Programs\Spotify Audio Speed\.runtime`. A Spotify UI update may have moved the Lyrics button.
- **Speed control unavailable:** confirm Windhawk and the mod are enabled, then fully close and reopen Spotify with the launcher. The audio stream must be created after the mod is loaded.
- **Port 9222 belongs to another debugger:** close that debugger before launching. The script refuses to take over another debugger session.
- **Crackling:** return to 1x. Report your Spotify version, Windows version, audio device, and the rates affected. Earlier development builds crackled; the larger buffer helped on the tested machine, but is not a guarantee for every device.
- **Setup cannot find Windhawk development tools:** add Development tools in Windhawk and rerun Setup.
- **Setup cannot download dependencies:** check your internet connection, or install Windhawk 2 with Development tools and Node.js 22+ manually, then rerun Setup.
- **An organization blocks PowerShell scripts:** follow your organization's policy; Setup does not override managed restrictions.

Background: [Microsoft IAudioClockAdjustment](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-iaudioclockadjustment). The project started from investigating [WMPotify](https://github.com/Ingan121/WMPotify); this package uses a Windows audio approach rather than its internal Spotify player hooks.

## License

[MIT](LICENSE). Spotify, Windhawk, and Node.js retain their own licenses.
