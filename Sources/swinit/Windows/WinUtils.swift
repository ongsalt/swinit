import WinSDK

@inline(__always)
func LOWORD(_ dword: UInt32) -> UInt16 {
  UInt16(truncatingIfNeeded: dword & 0xFFFF)
}

@inline(__always)
func HIWORD(_ dword: UInt32) -> UInt16 {
  UInt16(truncatingIfNeeded: (dword >> 16) & 0xFFFF)
}

@inline(__always)
func LOWORD(_ dword: WPARAM) -> UInt16 {
  LOWORD(UInt32(dword))
}

@inline(__always)
func HIWORD(_ dword: WPARAM) -> UInt16 {
  HIWORD(UInt32(dword))
}

@inline(__always)
func LOWORD(_ dword: LPARAM) -> UInt16 {
  LOWORD(UInt32(dword))
}

@inline(__always)
func HIWORD(_ dword: LPARAM) -> UInt16 {
  HIWORD(UInt32(dword))
}
