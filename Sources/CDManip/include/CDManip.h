#ifndef CDMANIP_H
#define CDMANIP_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum CDManipPhase {
    CDManipPhaseBegan = 0,
    CDManipPhaseChanged = 1,
    CDManipPhaseEnded = 2,
} CDManipPhase;

typedef struct CDManipCallbacks {
    void *_Nullable userData;
    /// delta: relative magnification since the last event (newScale/oldScale - 1).
    void (*_Nonnull onPinch)(void *_Nullable userData, double delta, CDManipPhase phase);
    /// deltaX/deltaY: pan since the last event, in physical pixels.
    void (*_Nonnull onPan)(void *_Nullable userData, double deltaX, double deltaY,
                           CDManipPhase phase);
} CDManipCallbacks;

typedef struct CDManipController CDManipController;

/// Creates a DirectManipulation controller for the given HWND. Returns NULL on
/// failure (e.g. DirectManipulation unavailable). All functions, including the
/// callbacks, run on the thread that owns the window.
CDManipController *_Nullable cdmanip_create(void *_Nonnull hwnd, CDManipCallbacks callbacks);

void cdmanip_destroy(CDManipController *_Nonnull controller);

/// Forward DM_POINTERHITTEST (0x0318) here with the message's wParam.
void cdmanip_pointer_hit_test(CDManipController *_Nonnull controller, uintptr_t wParam);

#ifdef __cplusplus
}
#endif

#endif /* CDMANIP_H */
