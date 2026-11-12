// UI-only test: the temporary bridge stores values in memory, without changing audio.
import { createServer } from 'node:http';
import { readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
let current = 100;
const received = [];
const server = createServer((req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1:8758');
  if (req.method === 'POST') { current = Number(url.searchParams.get('percent')); received.push(current); }
  res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': 'https://xpui.app.spotify.com', 'Access-Control-Allow-Private-Network': 'true' });
  res.end(JSON.stringify({ percent: current, activeStreams: 1, ok: true }));
});
await new Promise((resolve, reject) => { server.once('error', reject);server.listen(8758, '127.0.0.1', resolve); });
let socket;
try {
  const pages = await fetch('http://127.0.0.1:9222/json/list').then(r => r.json());
  const target = pages.find(t => t.type === 'page' && new URL(t.url).hostname === 'xpui.app.spotify.com');
  assert(target, 'Spotify debugger is required for the UI-only test');
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.addEventListener('open', resolve, { once: true });socket.addEventListener('error', reject, { once: true }); });
  let id = 0;
  const pending = new Map();
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data), waiter = pending.get(message.id);
    if (!waiter) return;
    pending.delete(message.id);clearTimeout(waiter.timeout);
    if (message.error) waiter.reject(new Error(JSON.stringify(message.error)));
    else waiter.resolve(message.result);
  });
  const call = (method, params) => new Promise((resolve, reject) => {
    const number = ++id;
    const timeout = setTimeout(() => { pending.delete(number);reject(new Error('Debugger timed out')); }, 10000);
    pending.set(number, { resolve, reject, timeout });socket.send(JSON.stringify({ id: number, method, params }));
  });
  const evaluate = async expression => {
    const reply = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    if (reply.exceptionDetails) throw new Error(JSON.stringify(reply.exceptionDetails));
    return reply.result.value;
  };
  try {
    const source = readFileSync(new URL('speed-control.js', import.meta.url), 'utf8');
    await evaluate(source);
    await new Promise(r => setTimeout(r, 400));
    const placement = await evaluate(`(() => {const l=document.querySelector('[data-testid="lyrics-button"]');return {left:l.previousElementSibling.id,count:document.querySelectorAll('#spotify-speed-button').length};})()`);
    assert.equal(placement.left, 'spotify-speed-button');assert.equal(placement.count, 1);
    await evaluate(`document.querySelector('#spotify-speed-button').click();`);
    const opening = await evaluate(`({open:!document.querySelector('#spotify-speed-panel').hidden,focused:document.activeElement.id,min:document.querySelector('#spotify-speed-range').min,max:document.querySelector('#spotify-speed-range').max})`);
    assert.equal(opening.open, true);assert.equal(opening.focused, 'spotify-speed-range');
    assert.equal(opening.min, '50');assert.equal(opening.max, '200');
    await evaluate(`(() => {const r=document.querySelector('#spotify-speed-range');for(const p of [50,125,200,175]){r.value=p;r.dispatchEvent(new Event('input',{bubbles:true}));}})()`);
    await new Promise(r => setTimeout(r, 250));
    assert.equal(current, 175, 'Dragging must send the latest value');
    const screenshot = await call('Page.captureScreenshot', { format: 'png' });
    writeFileSync(new URL('speed-control-preview.png', import.meta.url), Buffer.from(screenshot.data, 'base64'));
    await evaluate(`document.querySelector('#spotify-speed-reset').click()`);
    await new Promise(r => setTimeout(r, 250));assert.equal(current, 100, 'Reset must send 1x');
    const reset = await evaluate(`({value:document.querySelector('#spotify-speed-range').value,label:document.querySelector('#spotify-speed-button').textContent,error:document.querySelector('#spotify-speed-status').dataset.error})`);
    assert.equal(reset.value, '100');assert.equal(reset.label, '1×');assert.equal(reset.error, 'false');
    await evaluate(`document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))`);
    const dismissed = await evaluate(`({hidden:document.querySelector('#spotify-speed-panel').hidden,focused:document.activeElement.id})`);
    assert.equal(dismissed.hidden, true);assert.equal(dismissed.focused, 'spotify-speed-button');
    await evaluate(source);
    assert.equal(await evaluate(`document.querySelectorAll('#spotify-speed-button').length`), 1, 'Reinjection must not duplicate controls');
    console.log(JSON.stringify({ placement, opening, received, reset, dismissed, audioChanged: false }, null, 2));
  } finally {
    await evaluate(`window.__spotifyAudioSpeedCleanup?.()`);
  }
} finally {
  socket?.close();server.closeAllConnections();await new Promise(resolve => server.close(resolve));
}
