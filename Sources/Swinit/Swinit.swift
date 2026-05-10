@_exported import SwinitCommon

#if canImport(SwinitWin32)

import SwinitWin32

public typealias Window = WindowsWindow
public typealias EventLoop = WindowsEventLoop

#elseif canImport(SwinitWayland)

import SwinitWayland

public typealias Window = WaylandWindow
public typealias EventLoop = WaylandEventLoop

#else

public typealias Window = Any
public typealias EventLoop = Any

#endif