// ==WindhawkMod==
// @id spotify-audio-speed
// @name Spotify Audio Speed
// @description Live speed and pitch control for Spotify's Windows audio stream
// @version 0.3.2
// @author vibran
// @license MIT
// @include Spotify.exe
// @architecture x86-64
// @compilerOptions -DWIN32_LEAN_AND_MEAN -lole32 -luuid -lws2_32
// ==/WindhawkMod==

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

BOOL Wh_ModInit() {
    if(wcsstr(GetCommandLineW(),L"--type="))return FALSE;
    int value=static_cast<int>(Wh_GetIntValue(L"liveSpeedPercent",Wh_GetIntSetting(L"speedPercent")));
    percent=ValidPercent(value)?value:100;
    return TRUE;
}
void Wh_ModAfterInit() {
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
void Wh_ModSettingsChanged() {SetPercent(Wh_GetIntSetting(L"speedPercent"));}
void Wh_ModBeforeUninit() {stopping=true;if(worker){WaitForSingleObject(worker,INFINITE);CloseHandle(worker);worker=nullptr;}}
