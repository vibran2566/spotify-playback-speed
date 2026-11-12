// Exercises the real worker and COM handoff in an independent process, without injection.
#include <winsock2.h>
#include <windows.h>
#include <cstdio>
#include <cmath>
#include <audiopolicy.h>
void Wh_Log(const wchar_t*,const char*) {}
int Wh_GetIntValue(const wchar_t*,int value) {return value;}
int Wh_GetIntSetting(const wchar_t*) {return 100;}
void Wh_SetIntValue(const wchar_t*,int) {}
bool Wh_SetFunctionHook(void*,void*,void**) {return false;}
bool Wh_ApplyHookOperations() {return false;}
#include "spotify-audio-speed.wh.cpp"

void Check(HRESULT result,const char* operation) {
    if(FAILED(result)) {std::printf("FAIL %s %08lx\n",operation,result);ExitProcess(1);}
}
int main() {
    Check(CoInitializeEx(nullptr,COINIT_MULTITHREADED),"COM");
    IMMDeviceEnumerator* enumerator=nullptr;IMMDevice* device=nullptr;IAudioClient* client=nullptr;
    Check(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_INPROC_SERVER,
        __uuidof(IMMDeviceEnumerator),reinterpret_cast<void**>(&enumerator)),"enumerator");
    Check(enumerator->GetDefaultAudioEndpoint(eRender,eMultimedia,&device),"device");
    IAudioSessionManager2* manager=nullptr;IAudioSessionEnumerator* sessions=nullptr;
    Check(device->Activate(__uuidof(IAudioSessionManager2),CLSCTX_INPROC_SERVER,nullptr,reinterpret_cast<void**>(&manager)),"sessions");
    Check(manager->GetSessionEnumerator(&sessions),"session list");int count=0;sessions->GetCount(&count);
    for(int i=0;i<count;++i) {IAudioSessionControl* session=nullptr;IAudioSessionControl2* control=nullptr;
        if(SUCCEEDED(sessions->GetSession(i,&session))) {
            if(SUCCEEDED(session->QueryInterface(__uuidof(IAudioSessionControl2),reinterpret_cast<void**>(&control)))) {
                DWORD pid=0;control->GetProcessId(&pid);std::printf("audio-session PID=%lu\n",pid);control->Release();}
            session->Release();}}
    sessions->Release();manager->Release();
    Check(device->Activate(__uuidof(IAudioClient),CLSCTX_INPROC_SERVER,nullptr,reinterpret_cast<void**>(&client)),"client");
    auto table=*reinterpret_cast<void***>(client);
    initOriginal=reinterpret_cast<InitFn>(table[3]);startOriginal=reinterpret_cast<ClientFn>(table[10]);stopOriginal=reinterpret_cast<ClientFn>(table[11]);
    WAVEFORMATEX* format=nullptr;Check(client->GetMixFormat(&format),"format");
    if(format->wBitsPerSample!=32) {std::puts("SKIP: test requires float32 mix");return 2;}
    Wh_ModInit();worker=CreateThread(nullptr,0,Worker,nullptr,0,nullptr);
    Check(InitHook(client,AUDCLNT_SHAREMODE_SHARED,AUDCLNT_STREAMFLAGS_EVENTCALLBACK,100000,0,format,nullptr),"init");
    HANDLE event=CreateEventW(nullptr,FALSE,FALSE,nullptr);Check(client->SetEventHandle(event),"event");
    UINT32 capacity=0;Check(client->GetBufferSize(&capacity),"buffer size");
    IAudioRenderClient* render=nullptr;Check(client->GetService(__uuidof(IAudioRenderClient),reinterpret_cast<void**>(&render)),"render");
    double phase=0;auto fill=[&](UINT32 frames) {
        BYTE* data=nullptr;Check(render->GetBuffer(frames,&data),"get buffer");
        auto samples=reinterpret_cast<float*>(data);
        for(UINT32 i=0;i<frames;++i) {float value=0.02f*std::sin(phase);phase+=2*3.141592653589793*440/format->nSamplesPerSec;
            for(WORD c=0;c<format->nChannels;++c)samples[i*format->nChannels+c]=value;}
        Check(render->ReleaseBuffer(frames,0),"release buffer");
    };
    fill(capacity);Check(StartHook(client),"start");
    int speeds[]={100,50,125,200,100};
    for(int speed:speeds) {
        SetPercent(speed);auto end=GetTickCount64()+2000;unsigned empty=0,callbacks=0;
        while(GetTickCount64()<end) {
            if(WaitForSingleObject(event,1000)!=WAIT_OBJECT_0) {std::puts("FAIL: event timeout");return 1;}
            UINT32 padding=0;Check(client->GetCurrentPadding(&padding),"padding");
            ++callbacks;if(!padding)++empty;
            if(padding<capacity)fill(capacity-padding);
        }
        std::printf("percent=%d HRESULT=%08lx buffer=%u callbacks=%u empty=%u\n",speed,lastResult.load(),capacity,callbacks,empty);std::fflush(stdout);
        Check(lastResult.load(),"worker adjustment");
    }
    Check(StopHook(client),"stop");Wh_ModBeforeUninit();
    render->Release();client->Release();device->Release();enumerator->Release();CoTaskMemFree(format);CloseHandle(event);CoUninitialize();
    std::puts("PASS: worker live changes and cleanup");
}
