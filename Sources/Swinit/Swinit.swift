@_exported import SwinitCore

#if canImport(SwinitWin32)
@_exported import SwinitWin32
#elseif canImport(SwinitWayland)
@_exported import SwinitWayland
#endif
