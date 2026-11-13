// ==WindhawkMod==
// @id spotify-playback-speed
// @name Spotify Playback Speed
// @description Adds a 0.5x-2x speed slider next to Spotify's Lyrics button
// @version 0.4.0
// @author vibran
// @github https://github.com/vibran2566
// @homepage https://github.com/vibran2566/spotify-playback-speed
// @license MIT
// @include Spotify.exe
// @architecture x86-64
// @compilerOptions -DWIN32_LEAN_AND_MEAN -lole32 -luuid -lws2_32
// ==/WindhawkMod==

// ==WindhawkModReadme==
/*
# Spotify Playback Speed
Adds a speed button next to **Lyrics** in the Spotify desktop app. Click it for a
0.50x-2.00x slider and a 1x reset. Pitch changes with speed.

After installing or updating the mod, fully close Spotify and open it again.

Known limits: the progress bar and synced lyrics don't follow the changed speed,
and Spotify updates may move the Lyrics button.
*/
// ==/WindhawkModReadme==

// ==WindhawkModSettings==
/*
- speedPercent: 100
  $name: Playback speed (%)
  $description: 50 to 200. Changes apply live. Pitch changes too.
*/
// ==/WindhawkModSettings==

#include <winsock2.h>
#include <windows.h>
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <atomic>
#include <algorithm>
#include <charconv>
#include <deque>
#include <map>
#include <mutex>
#include <string>

constexpr unsigned short speedPort=8758;
std::atomic<int> percent{100};
std::atomic<bool> stopping{false};
std::atomic<HRESULT> lastResult{S_OK};
HANDLE worker=nullptr;

void Log(const char* text) {
    Wh_Log(L"%S",text);
}

bool ValidPercent(int value) {return value>=50 && value<=200;}
void SetPercent(int value) {
    if(!ValidPercent(value)) return;
    percent=value;
    Wh_SetIntValue(L"liveSpeedPercent",value);
}

struct Command {IAudioClient* id;IStream* stream;DWORD rate;};
std::mutex pendingMutex;
std::deque<Command> pending;
// shortcut: rate entries survive Stop for later Start; add Release tracking if clients become numerous.
std::map<IAudioClient*,DWORD> clientRates;

void QueueClient(IAudioClient* client,DWORD rate) {
    IStream* stream=nullptr;
    HRESULT result=CoMarshalInterThreadInterfaceInStream(__uuidof(IAudioClient),client,&stream);
    if(FAILED(result)) {lastResult=result;Log("Could not marshal audio client\r\n");return;}
    std::lock_guard lock(pendingMutex);
    pending.push_back({client,stream,rate});
}

using InitFn=HRESULT (STDMETHODCALLTYPE*)(IAudioClient*,AUDCLNT_SHAREMODE,DWORD,REFERENCE_TIME,REFERENCE_TIME,const WAVEFORMATEX*,LPCGUID);
using ClientFn=HRESULT (STDMETHODCALLTYPE*)(IAudioClient*);
InitFn initOriginal;
ClientFn startOriginal,stopOriginal;

HRESULT STDMETHODCALLTYPE InitHook(IAudioClient* client,AUDCLNT_SHAREMODE mode,DWORD flags,
    REFERENCE_TIME duration,REFERENCE_TIME periodicity,const WAVEFORMATEX* format,LPCGUID session) {
    if(mode!=AUDCLNT_SHAREMODE_SHARED || !format || (flags&AUDCLNT_STREAMFLAGS_LOOPBACK))
        return initOriginal(client,mode,flags,duration,periodicity,format,session);
    // Give the producer room to tolerate faster consumption and scheduler jitter.
    auto buffering=std::max(duration,REFERENCE_TIME(2500000));
    HRESULT result=initOriginal(client,mode,flags|AUDCLNT_STREAMFLAGS_RATEADJUST,buffering,periodicity,format,session);
    if(FAILED(result)) return initOriginal(client,mode,flags,duration,periodicity,format,session);
    IAudioRenderClient* render=nullptr;
    if(SUCCEEDED(client->GetService(__uuidof(IAudioRenderClient),reinterpret_cast<void**>(&render)))) {
        render->Release();
        {std::lock_guard lock(pendingMutex);clientRates[client]=format->nSamplesPerSec;}
        QueueClient(client,format->nSamplesPerSec);
    }
    return result;
}
HRESULT STDMETHODCALLTYPE StartHook(IAudioClient* client) {
    DWORD rate=0;
    {std::lock_guard lock(pendingMutex);auto it=clientRates.find(client);if(it!=clientRates.end())rate=it->second;}
    if(rate) QueueClient(client,rate);
    return startOriginal(client);
}
HRESULT STDMETHODCALLTYPE StopHook(IAudioClient* client) {
    HRESULT result=stopOriginal(client);
    if(SUCCEEDED(result)) {std::lock_guard lock(pendingMutex);pending.push_back({client,nullptr,0});}
    return result;
}

struct Clock {IAudioClockAdjustment* adjustment;DWORD rate;};
void Apply(Clock clock,int value) {
    HRESULT result=clock.adjustment->SetSampleRate(clock.rate*value/100.0f);
    lastResult=result;
    char message[128];
    wsprintfA(message,"Live audio rate %d percent; HRESULT=%08lx\r\n",value,result);
    Log(message);
}

std::string State(size_t active) {
    return "{\"percent\":"+std::to_string(percent.load())+",\"activeStreams\":"+std::to_string(active)+
        ",\"ok\":"+(SUCCEEDED(lastResult.load())?"true":"false")+"}";
}

void Reply(SOCKET client,int status,const std::string& body) {
    std::string response="HTTP/1.1 "+std::to_string(status)+(status==200?" OK":" Error")+
        "\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: https://xpui.app.spotify.com"
        "\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type"
        "\r\nAccess-Control-Allow-Private-Network: true\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: "+
        std::to_string(body.size())+"\r\n\r\n"+body;
    size_t offset=0;
    while(offset<response.size()) {int n=send(client,response.data()+offset,int(response.size()-offset),0);if(n<=0)break;offset+=n;}
}

void Serve(SOCKET client,std::map<IAudioClient*,Clock>& clocks) {
    DWORD timeout=300;
    setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,reinterpret_cast<char*>(&timeout),sizeof(timeout));
    setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,reinterpret_cast<char*>(&timeout),sizeof(timeout));
    std::string request;
    char buffer[1024];
    const auto deadline=GetTickCount64()+1000;
    while(request.find("\r\n\r\n")==std::string::npos && request.size()<8192 && GetTickCount64()<deadline) {
        int n=recv(client,buffer,sizeof(buffer),0);if(n<=0)break;request.append(buffer,n);
    }
    std::string lower=request;
    for(char& c:lower) if(c>='A' && c<='Z') c+=32;
    auto header=[&](const char* name) {
        auto pos=lower.find(std::string("\r\n")+name+": ");
        if(pos==std::string::npos) return std::string();
        pos+=strlen(name)+4;
        return request.substr(pos,request.find("\r\n",pos)-pos);
    };
    auto origin=header("origin");
    if(header("host")!="127.0.0.1:8758" || (!origin.empty() && origin!="https://xpui.app.spotify.com")) {
        Reply(client,403,"{}");return;
    }
    if(request.starts_with("OPTIONS /speed ")) {Reply(client,200,"{}");return;}
    if(request.starts_with("GET /speed ")) {Reply(client,200,State(clocks.size()));return;}
    const std::string prefix="POST /speed?percent=";
    if(!request.starts_with(prefix)) {Reply(client,404,"{}");return;}
    auto end=request.find(' ',prefix.size());
    if(end==std::string::npos) {Reply(client,400,"{}");return;}
    int value=0;
    auto parsed=std::from_chars(request.data()+prefix.size(),request.data()+end,value);
    if(parsed.ec!=std::errc() || parsed.ptr!=request.data()+end || !ValidPercent(value)) {Reply(client,400,"{}");return;}
    SetPercent(value);
    for(auto& [id,clock]:clocks) Apply(clock,value);
    Reply(client,200,State(clocks.size()));
}

DWORD WINAPI Worker(void*) {
    if(FAILED(CoInitializeEx(nullptr,COINIT_MULTITHREADED))) return 1;
    WSADATA data;
    const bool socketsReady=WSAStartup(MAKEWORD(2,2),&data)==0;
    SOCKET listener=socketsReady?socket(AF_INET,SOCK_STREAM,IPPROTO_TCP):INVALID_SOCKET;
    sockaddr_in address{};address.sin_family=AF_INET;address.sin_port=htons(speedPort);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(listener!=INVALID_SOCKET && (bind(listener,reinterpret_cast<sockaddr*>(&address),sizeof(address)) || listen(listener,4))) {
        closesocket(listener);listener=INVALID_SOCKET;Log("Speed control port unavailable\r\n");
    }
    std::map<IAudioClient*,Clock> clocks;
    int applied=percent.load();
    auto drain=[&]() {
        std::deque<Command> queue;
        {std::lock_guard lock(pendingMutex);queue.swap(pending);}
        for(auto command:queue) {
            auto old=clocks.find(command.id);
            if(old!=clocks.end()) {old->second.adjustment->Release();clocks.erase(old);}
            if(!command.stream) continue;
            IAudioClient* client=nullptr;
            HRESULT result=CoGetInterfaceAndReleaseStream(command.stream,__uuidof(IAudioClient),reinterpret_cast<void**>(&client));
            if(SUCCEEDED(result)) {
                IAudioClockAdjustment* adjustment=nullptr;
                result=client->GetService(__uuidof(IAudioClockAdjustment),reinterpret_cast<void**>(&adjustment));
                if(SUCCEEDED(result)) {clocks[command.id]={adjustment,command.rate};Apply(clocks[command.id],percent.load());}
                client->Release();
            }
            if(FAILED(result)) {lastResult=result;Log("Audio control unavailable\r\n");}
        }
    };
    while(!stopping.load()) {
        drain();
        if(applied!=percent.load()) {applied=percent.load();for(auto& [id,clock]:clocks)Apply(clock,applied);}
        if(listener==INVALID_SOCKET) {Sleep(20);continue;}
        fd_set reads;FD_ZERO(&reads);FD_SET(listener,&reads);timeval timeout{0,20000};
        if(select(0,&reads,nullptr,nullptr,&timeout)>0) {
            SOCKET client=accept(listener,nullptr,nullptr);
            if(client!=INVALID_SOCKET) {Serve(client,clocks);closesocket(client);applied=percent.load();}
        }
    }
    drain();
    for(auto& [id,clock]:clocks) {Apply(clock,100);clock.adjustment->Release();}
    if(listener!=INVALID_SOCKET)closesocket(listener);
    if(socketsReady)WSACleanup();
    CoUninitialize();
    return 0;
}

// The slider UI. It talks to the speed API above on 127.0.0.1:8758.
constexpr char16_t speedControlScript[]=uR"js((() => {
  if (location.hostname !== 'xpui.app.spotify.com' || window.top !== window || window.__spotifyPlaybackSpeedLoaded) return;
  window.__spotifyPlaybackSpeedLoaded = true;
  const start = () => {
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
    status.dataset.error = 'true';status.textContent = 'Speed control unavailable. Restart Spotify.';
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
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true }); else start();
})())js";

// The few CEF C API types the page-process hook needs. Only eval's position in the
// context struct matters; it has been stable for years and the size is checked below.
struct CefString {const char16_t* str;size_t length;void(*dtor)(char16_t*);};
struct CefBase {size_t size;void(*addRef)(CefBase*);int(*release)(CefBase*);int(*hasOneRef)(CefBase*);int(*hasAtLeastOneRef)(CefBase*);};
struct CefV8Context {
    CefBase base;
    void *getTaskRunner,*isValid,*getBrowser,*getFrame,*getGlobal,*enter,*exit,*isSame;
    int(*eval)(CefV8Context*,const CefString*,const CefString*,int,CefBase**,CefBase**);
};
using CreateFunctionFn=void*(*)(const CefString*,void*);
using CurrentContextFn=CefV8Context*(*)();
using InContextFn=int(*)();
CreateFunctionFn createFunctionOriginal;
CurrentContextFn currentContext;
InContextFn inContext;

// Spotify registers its native JS functions while each page loads, so this runs inside
// the new page's context. The script guards itself, so repeat calls are cheap no-ops.
void* CreateFunctionHook(const CefString* name,void* handler) {
    if(inContext()) {
        if(CefV8Context* context=currentContext()) {
            if(context->base.size>=sizeof(CefV8Context)) {
                const CefString code{speedControlScript,std::size(speedControlScript)-1,nullptr};
                const CefString url{u"spotify-playback-speed.js",25,nullptr};
                CefBase* result=nullptr;CefBase* exception=nullptr;
                context->eval(context,&code,&url,1,&result,&exception);
                if(result)result->release(result);
                if(exception)exception->release(exception);
            }
            context->base.release(&context->base);
        }
    }
    return createFunctionOriginal(name,handler);
}

bool HookPageProcess() {
    HMODULE cef=GetModuleHandleW(L"libcef.dll");
    if(!cef)cef=LoadLibraryW(L"libcef.dll");
    if(!cef)return false;
    // CEF 134 renamed cef_v8value_* to cef_v8_value_* (and the same for contexts).
    auto find=[&](const char* current,const char* old){FARPROC p=GetProcAddress(cef,current);return p?p:GetProcAddress(cef,old);};
    auto createFunction=reinterpret_cast<void*>(find("cef_v8_value_create_function","cef_v8value_create_function"));
    currentContext=reinterpret_cast<CurrentContextFn>(find("cef_v8_context_get_current_context","cef_v8context_get_current_context"));
    inContext=reinterpret_cast<InContextFn>(find("cef_v8_context_in_context","cef_v8context_in_context"));
    if(!createFunction || !currentContext || !inContext) {Log("CEF V8 functions not found\r\n");return false;}
    return Wh_SetFunctionHook(createFunction,reinterpret_cast<void*>(CreateFunctionHook),reinterpret_cast<void**>(&createFunctionOriginal));
}

bool pageProcess=false;

BOOL Wh_ModInit() {
    const wchar_t* commandLine=GetCommandLineW();
    if(wcsstr(commandLine,L"--type=")) {
        // Only Spotify's page renderer gets the UI; other helper processes are left alone.
        if(!wcsstr(commandLine,L"--type=renderer") || wcsstr(commandLine,L"--extension-process"))return FALSE;
        pageProcess=true;
        return HookPageProcess();
    }
    int value=static_cast<int>(Wh_GetIntValue(L"liveSpeedPercent",Wh_GetIntSetting(L"speedPercent")));
    percent=ValidPercent(value)?value:100;
    return TRUE;
}
void Wh_ModAfterInit() {
    if(pageProcess)return;
    worker=CreateThread(nullptr,0,Worker,nullptr,0,nullptr);
    HRESULT initialized=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    if(FAILED(initialized) && initialized!=RPC_E_CHANGED_MODE)return;
    IMMDeviceEnumerator* enumerator=nullptr;IMMDevice* device=nullptr;IAudioClient* client=nullptr;
    HRESULT result=CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_INPROC_SERVER,
        __uuidof(IMMDeviceEnumerator),reinterpret_cast<void**>(&enumerator));
    if(SUCCEEDED(result))result=enumerator->GetDefaultAudioEndpoint(eRender,eMultimedia,&device);
    if(SUCCEEDED(result))result=device->Activate(__uuidof(IAudioClient),CLSCTX_INPROC_SERVER,nullptr,reinterpret_cast<void**>(&client));
    if(SUCCEEDED(result) && worker) {
        auto table=*reinterpret_cast<void***>(client);
        if(Wh_SetFunctionHook(table[3],reinterpret_cast<void*>(InitHook),reinterpret_cast<void**>(&initOriginal)) &&
           Wh_SetFunctionHook(table[10],reinterpret_cast<void*>(StartHook),reinterpret_cast<void**>(&startOriginal)) &&
           Wh_SetFunctionHook(table[11],reinterpret_cast<void*>(StopHook),reinterpret_cast<void**>(&stopOriginal)) &&
           Wh_ApplyHookOperations())Log("Live Windows audio hooks installed\r\n");
    }
    if(client)client->Release();if(device)device->Release();if(enumerator)enumerator->Release();
    if(SUCCEEDED(initialized))CoUninitialize();
}
void Wh_ModSettingsChanged() {if(!pageProcess)SetPercent(Wh_GetIntSetting(L"speedPercent"));}
void Wh_ModBeforeUninit() {stopping=true;if(worker){WaitForSingleObject(worker,INFINITE);CloseHandle(worker);worker=nullptr;}}
