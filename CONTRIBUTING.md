# Contributing

This project is an experimental Windows x64 alpha. Keep changes small and include the Spotify version, Windows version, audio device, and reproduction steps when reporting a bug.

Run `npm run check` and `npm test` before sending a change. Compile native changes with Windhawk while disabled before loading them. Audio behavior needs a real listening check; a timing measurement or successful API call alone does not establish clean playback.

Do not commit recordings, Spotify binaries, logs, user configuration, or generated executables. The tests that launch a test player or connect to Spotify are opt-in; describe exactly which checks you ran.

The next priorities are progress/lyrics timing, clean installation on another PC, and safe native audio-client lifetime handling. Contributions are under the MIT license.
