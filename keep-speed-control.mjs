// Keeps the control mounted across Spotify page reloads, without native CEF hooks.
import { readFileSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
const source = readFileSync(new URL('speed-control.js', import.meta.url), 'utf8');
const runtime = new URL('.runtime/', import.meta.url);
const readyFile = new URL('ready.json', runtime);
mkdirSync(runtime, {recursive:true});
let status;
function report(message) { if (message !== status) {status=message;console.log(message);} }
async function attach(target) {
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  try {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Debugger timeout')), 3000);
      socket.addEventListener('error', () => { clearTimeout(timeout);reject(new Error('Debugger unavailable')); }, {once:true});
      socket.addEventListener('message', event => {
        const reply=JSON.parse(event.data);
        if(reply.id!==1)return;
        clearTimeout(timeout);
        if(reply.error || reply.result?.exceptionDetails || reply.result?.result?.value!==true)reject(new Error('Waiting for Spotify player controls'));
        else resolve();
      });
      socket.addEventListener('open', () => socket.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{
        expression:`(()=>{if(typeof window.__spotifyAudioSpeedCleanup!=='function'||!document.querySelector('#spotify-speed-button')){${source}\n}return !!document.querySelector('#spotify-speed-button');})()`,returnByValue:true
      }})), {once:true});
    });
  } finally {socket.close();}
}
for(;;) {
  try {
    const targets=await fetch('http://127.0.0.1:9222/json/list',{signal:AbortSignal.timeout(2000)}).then(r=>r.json());
    const target=targets.find(t=>t.type==='page' && new URL(t.url).hostname==='xpui.app.spotify.com');
    if(!target)throw new Error('Waiting for Spotify player');
    await attach(target);writeFileSync(readyFile,JSON.stringify({timestamp:Date.now()}));report('Speed control attached');
  } catch(error) {rmSync(readyFile,{force:true});report(error.message==='Waiting for Spotify player controls'?error.message:'Waiting for Spotify local debugger');}
  await new Promise(resolve=>setTimeout(resolve,2000));
}
