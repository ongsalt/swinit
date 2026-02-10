#ifndef I_DONT_WANNA_WRITE_A_CODE_GENERATOR_2_H
#define I_DONT_WANNA_WRITE_A_CODE_GENERATOR_2_H

#include "xdg-shell-client-protocol.h"
#include <wayland-client-core.h>
#include <wayland-client-protocol.h>
#include <wayland-util.h>

// we can just make a struct
struct _WaylandInterfaces {
  struct wl_interface *surface;
  struct wl_interface *shm;
  struct wl_interface *compositor;
  struct wl_interface *xdgWmBase;
  struct wl_interface *xdgToplevelDragV1;
};

const struct _WaylandInterfaces WaylandInterfaces;

#endif