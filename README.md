<div align="center">

# Spotify Playback Speed

Speed and pitch control for the Spotify Windows desktop app.

<img width="291" height="215" alt="Speed slider open above Spotify's playback controls" src="https://github.com/user-attachments/assets/32410baf-9d38-4c78-be93-4146eab4f265" />

**0.50x – 2.00x** · one-click **1x** reset · sits next to the Lyrics button

[**Download**](https://github.com/vibran2566/spotify-playback-speed/releases) · [Known limits](#known-limits) · [Troubleshooting](#troubleshooting)

</div>

> [!WARNING]
> Experimental. The progress bar and synced lyrics don't follow the changed speed yet.

## Install

1. Open [Releases](https://github.com/vibran2566/spotify-playback-speed/releases), download the `.zip` under **Assets** of the newest release, and extract it.
2. Double-click **Setup.cmd**.
3. If Windhawk's installer opens, finish it with **Development tools** included.
4. Approve Windows' administrator permission request for the Windhawk mod, if shown.
5. Open **Spotify Playback Speed** from your desktop or Start menu.

Start playback, then click the speed button just left of **Lyrics**.

Setup stays in your user account. With a standard Windhawk installation, only the mod operation requests administrator permission. Portable Windhawk installations run without elevation. If you cancel the permission request, Setup reports the failure and can be run again.

> [!TIP]
> **To update**, download a new ZIP and run Setup again. Your speed setting is kept.

New installations use `%LOCALAPPDATA%\Programs\Spotify Playback Speed`. Upgrades keep an existing installation in place and replace the older shortcut names.

<details>
<summary>Spotify or Windhawk installed somewhere custom?</summary>
<br>

Run setup from PowerShell with explicit paths:

```powershell
.\src\Install-Spotify-Playback-Speed.ps1 `
  -SpotifyPath 'D:\Apps\Spotify\Spotify.exe' `
  -WindhawkCli 'D:\Apps\Windhawk\windhawk-cli.exe'
```

</details>

## Requirements

- Windows x64 with the Spotify desktop app
- [Windhawk](https://windhawk.net/) 2.x and Node.js 22+. Setup reuses them if they're already installed.

## Known limits

- Spotify updates may break the button placement or the audio hook.
- The audio buffer is raised to 250 ms, which adds a little latency.
- The helper keeps running after Spotify closes. Reopen Spotify with the **Spotify Playback Speed** shortcut so the control comes back.

## Uninstall

Remove **Spotify Playback Speed** from Windows' installed apps. This stops all helpers. Spotify and Windhawk stay installed. Then fully close and reopen Spotify.

Standard Windhawk installations may request administrator permission to remove the mod. If Windhawk or the mod was already removed, app cleanup still finishes. Cancelling an administrator request leaves the app registered so you can retry removal.

To turn it off temporarily, disable **Spotify Playback Speed** in Windhawk.

## Troubleshooting

<details>
<summary><b>No speed button</b></summary>
<br>

Open Spotify with the **Spotify Playback Speed** shortcut. If startup fails, read its error message. Logs are in `.runtime` inside the installation folder (normally `%LOCALAPPDATA%\Programs\Spotify Playback Speed`). A Spotify UI update may also have moved the Lyrics button.

</details>
<br>

<details>
<summary><b>Speed control unavailable</b></summary>
<br>

Check that Windhawk and the mod are enabled, then fully close Spotify and reopen it with the shortcut. The mod has to load before Spotify creates its audio stream.

</details>
<br>

<details>
<summary><b>Port 9222 belongs to another debugger</b></summary>
<br>

Close that debugger before launching. The script won't take over another debugger session.

</details>
<br>

<details>
<summary><b>Crackling audio</b></summary>
<br>

Go back to 1x and open an issue with your Spotify version, Windows version, audio device, and the rates that crackle. The larger buffer fixed this on the test machine, but it may not on every device.

</details>
<br>

<details>
<summary><b>Setup can't find Windhawk development tools</b></summary>
<br>

Add **Development tools** in Windhawk, then run Setup again.

</details>
<br>

<details>
<summary><b>Setup can't download dependencies</b></summary>
<br>

Check your internet connection. Or install Windhawk 2 with Development tools and Node.js 22+ yourself, then run Setup again.

</details>

## Credits & license

Started from investigating [WMPotify](https://github.com/Ingan121/WMPotify). Independent project, not affiliated with Spotify.

[MIT](LICENSE). Spotify, Windhawk, and Node.js keep their own licenses.
