// Minimal reproducer for the wl_seat.missingCapability protocol error.
//
// Calling wl_seat.get_touch when the seat does not advertise touch capability
// is a protocol error since wl_seat v5. On GNOME/mutter it kills the session.
// On compositors that handle it gracefully (e.g. Niri) the client is
// disconnected and an "ok" message is printed.
import WaylandClient

let conn = Connection()

var seat: WlSeat?
var caps: WlSeat.Capability = []

let globals = try Globals(connection: conn)
seat = try? globals.bind(to: WlSeat.self, version: 5...9)

// Capture capabilities before the roundtrips.
seat?.onEvent = { event in
    if case .capabilities(let c) = event { caps = c }
}

// First roundtrip: registry globals arrive, wl_seat is bound.
conn.roundtrip()
// Second roundtrip: wl_seat.capabilities arrives in response to the bind.
conn.roundtrip()

print("seat capabilities: \(String(format: "0x%x", caps.rawValue))", terminator: "")
print(caps.isEmpty ? " (none)" :
      " (\(caps.contains(.pointer) ? "pointer " : "")" +
      "\(caps.contains(.keyboard) ? "keyboard " : "")" +
      "\(caps.contains(.touch) ? "touch" : ""))")

print("calling wl_seat.get_touch() without checking capabilities...")
_ = try? seat?.getTouch()

// Compositor processes our request on the next roundtrip.
// wl_display_roundtrip returns -1 if a protocol error was received.
let ok = conn.roundtrip()

if ok < 0 {
    print("ok — compositor sent protocol error and disconnected this client (compositor still running)")
} else {
    print("compositor did not enforce the capability check")
}
