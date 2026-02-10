import WinSDK

final class WinString {
  private var inner: _WinString
  public var string: String {
    didSet {
      self.inner = _WinString(string)
    }
  }

  init(_ string: String) {
    self.string = string
    self.inner = _WinString(string)
  }

  deinit {
    inner.drop()
  }

  // Returns the LPCWSTR you need for Win32
  var lpcwstr: UnsafePointer<UInt16> {
    inner.lpcwstr
  }
}

private struct _WinString {
  let ptr: UnsafeMutablePointer<UInt16>
  let count: Int

  init(_ str: String) {
    let utf16: [UInt16] = str.utf16.map { UInt16($0) } + [0]
    count = utf16.count
    ptr = UnsafeMutablePointer<UInt16>.allocate(capacity: count)
    ptr.initialize(from: utf16, count: count)
  }

  func drop() {
    ptr.deinitialize(count: count)
    ptr.deallocate()
  }

  // Returns the LPCWSTR you need for Win32
  var lpcwstr: UnsafePointer<UInt16> { return UnsafePointer(ptr) }
}

extension String {
  public var wideString: [UInt16] {
    return self.withCString(encodedAs: UTF16.self) { buffer in
      [UInt16](unsafeUninitializedCapacity: self.utf16.count + 1) {
        WinSDK.wcscpy_s($0.baseAddress, $0.count, buffer)
        $1 = $0.count
      }
    }
  }

  var pinned: WinString {
    WinString(self)
  }
}
