import CWayland
import Glibc

// content of a wl_surface
public class Buffer {
    let buffer: OpaquePointer
    public let bufferData: UnsafeMutableRawBufferPointer
    private var listener: wl_buffer_listener

    let offset: Int32
    let width: Int32
    let height: Int32
    let stride: Int32
    let format: wl_shm_format

    init(
        pool: SHMPool, offset: Int32, width: Int32, height: Int32, stride: Int32,
        format: wl_shm_format
    ) {
        self.format = format
        self.offset = offset
        self.width = width
        self.height = height
        self.stride = stride

        self.bufferData = UnsafeMutableRawBufferPointer(start: pool.poolData.advanced(by: Int(offset)), count: Int(stride * height))

        buffer = wl_shm_pool_create_buffer(
            pool.pool, offset,
            width, height, stride, format.rawValue
        )!

        listener = wl_buffer_listener { ptr, _ in
            let this = Unmanaged<Buffer>.fromOpaque(ptr!).takeUnretainedValue()

            wl_buffer_destroy(this.buffer)
        }

        let ptr = Unmanaged.passUnretained(self).toOpaque()
        wl_buffer_add_listener(buffer, &listener, ptr)
    }

    func s() {

    }
}
