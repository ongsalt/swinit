// DirectManipulation-based touchpad gesture recognition, modeled on Chromium's
// ui/base/win/direct_manipulation_helper. A fake 1000x1000 viewport captures
// touchpad contacts (via DM_POINTERHITTEST -> SetContact); the cumulative
// content transform is diffed into pinch/pan deltas and reset to identity when
// the viewport returns to READY.
#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <directmanipulation.h>
#include <objbase.h>

#include <cmath>
#include <cstdio>
#include <unordered_map>

#include "include/CDManip.h"

// Temporary diagnostics, remove once touchpad capture is confirmed working.
#define CDMANIP_LOG(...)                  \
    do {                                  \
        fprintf(stderr, "[cdmanip] " __VA_ARGS__); \
        fputc('\n', stderr);              \
        fflush(stderr);                   \
    } while (0)

namespace {

constexpr int kViewportSize = 1000;
constexpr float kScaleEpsilon = 1e-5f;
constexpr UINT kUpdateIntervalMs = 8;

class Controller;

// Timer id -> controller, so the flat WinAPI TimerProc can find its owner.
// Everything runs on the window's UI thread, so no locking.
std::unordered_map<UINT_PTR, Controller *> &activeTimers() {
    static std::unordered_map<UINT_PTR, Controller *> map;
    return map;
}

void CALLBACK updateTimerProc(HWND, UINT, UINT_PTR id, DWORD);

class EventHandler final : public IDirectManipulationViewportEventHandler {
public:
    explicit EventHandler(Controller *owner) : owner_(owner) {}
    void detach() { owner_ = nullptr; }

    // IUnknown
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (riid == IID_IUnknown ||
            riid == __uuidof(IDirectManipulationViewportEventHandler)) {
            *ppv = static_cast<IDirectManipulationViewportEventHandler *>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refCount_; }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG count = --refCount_;
        if (count == 0) delete this;
        return count;
    }

    // IDirectManipulationViewportEventHandler
    HRESULT STDMETHODCALLTYPE OnViewportStatusChanged(
        IDirectManipulationViewport *viewport, DIRECTMANIPULATION_STATUS current,
        DIRECTMANIPULATION_STATUS previous) override;
    HRESULT STDMETHODCALLTYPE OnViewportUpdated(IDirectManipulationViewport *) override {
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE OnContentUpdated(IDirectManipulationViewport *,
                                               IDirectManipulationContent *content) override;

private:
    ~EventHandler() = default;

    Controller *owner_;
    ULONG refCount_ = 1;
};

class Controller {
public:
    Controller(HWND hwnd, CDManipCallbacks callbacks) : hwnd_(hwnd), callbacks_(callbacks) {}

    ~Controller() {
        stopUpdateTimer();
        if (viewport_) {
            viewport_->Stop();
            if (eventHandlerCookie_ != 0) viewport_->RemoveEventHandler(eventHandlerCookie_);
            viewport_->Abandon();
            viewport_->Release();
        }
        if (handler_) {
            handler_->detach();
            handler_->Release();
        }
        if (updateManager_) updateManager_->Release();
        if (manager_) {
            manager_->Deactivate(hwnd_);
            manager_->Release();
        }
        if (comInitialized_) CoUninitialize();
    }

    bool initialize() {
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        comInitialized_ = SUCCEEDED(hr);  // RPC_E_CHANGED_MODE: COM already up, fine
        CDMANIP_LOG("CoInitializeEx hr=0x%08lx", hr);

        hr = CoCreateInstance(__uuidof(DirectManipulationManager), nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&manager_));
        if (FAILED(hr)) { CDMANIP_LOG("CoCreateInstance failed hr=0x%08lx", hr); return false; }
        hr = manager_->GetUpdateManager(IID_PPV_ARGS(&updateManager_));
        if (FAILED(hr)) { CDMANIP_LOG("GetUpdateManager failed hr=0x%08lx", hr); return false; }
        hr = manager_->CreateViewport(nullptr, hwnd_, IID_PPV_ARGS(&viewport_));
        if (FAILED(hr)) { CDMANIP_LOG("CreateViewport failed hr=0x%08lx", hr); return false; }

        DIRECTMANIPULATION_CONFIGURATION configuration =
            DIRECTMANIPULATION_CONFIGURATION_INTERACTION |
            DIRECTMANIPULATION_CONFIGURATION_TRANSLATION_X |
            DIRECTMANIPULATION_CONFIGURATION_TRANSLATION_Y |
            DIRECTMANIPULATION_CONFIGURATION_TRANSLATION_INERTIA |
            DIRECTMANIPULATION_CONFIGURATION_RAILS_X |
            DIRECTMANIPULATION_CONFIGURATION_RAILS_Y |
            DIRECTMANIPULATION_CONFIGURATION_SCALING;
        hr = viewport_->ActivateConfiguration(configuration);
        if (FAILED(hr)) return false;
        // We pump updates ourselves; DM must not wait for a compositor frame.
        hr = viewport_->SetViewportOptions(DIRECTMANIPULATION_VIEWPORT_OPTIONS_MANUALUPDATE);
        if (FAILED(hr)) return false;

        handler_ = new EventHandler(this);
        hr = viewport_->AddEventHandler(hwnd_, handler_, &eventHandlerCookie_);
        if (FAILED(hr)) return false;

        RECT rect = {0, 0, kViewportSize, kViewportSize};
        hr = viewport_->SetViewportRect(&rect);
        if (FAILED(hr)) return false;

        hr = manager_->Activate(hwnd_);
        if (FAILED(hr)) { CDMANIP_LOG("Activate failed hr=0x%08lx", hr); return false; }
        hr = viewport_->Enable();
        if (FAILED(hr)) { CDMANIP_LOG("Enable failed hr=0x%08lx", hr); return false; }
        hr = updateManager_->Update(nullptr);
        CDMANIP_LOG("initialized, first Update hr=0x%08lx", hr);
        return SUCCEEDED(hr);
    }

    void pointerHitTest(WPARAM wParam) {
        if (!viewport_) return;
        UINT32 pointerId = GET_POINTERID_WPARAM(wParam);
        POINTER_INPUT_TYPE type = PT_POINTER;
        BOOL gotType = GetPointerType(pointerId, &type);
        CDMANIP_LOG("DM_POINTERHITTEST id=%u gotType=%d type=%ld", pointerId, gotType, (long)type);
        if (gotType && type == PT_TOUCHPAD) {
            HRESULT hr = viewport_->SetContact(pointerId);
            CDMANIP_LOG("SetContact hr=0x%08lx", hr);
        }
    }

    void onStatusChanged(DIRECTMANIPULATION_STATUS current, DIRECTMANIPULATION_STATUS previous) {
        CDMANIP_LOG("status %d -> %d", (int)previous, (int)current);
        if (current == previous) return;

        if (current == DIRECTMANIPULATION_RUNNING || current == DIRECTMANIPULATION_INERTIA) {
            startUpdateTimer();
        } else {
            stopUpdateTimer();
        }

        if (current == DIRECTMANIPULATION_READY) {
            endGestures();
            // Reset the content transform to identity so the next gesture starts
            // clean and never accumulates toward the viewport bounds.
            if (viewport_ && (std::fabs(lastScale_ - 1.0f) > kScaleEpsilon ||
                              lastX_ != 0.0f || lastY_ != 0.0f)) {
                viewport_->ZoomToRect(0.0f, 0.0f, float(kViewportSize), float(kViewportSize),
                                      FALSE);
            }
            lastScale_ = 1.0f;
            lastX_ = 0.0f;
            lastY_ = 0.0f;
        }
    }

    void onContentUpdated(IDirectManipulationContent *content) {
        float m[6];
        if (FAILED(content->GetContentTransform(m, 6))) return;
        float scale = m[0];
        float x = m[4];
        float y = m[5];
        if (scale <= 0.0f) return;

        double scaleDelta = double(scale) / double(lastScale_) - 1.0;
        double dx = double(x) - double(lastX_);
        double dy = double(y) - double(lastY_);
        lastScale_ = scale;
        lastX_ = x;
        lastY_ = y;

        if (std::fabs(scaleDelta) > 1e-9) {
            if (!pinchActive_) {
                pinchActive_ = true;
                callbacks_.onPinch(callbacks_.userData, 0.0, CDManipPhaseBegan);
            }
            callbacks_.onPinch(callbacks_.userData, scaleDelta, CDManipPhaseChanged);
        }
        if (dx != 0.0 || dy != 0.0) {
            if (!panActive_) {
                panActive_ = true;
                callbacks_.onPan(callbacks_.userData, 0.0, 0.0, CDManipPhaseBegan);
            }
            callbacks_.onPan(callbacks_.userData, dx, dy, CDManipPhaseChanged);
        }
    }

    void update() {
        if (updateManager_) updateManager_->Update(nullptr);
    }

private:
    void endGestures() {
        if (pinchActive_) {
            pinchActive_ = false;
            callbacks_.onPinch(callbacks_.userData, 0.0, CDManipPhaseEnded);
        }
        if (panActive_) {
            panActive_ = false;
            callbacks_.onPan(callbacks_.userData, 0.0, 0.0, CDManipPhaseEnded);
        }
    }

    void startUpdateTimer() {
        if (timerId_ != 0) return;
        timerId_ = SetTimer(nullptr, 0, kUpdateIntervalMs, updateTimerProc);
        if (timerId_ != 0) activeTimers()[timerId_] = this;
    }

    void stopUpdateTimer() {
        if (timerId_ == 0) return;
        KillTimer(nullptr, timerId_);
        activeTimers().erase(timerId_);
        timerId_ = 0;
    }

    HWND hwnd_;
    CDManipCallbacks callbacks_;
    bool comInitialized_ = false;

    IDirectManipulationManager *manager_ = nullptr;
    IDirectManipulationUpdateManager *updateManager_ = nullptr;
    IDirectManipulationViewport *viewport_ = nullptr;
    EventHandler *handler_ = nullptr;
    DWORD eventHandlerCookie_ = 0;
    UINT_PTR timerId_ = 0;

    float lastScale_ = 1.0f;
    float lastX_ = 0.0f;
    float lastY_ = 0.0f;
    bool pinchActive_ = false;
    bool panActive_ = false;
};

HRESULT EventHandler::OnViewportStatusChanged(IDirectManipulationViewport *,
                                              DIRECTMANIPULATION_STATUS current,
                                              DIRECTMANIPULATION_STATUS previous) {
    if (owner_) owner_->onStatusChanged(current, previous);
    return S_OK;
}

HRESULT EventHandler::OnContentUpdated(IDirectManipulationViewport *,
                                       IDirectManipulationContent *content) {
    if (owner_) owner_->onContentUpdated(content);
    return S_OK;
}

void CALLBACK updateTimerProc(HWND, UINT, UINT_PTR id, DWORD) {
    auto &timers = activeTimers();
    auto it = timers.find(id);
    if (it != timers.end()) it->second->update();
}

}  // namespace

extern "C" {

CDManipController *cdmanip_create(void *hwnd, CDManipCallbacks callbacks) {
    auto *controller = new Controller(static_cast<HWND>(hwnd), callbacks);
    if (!controller->initialize()) {
        delete controller;
        return nullptr;
    }
    return reinterpret_cast<CDManipController *>(controller);
}

void cdmanip_destroy(CDManipController *controller) {
    delete reinterpret_cast<Controller *>(controller);
}

void cdmanip_pointer_hit_test(CDManipController *controller, uintptr_t wParam) {
    reinterpret_cast<Controller *>(controller)->pointerHitTest(static_cast<WPARAM>(wParam));
}

}  // extern "C"

#endif  // _WIN32
