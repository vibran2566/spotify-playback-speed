# Spotify Audio Speed

Experimental speed and pitch control for the Spotify Windows desktop app. A button next to Lyrics opens a **0.50x–2.00x** slider with a **1x reset**. Changes apply live after initial setup.

**Status: alpha, ready for technical users to try, not a stable release.** The original build was tested on Windows 11 x64 with Spotify 1.3.8.620 and Windhawk 2.0. One user confirmed clean music playback at 1.25x. Version 0.3.2 packages that implementation with portable paths and a launcher for Store and regular Spotify installations; other installations still need testing.

## Known limits

- Speed and pitch change together. This does not preserve pitch.
- **Progress bar timing and synchronized lyric scrolling do not account for the changed speed yet.**
- Spotify updates may break the button placement or audio integration. Only the version above has been exercised.
- The audio buffer is increased to 250 ms, which adds latency. Other audio devices, full-range listening, sleep/wake, and reboot recovery are not verified.
- Shared-mode audio only; exclusive-mode streams are left alone.
- The UI uses Spotify's local Chromium debugger. The launcher requests loopback binding on port 9222; the speed bridge binds to 127.0.0.1:8758. The debugger exposes more than speed control to local software. Do not expose either port to your network.
- The helper remains running while Spotify is closed. Use this project's launcher when reopening Spotify so the control can return.

This is an independent project, not affiliated with Spotify. No Spotify application files, recordings, or proprietary binaries are distributed.

## Requirements

- Windows x64 with Spotify desktop installed.
- [Windhawk](https://windhawk.net/) 2.0, running with its compiler and command line interface available.
- [Node.js](https://nodejs.org/) 22 or newer, available as `node.exe` in PATH.

No npm dependencies or npm installation are needed.

## Install and start

Clone or download this repository and open PowerShell in its directory. Keep the project files in that directory while using the helper.

Find `windhawk-cli.exe` in your Windhawk installation. For a per-user portable installation, the commands look like this; adjust `$cli` to your installation:

```powershell
$cli = "$env:LOCALAPPDATA\Programs\Windhawk\windhawk-cli.exe"
& $cli mod install --file "$PWD\spotify-audio-speed.wh.cpp" --disabled
# Stop here if compilation failed. Enable only after reviewing the source.
& $cli mod enable local@spotify-audio-speed
.\Start-Spotify-Speed.ps1
```

The launcher may close and reopen Spotify once to enable the local debugger and create a new audio stream. Subsequent slider adjustments require no restart. Start playback, then click the speed button immediately left of Lyrics. The **1x** button resets the rate.

The launcher detects common regular and Microsoft Store installation paths. For another location:

```powershell
.\Start-Spotify-Speed.ps1 -SpotifyPath 'D:\Apps\Spotify\Spotify.exe'
```

You can create a shortcut targeting `powershell.exe` with arguments `-NoProfile -File "<full path>\Start-Spotify-Speed.ps1"`. Keep Windhawk running.

## Stop and remove

1. Disable **Spotify Audio Speed** in Windhawk (or run `& $cli mod disable local@spotify-audio-speed`). This restores held audio streams to 1x.
2. Stop this repository's UI helper, using PowerShell from the repository directory:

   ```powershell
   $helper = Join-Path $PWD 'keep-speed-control.mjs'
   Get-CimInstance Win32_Process -Filter "name='node.exe'" |
       Where-Object { $_.CommandLine -and $_.CommandLine.Contains($helper) } |
       ForEach-Object { Stop-Process -Id $_.ProcessId }
   ```

3. Fully close Spotify and reopen it using its ordinary shortcut to remove the injected UI and close the debugger.
4. Optionally remove the mod in Windhawk, then delete the project directory.

## Troubleshooting

- **No speed button:** use the project launcher, wait for Spotify to finish loading, and check `.runtime/host-errors.log`. A Spotify UI update may have moved the Lyrics button.
- **Speed control unavailable:** confirm Windhawk and the mod are enabled, then fully close and reopen Spotify with the launcher. The audio stream must be created after the mod is loaded.
- **Port 9222 belongs to another debugger:** close that debugger before launching. The script refuses to take over another debugger session.
- **Crackling:** return to 1x. Report your Spotify version, Windows version, audio device, and the rates affected. Earlier development builds crackled; the larger buffer helped on the tested machine, but is not a guarantee for every device.
- **Cannot run PowerShell scripts:** follow your machine's script execution policy or run the launcher through an approved shell. This project does not change that policy.

## How it works

The Windhawk mod hooks Spotify's Windows shared audio client, enables `AUDCLNT_STREAMFLAGS_RATEADJUST`, and performs `IAudioClockAdjustment::SetSampleRate` calls on a COM worker thread. A small HTTP bridge accepts only speed operations on loopback, validating Host, browser Origin, method, route and integer range. There is no authentication for other local software.

The Node helper connects to Spotify's local debugger and injects `speed-control.js`. It restores the UI across page reloads without native CEF hooks. The mod applies to the main Spotify process and stores the selected percentage through Windhawk.

Background: [Microsoft IAudioClockAdjustment](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-iaudioclockadjustment). The project started from investigating [WMPotify](https://github.com/Ingan121/WMPotify); this package uses a Windows audio approach rather than its internal Spotify player hooks.

## Development and checks

```powershell
npm run check
npm test
```

These validate JavaScript syntax and exercise the launcher with mocked process and debugger operations. They do not launch Spotify or change audio.

For native checks, use Windhawk to compile the source with the mod disabled in a separate test installation. `test-audio-backend.cpp` also exercises the native worker in a standalone process without injection. With an x64 MinGW-compatible Clang toolchain:

```powershell
clang++ --target=x86_64-w64-mingw32 -std=c++23 -O2 -static -DWIN32_LEAN_AND_MEAN -D_WIN32_WINNT=0x0A00 test-audio-backend.cpp -o test-audio-backend.exe -lole32 -luuid -lws2_32
.\test-audio-backend.exe
```

This plays a quiet test tone. For optional speaker loopback quality checks, install `numpy` and `PyAudioWPatch`, then run `python test-audio-quality.py`. It reads speaker output, never a microphone. Close other audio sources first. Generated results are ignored by Git.

`node test-speed-ui.mjs` tests the UI against a mock bridge in a real Spotify debugger session. It requires port 8758 to be free and can replace the current control; stop the helper and disable the real mod first. It does not test real Spotify audio.

## Before a stable release

- Synchronize the progress bar and lyrics with the changed rate.
- Test clean setup on a second PC, regular Spotify installations, additional devices, and Spotify versions.
- Verify the full speed range, track changes, seek/pause behavior, sleep/wake, reboot, and native unload under load.
- Harden audio-client lifetime tracking: the current client-rate map retains entries across Stop for later Start.

## License

[MIT](LICENSE). Source only; Spotify, Windhawk, Node.js, and optional test dependencies retain their own licenses.
