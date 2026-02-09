final class WinString {
  let ptr: UnsafeMutablePointer<UInt16>
  private let count: Int

  init(_ str: String) {
    let utf16 = str.utf16.map { UInt16($0) } + [0]
    count = utf16.count
    ptr = UnsafeMutablePointer<UInt16>.allocate(capacity: count)
    ptr.initialize(from: utf16, count: count)
  }

  deinit {
    ptr.deinitialize(count: count)
    ptr.deallocate()
  }

  // Returns the LPCWSTR you need for Win32
  var lpcwstr: UnsafePointer<UInt16> { return UnsafePointer(ptr) }
}
