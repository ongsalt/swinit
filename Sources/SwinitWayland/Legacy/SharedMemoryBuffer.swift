import CWayland
import Foundation
import Glibc

public class SharedMemoryBuffer {
    let shm: OpaquePointer


    public init(shm: OpaquePointer) {
        self.shm = shm
    }

    public func createPool(size: Int32) -> SHMPool {
        return SHMPool(shm: self, size: size)
    }
}
