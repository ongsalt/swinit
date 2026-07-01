#if os(Linux)
import CXkbCommon
import WaylandClient
import Foundation
import Glibc

// Wraps xkb_context + xkb_keymap + xkb_state for a single wl_keyboard.
@MainActor
final class XKBState {
    nonisolated(unsafe) private var ctx:     OpaquePointer?
    nonisolated(unsafe) private var keymap:  OpaquePointer?
    nonisolated(unsafe) private var state:   OpaquePointer?

    init() {
        ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS)
    }

    deinit {
        xkb_state_unref(state)
        xkb_keymap_unref(keymap)
        xkb_context_unref(ctx)
    }

    // Called from wl_keyboard.keymap event.
    func loadKeymap(fd: FileHandle, size: Int) {
        let raw = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd.fileDescriptor, 0)
        guard raw != MAP_FAILED, let ptr = raw else { return }
        defer { munmap(ptr, size) }

        guard let newKeymap = xkb_keymap_new_from_string(
            ctx, ptr.assumingMemoryBound(to: CChar.self),
            XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS)
        else { return }

        xkb_state_unref(state)
        xkb_keymap_unref(keymap)
        keymap = newKeymap
        state  = xkb_state_new(newKeymap)
    }

    // Feed modifier state from wl_keyboard.modifiers.
    func updateMask(depressed: UInt32, latched: UInt32, locked: UInt32, group: UInt32) {
        guard let state else { return }
        xkb_state_update_mask(state, depressed, latched, locked, 0, 0, group)
    }

    // Translate an evdev keycode to (keysym, text).
    // Returns nil for both if no keymap is loaded.
    func translate(evdev: UInt32) -> (sym: UInt32, text: String?) {
        guard let state else { return (UInt32(XKB_KEY_NoSymbol), nil) }
        let xkbCode = xkb_keycode_t(evdev + 8)
        let sym = UInt32(xkb_state_key_get_one_sym(state, xkbCode))
        var buf = [CChar](repeating: 0, count: 64)
        let n = xkb_state_key_get_utf8(state, xkbCode, &buf, buf.count)
        let text: String? = n > 0 ? buf.withUnsafeBytes { String(decoding: $0.prefix(Int(n)), as: UTF8.self) } : nil
        return (sym, text)
    }
}
#endif
