import CWayland
import Foundation
import Glibc

public class SHMPool {
    let pool: OpaquePointer
    let fd: Int32
    let size: Int32
    public let poolData: UnsafeMutableRawPointer

    public init(shm: SharedMemoryBuffer, size: Int32) {
        self.size = size

        let name = "/wl_shm-\(UUID())"
        fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600)
        shm_unlink(name)

        // print("fd: \(fd)")

        var ret: Int32 = 0
        repeat {
            ret = ftruncate(fd, Int(size))
        } while errno == EINTR && ret < 0
        
        poolData = mmap(nil, Int(size), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)!
        pool = wl_shm_create_pool(shm.shm, fd, size)!
    }

    public func createBuffer(
        offset: Int32, width: Int32, height: Int32, stride: Int32,
        format: wl_shm_format = WL_SHM_FORMAT_ARGB8888
    )
        -> Buffer
    {
        Buffer(
            pool: self, offset: offset, width: width, height: height, stride: stride, format: format
        )
    }

    // 4 bytes????
    // TODO:
    public subscript(offset: UInt32) -> UInt32 {
        get {
            poolData.load(fromByteOffset: Int(offset), as: UInt32.self)
        }
        set {
            poolData.storeBytes(of: newValue, toByteOffset: Int(offset), as: UInt32.self)
        }
    }
}
