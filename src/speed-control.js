(() => {
  if (location.hostname !== 'xpui.app.spotify.com' || window.top !== window) return;
  window.__spotifyAudioSpeedCleanup?.();
  const endpoint = 'http://127.0.0.1:8758/speed';
  let queued = null, sending = false, timer, closed = false;
  const abort = new AbortController();
  const style = document.createElement('style');
  style.textContent = `
    #spotify-speed-button{border:0;background:none;color:var(--text-subdued,#b3b3b3);font:700 11px sans-serif;font-family:inherit;font-variant-numeric:tabular-nums;min-width:36px;height:32px;padding:0 4px;cursor:pointer;border-radius:4px;flex-shrink:0}
    #spotify-speed-button:hover{color:#fff}#spotify-speed-button[data-active=true]{color:var(--text-positive,#1ed760)}
    #spotify-speed-button:focus-visible,#spotify-speed-panel button:focus-visible,#spotify-speed-range:focus-visible{outline:2px solid #fff;outline-offset:4px}
    #spotify-speed-panel{position:fixed;z-index:2147483647;box-sizing:border-box;width:264px;padding:18px 18px 14px;background:var(--background-elevated-highlight,#282828);color:var(--text-base,#fff);border-radius:8px;box-shadow:0 8px 28px #0009;font:12px sans-serif;font-family:inherit}
    #spotify-speed-panel[hidden]{display:none}#spotify-speed-panel .speed-heading{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px}
    #spotify-speed-value{font-size:22px;font-weight:700;line-height:1.1;font-variant-numeric:tabular-nums}
    #spotify-speed-reset{border:1px solid #ffffff65;border-radius:16px;background:transparent;color:inherit;padding:5px 12px;font:700 12px sans-serif;font-family:inherit;cursor:pointer}
    #spotify-speed-reset:hover{border-color:#fff;background:#ffffff12}
    #spotify-speed-range{appearance:none;-webkit-appearance:none;display:block;box-sizing:border-box;width:100%;height:4px;margin:12px 0 10px;border-radius:4px;cursor:pointer;background:linear-gradient(to right,#1ed760 var(--fill),#ffffff40 var(--fill))}
    #spotify-speed-range::-webkit-slider-thumb{appearance:none;-webkit-appearance:none;width:12px;height:12px;border:0;border-radius:50%;background:#fff;box-shadow:0 1px 4px #0005}
    #spotify-speed-panel .speed-limits{display:flex;justify-content:space-between;color:var(--text-subdued,#b3b3b3);font-variant-numeric:tabular-nums}
    #spotify-speed-status{margin:14px 0 0;color:var(--text-subdued,#b3b3b3);font-size:11px;line-height:1.4;min-height:15px}
    #spotify-speed-status[data-error=true]{color:#f15e6c}
  `;
  document.head.append(style);
  const button = document.createElement('button');
  button.id = 'spotify-speed-button';button.type = 'button';
  button.setAttribute('aria-haspopup', 'dialog');button.setAttribute('aria-controls', 'spotify-speed-panel');
  button.setAttribute('aria-expanded', 'false');
  const panel = document.createElement('div');
  panel.id = 'spotify-speed-panel';panel.hidden = true;panel.setAttribute('role', 'dialog');panel.setAttribute('aria-label', 'Playback speed');
  panel.innerHTML = `<div class="speed-heading"><output id="spotify-speed-value" for="spotify-speed-range">1.00×</output><button id="spotify-speed-reset" type="button" aria-label="Reset playback speed to 1×">1×</button></div><input id="spotify-speed-range" type="range" min="50" max="200" step="1" value="100" aria-label="Playback speed"><div class="speed-limits"><span>0.50×</span><span>2.00×</span></div><p id="spotify-speed-status" role="status" aria-live="polite">Pitch changes with speed.</p>`;
  document.body.append(panel);
  const range = panel.querySelector('input'), value = panel.querySelector('output'), status = panel.querySelector('p');
  function paint(p) {
    range.value = String(p);range.style.setProperty('--fill', `${(p - 50) / 1.5}%`);
    value.textContent = `${(p / 100).toFixed(2)}×`;
    button.textContent = `${(p / 100).toFixed(2).replace(/0+$/, '').replace(/\.$/, '')}×`;
    button.title = `Playback speed: ${(p / 100).toFixed(2)}×`;button.setAttribute('aria-label', button.title);
    button.dataset.active = String(p !== 100);range.setAttribute('aria-valuetext', `${(p / 100).toFixed(2)} times normal speed`);
  }
  function failed() {
    if (closed) return;
    status.dataset.error = 'true';status.textContent = 'Speed control unavailable. Check Windhawk.';
  }
  async function read() {
    try {
      const response = await fetch(endpoint, { signal: AbortSignal.timeout(1500) });
      if (!response.ok) throw new Error();
      const state = await response.json();
      if (!Number.isInteger(state.percent) || state.percent < 50 || state.percent > 200 || !state.ok) throw new Error();
      if (!sending && queued === null && !closed) paint(state.percent);
      if (!closed) { status.dataset.error = 'false';status.textContent = 'Pitch changes with speed.'; }
    } catch { failed(); }
  }
  async function send() {
    if (sending || closed) return;
    sending = true;
    try {
      while (queued !== null && !closed) {
        const next = queued;queued = null;
        const response = await fetch(`${endpoint}?percent=${next}`, { method: 'POST', signal: AbortSignal.timeout(1500) });
        if (!response.ok || !(await response.json()).ok) throw new Error();
        status.dataset.error = 'false';status.textContent = 'Pitch changes with speed.';
      }
    } catch { queued = null;failed(); }
    finally { sending = false; }
  }
  function change(p) {paint(p);queued = p;clearTimeout(timer);timer = setTimeout(send, 35);}
  function place() {
    if (panel.hidden || !button.isConnected) return;
    const r = button.getBoundingClientRect();
    panel.style.left = `${Math.max(8, Math.min(innerWidth - 272, r.left + r.width / 2 - 132))}px`;
    panel.style.bottom = `${innerHeight - r.top + 12}px`;
  }
  function close(focus = false) {panel.hidden = true;button.setAttribute('aria-expanded', 'false');if (focus) button.focus();}
  button.addEventListener('click', () => {
    if (!panel.hidden) { close();return; }
    panel.hidden = false;button.setAttribute('aria-expanded', 'true');place();range.focus();read();
  });
  range.addEventListener('input', () => change(Number(range.value)));
  panel.querySelector('button').addEventListener('click', () => change(100));
  document.addEventListener('pointerdown', e => {if (!panel.contains(e.target) && !button.contains(e.target)) close();}, { signal: abort.signal });
  document.addEventListener('keydown', e => {if (e.key === 'Escape' && !panel.hidden) {e.preventDefault();close(true);}}, { signal: abort.signal });
  window.addEventListener('resize', place, { signal: abort.signal });window.addEventListener('focus', read, { signal: abort.signal });
  function mount() {const lyrics = document.querySelector('[data-testid="lyrics-button"]');if (lyrics && lyrics.previousElementSibling !== button) lyrics.before(button);}
  const observer = new MutationObserver(mount);observer.observe(document.body, { childList: true, subtree: true });
  paint(100);mount();read();
  window.__spotifyAudioSpeedCleanup = () => {
    closed = true;observer.disconnect();abort.abort();clearTimeout(timer);button.remove();panel.remove();style.remove();delete window.__spotifyAudioSpeedCleanup;
  };
})()
