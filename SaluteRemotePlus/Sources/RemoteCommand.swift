import Foundation

enum RemoteCommand: String, CaseIterable, Identifiable {
    case power = "POWER"
    case mute = "MUTE"
    case up = "UP"
    case down = "DOWN"
    case left = "LEFT"
    case right = "RIGHT"
    case ok = "OK"
    case back = "BACK"
    case home = "HOME"
    case settings = "SETTINGS"
    case search = "SEARCH"
    case source = "SOURCE"
    case volumeUp = "VOLUME_UP"
    case volumeDown = "VOLUME_DOWN"
    case channelUp = "CHANNEL_UP"
    case channelDown = "CHANNEL_DOWN"
    case playPause = "PLAY_PAUSE"
    case mouseClick = "MOUSE_CLICK"
    case menu = "MENU"
    case info = "INFO"
    case rewind = "REWIND"
    case fastForward = "FAST_FORWARD"
    case assist = "ASSIST"

    var id: String { rawValue }

    /// Официальные коды кнопок протокола Salute TV Gamepad (`Message.Gamepad.Button.code`).
    var buttonCode: UInt32 {
        switch self {
        case .up: return 20
        case .down: return 21
        case .left: return 22
        case .right: return 23
        case .ok: return 24
        case .back: return 34
        case .home: return 35
        case .volumeUp: return 37
        case .volumeDown: return 38
        case .power: return 39
        case .mute: return 40
        case .mouseClick: return 44
        // Команды ниже преимущественно уходят через LibSberCast (deeplink / mediaCommand),
        // значения оставлены как безопасные резервные коды.
        case .settings: return 35
        case .search: return 84
        case .source: return 178
        case .channelUp: return 45
        case .channelDown: return 46
        case .playPause: return 24
        case .menu: return 35
        case .info: return 35
        case .rewind: return 22
        case .fastForward: return 23
        case .assist: return 84
        }
    }

    /// Стандартные Android KeyEvent коды (Android TV Remote v2 и YaOS / ADB).
    var androidKeyCode: Int {
        switch self {
        case .power: return 26          // KEYCODE_POWER
        case .mute: return 164          // KEYCODE_VOLUME_MUTE
        case .up: return 19             // KEYCODE_DPAD_UP
        case .down: return 20           // KEYCODE_DPAD_DOWN
        case .left: return 21           // KEYCODE_DPAD_LEFT
        case .right: return 22          // KEYCODE_DPAD_RIGHT
        case .ok: return 23             // KEYCODE_DPAD_CENTER
        case .back: return 4            // KEYCODE_BACK
        case .home: return 3            // KEYCODE_HOME
        case .settings: return 176      // KEYCODE_SETTINGS
        case .search: return 84         // KEYCODE_SEARCH
        case .source: return 178        // KEYCODE_TV_INPUT
        case .volumeUp: return 24       // KEYCODE_VOLUME_UP
        case .volumeDown: return 25     // KEYCODE_VOLUME_DOWN
        case .channelUp: return 166     // KEYCODE_CHANNEL_UP
        case .channelDown: return 167   // KEYCODE_CHANNEL_DOWN
        case .playPause: return 85      // KEYCODE_MEDIA_PLAY_PAUSE
        case .mouseClick: return 23     // KEYCODE_DPAD_CENTER
        case .menu: return 82           // KEYCODE_MENU
        case .info: return 165          // KEYCODE_INFO
        case .rewind: return 89         // KEYCODE_MEDIA_REWIND
        case .fastForward: return 90    // KEYCODE_MEDIA_FAST_FORWARD
        case .assist: return 219        // KEYCODE_ASSIST (Google Ассистент / Алиса)
        }
    }

    var keyCode: Int { Int(buttonCode) }
}

struct GamepadSession {
    let sessionId: String
    let port: UInt
    let serviceVersion: String
    let aesKey: String
    let ipv4: [String]
}

/// Linux input-event коды для `Message.Gamepad.KeyboardSignal` (как в официальном приложении Салют).
enum KeyMap {
    static let backspace: Int32 = 14   // KEY_BACKSPACE
    static let enter: Int32 = 28       // KEY_ENTER

    static func androidKeyCode(for linuxKey: Int32) -> Int {
        switch linuxKey {
        case backspace: return 67 // KEYCODE_DEL
        case enter: return 66     // KEYCODE_ENTER
        default: return 66
        }
    }
}
