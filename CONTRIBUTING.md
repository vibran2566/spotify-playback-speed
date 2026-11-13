# Contributing

This project is an experimental Windows x64 alpha. Keep changes small and include the Spotify version, Windows version, audio device, and reproduction steps when reporting a bug.

Check JavaScript syntax with `node --check speed-control.js` and `node --check keep-speed-control.mjs`. Compile native changes with Windhawk while disabled before loading them. Audio behavior needs a real listening check; a timing measurement or successful API call alone does not establish clean playback.

Do not commit recordings, Spotify binaries, logs, user configuration, or generated executables. Describe which checks you ran and any audio or compatibility limits you observed.

The next priorities are progress/lyrics timing, clean installation on another PC, and safe native audio-client lifetime handling. Contributions are under the MIT license.
