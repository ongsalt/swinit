#include <wayland-client-core.h>
#include <wayland-client-protocol.h>

#include "xdg-shell-client-protocol.h"
#include "xdg-toplevel-drag-v1-client-protocol.h"

#include "interfaces.h"

const struct _WaylandInterfaces WaylandInterfaces = {
    .surface = &wl_surface_interface,
    .shm = &wl_shm_interface,
    .compositor = &wl_compositor_interface,
    .xdgWmBase = &xdg_wm_base_interface,
    .xdgToplevelDragV1 = &xdg_toplevel_drag_v1_interface
};
