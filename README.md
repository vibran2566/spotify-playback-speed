<div align="center">

# Spotify Playback Speed

Speed and pitch control for the Spotify Windows desktop app, as a single [Windhawk](https://github.com/ramensoftware/windhawk) mod.

<img width="291" height="215" alt="Speed slider open above Spotify's playback controls" src="https://github.com/user-attachments/assets/32410baf-9d38-4c78-be93-4146eab4f265" />

**0.50x – 2.00x** · one-click **1x** reset · sits next to the Lyrics button

[**Get the mod**](spotify-playback-speed.wh.cpp) · [Known limits](#known-limits) · [Troubleshooting](#troubleshooting)

</div>

> [!WARNING]
> Experimental. The progress bar and synced lyrics don't follow the changed speed yet.

## Install

Nothing to download or run. You paste one file into Windhawk, which compiles it.

1. Install **Windhawk 2**: [download windhawk_setup.exe](https://github.com/ramensoftware/windhawk/releases/download/2.0.0-alpha.8/windhawk_setup.exe). windhawk.net still offers 1.x, which won't work.
2. Open [spotify-playback-speed.wh.cpp](spotify-playback-speed.wh.cpp) and click **Copy raw file** (the copy icon above the code).
3. In Windhawk, click **Create a new mod**. If it asks for development tools, click **Install development tools** first.
4. Select all of the example code, paste over it, then click **Compile mod** and **Exit editing mode**.
5. Fully close Spotify (including its tray icon) and open it again.

The speed button appears just left of **Lyrics**.

> [!TIP]
> **To update**, open the mod in Windhawk, click **Edit**, paste the new version over the old code and click **Compile mod**. Then restart Spotify. Your speed setting is kept.

## Requirements

- Windows x64 with the Spotify desktop app
- [Windhawk 2](https://github.com/ramensoftware/windhawk/releases) with development tools

## Known limits

- Spotify updates may move the Lyrics button or change the audio engine.
- The audio buffer is raised to 250 ms, which adds a little latency.

## Uninstall

In Windhawk, open **Spotify Playback Speed** and click **Remove mod**, then restart Spotify. To turn it off for a while, disable the mod instead.

## Troubleshooting

<details>
<summary><b>No speed button</b></summary>
<br>

Check that the mod is enabled in Windhawk, then fully close Spotify, including its tray icon, and open it again. The mod adds the button while Spotify starts. A Spotify update may also have moved the Lyrics button; please open an issue with your Spotify version.

</details>
<br>

<details>
<summary><b>"Speed control unavailable"</b></summary>
<br>

Fully close and reopen Spotify. The mod has to load before Spotify creates its audio stream. If it still shows, another program may be using local port 8758.

</details>
<br>

<details>
<summary><b>Crackling audio</b></summary>
<br>

Go back to 1x and open an issue with your Spotify version, Windows version, audio device, and the rates that crackle. The larger buffer fixed this on the test machine, but it may not on every device.

</details>
<br>

<details>
<summary><b>Compiling fails</b></summary>
<br>

Make sure you're on Windhawk 2 with development tools installed, and that you replaced all of the example code. Then compile again.

</details>

## Credits & license

Started from investigating [WMPotify](https://github.com/Ingan121/WMPotify). Independent project, not affiliated with Spotify.

[MIT](LICENSE). Spotify and Windhawk keep their own licenses.
