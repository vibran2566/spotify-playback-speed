"""Exercise the standalone backend and inspect speaker loopback; never opens a mic."""
import json
import subprocess
from pathlib import Path

import numpy as np
import pyaudiowpatch as pa

root = Path(__file__).resolve().parent
with pa.PyAudio() as audio:
    device = audio.get_default_wasapi_loopback()
    rate = int(device['defaultSampleRate'])
    channels = int(device['maxInputChannels'])
    with audio.open(format=pa.paFloat32, channels=channels, rate=rate, input=True,
                    input_device_index=device['index'], frames_per_buffer=512) as stream:
        process = subprocess.Popen([str(root / 'test-audio-backend.exe')], stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True)
        try:
            # Loopback stops delivering when Windows has no active audio. Finish
            # capture while the ten-second test tone is still running.
            chunks = [stream.read(512, exception_on_overflow=True) for _ in range(int(rate * 9 / 512))]
            log, _ = process.communicate(timeout=5)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
assert process.returncode == 0, log
assert 'PASS: worker live changes and cleanup' in log, log
samples = np.frombuffer(b''.join(chunks), dtype=np.float32).reshape(-1, channels).mean(axis=1)
windows = []
for start in range(0, len(samples) - rate // 5, rate // 5):
    block = samples[start:start + rate // 5]
    spectrum = np.abs(np.fft.rfft(block * np.hanning(len(block))))
    peak = int(np.argmax(spectrum)) * rate / len(block)
    if np.sqrt(np.mean(block ** 2)) < 0.001:
        continue
    quiet = np.abs(block) < 0.0001
    edges = np.diff(np.r_[False, quiet, False].astype(int))
    runs = np.flatnonzero(edges == -1) - np.flatnonzero(edges == 1)
    windows.append({'atSeconds': round(start / rate, 2), 'peakHz': peak,
                    'longestQuietMs': float(max(runs, default=0) * 1000 / rate)})
for expected in [220, 440, 550, 880]:
    assert any(abs(w['peakHz'] - expected) <= 5 for w in windows), f'Missing {expected} Hz'
# Ignore rate transition windows; only evaluate blocks dominated by one expected tone.
assert len(windows) >= 40, 'Too little sustained output'
# The first and last windows straddle starting/stopping the test player.
steady = [w for w in windows[1:-1] if min(abs(w['peakHz'] - f) for f in [220, 440, 550, 880]) <= 5]
assert steady, 'No measurable output'
result = {'scope': 'Independent test player, not Spotify', 'log': log,
          'windows': windows, 'longestQuietMs': max(w['longestQuietMs'] for w in steady)}
(root / 'audio-backend-test-results.json').write_text(json.dumps(result, indent=2))
print(log)
print(f"Detected all four expected tone frequencies; longest quiet run: {result['longestQuietMs']:.2f} ms")
# This detects dropouts, not every possible audible defect.
assert result['longestQuietMs'] < 3, 'Output contains an unexpected gap'
