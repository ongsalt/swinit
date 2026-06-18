import WinSDK

// from mica for everyone
public enum WindowsBackdropStyle: UInt32 {
    case auto
    case none
    case mica
    case acrylic
    case micaAlt
}

public enum TitleBarAppearance {
    /// Match the system dark/light mode preference (default).
    case system
    case dark
    case light

    package var resolvedDark: Bool {
        switch self {
        case .dark:   return true
        case .light:  return false
        case .system: return systemPrefersDarkMode()
        }
    }
}

/// Reads AppsUseLightTheme from the registry to detect dark mode.
private func systemPrefersDarkMode() -> Bool {
    let keyPath  = "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"
    let valName  = "AppsUseLightTheme"
    var data: DWORD = 1                                    // default: light
    var size: DWORD = DWORD(MemoryLayout<DWORD>.size)
    let status = keyPath.withCString(encodedAs: UTF16.self) { kp in
        valName.withCString(encodedAs: UTF16.self) { vp in
            RegGetValueW(HKEY_CURRENT_USER, kp, vp,
                         DWORD(RRF_RT_REG_DWORD), nil, &data, &size)
        }
    }
    return status == ERROR_SUCCESS && data == 0
}
