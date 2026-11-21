import Foundation
import SwiftUI

// MARK: - Платформы телевизоров и протоколы управления

enum TVPlatform: String, Codable, CaseIterable, Identifiable {
    case sberSalute
    case androidTV
    case yaOS

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sberSalute: return "Сбер Салют"
        case .androidTV: return "Android TV / Google TV"
        case .yaOS: return "YaOS (Яндекс ТВ)"
        }
    }

    var shortBadge: String {
        switch self {
        case .sberSalute: return "Салют ТВ"
        case .androidTV: return "Android TV"
        case .yaOS: return "YaOS"
        }
    }

    var symbol: String {
        switch self {
        case .sberSalute: return "sparkles.tv.fill"
        case .androidTV: return "tv.fill"
        case .yaOS: return "play.tv.fill"
        }
    }

    var voiceTitle: String {
        switch self {
        case .sberSalute: return "Салют"
        case .androidTV: return "Ассистент"
        case .yaOS: return "Алиса"
        }
    }

    var accentColor: Color {
        switch self {
        case .sberSalute: return SberPalette.brightGreen
        case .androidTV: return Color(red: 0.25, green: 0.62, blue: 1.0)
        case .yaOS: return Color(red: 1.0, green: 0.28, blue: 0.26)
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .sberSalute: return SberPalette.teal
        case .androidTV: return Color(red: 0.14, green: 0.82, blue: 0.94)
        case .yaOS: return Color(red: 1.0, green: 0.78, blue: 0.18)
        }
    }

    var defaultConnectionMethod: TVConnectionMethod {
        switch self {
        case .sberSalute: return .sberCast
        case .androidTV: return .androidTVRemoteV2
        case .yaOS: return .androidTVRemoteV2
        }
    }

    var supportedMethods: [TVConnectionMethod] {
        switch self {
        case .sberSalute: return [.sberCast]
        case .androidTV: return [.androidTVRemoteV2, .adbWiFi]
        case .yaOS: return [.androidTVRemoteV2, .adbWiFi]
        }
    }

    var supportsMouseAndAir: Bool {
        self == .sberSalute
    }

    var supportsFindRemote: Bool {
        self == .sberSalute
    }
}

enum TVConnectionMethod: String, Codable, CaseIterable, Identifiable {
    case sberCast
    case androidTVRemoteV2
    case adbWiFi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sberCast: return "SberCast / StarOS"
        case .androidTVRemoteV2: return "Android TV Remote v2 (PIN)"
        case .adbWiFi: return "ADB по Wi-Fi (порт 5555)"
        }
    }

    var shortLabel: String {
        switch self {
        case .sberCast: return "StarOS"
        case .androidTVRemoteV2: return "Remote v2"
        case .adbWiFi: return "ADB :5555"
        }
    }

    var defaultPort: Int {
        switch self {
        case .sberCast: return 0
        case .androidTVRemoteV2: return 6466
        case .adbWiFi: return 5555
        }
    }

    var defaultPairingPort: Int {
        switch self {
        case .androidTVRemoteV2: return 6467
        default: return 0
        }
    }
}

// MARK: - Сохранённый профиль телевизора

struct SavedTVProfile: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var platform: TVPlatform
    var connectionMethod: TVConnectionMethod
    var host: String
    var remotePort: Int
    var pairingPort: Int
    var sberDeviceId: String?
    var isPaired: Bool
    var lastConnectedAt: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        platform: TVPlatform,
        connectionMethod: TVConnectionMethod? = nil,
        host: String = "",
        remotePort: Int? = nil,
        pairingPort: Int? = nil,
        sberDeviceId: String? = nil,
        isPaired: Bool = false,
        lastConnectedAt: Date? = nil
    ) {
        let resolvedMethod = connectionMethod ?? platform.defaultConnectionMethod
        self.id = id
        self.name = name
        self.platform = platform
        self.connectionMethod = resolvedMethod
        self.host = host
        self.remotePort = remotePort ?? resolvedMethod.defaultPort
        self.pairingPort = pairingPort ?? resolvedMethod.defaultPairingPort
        self.sberDeviceId = sberDeviceId
        self.isPaired = isPaired
        self.lastConnectedAt = lastConnectedAt
    }

    var subtitle: String {
        if platform == .sberSalute {
            return "\(platform.shortBadge) · Wi-Fi"
        }
        let hostPart = host.isEmpty ? "Без IP" : host
        return "\(platform.shortBadge) · \(connectionMethod.shortLabel) · \(hostPart)"
    }
}

// MARK: - Обнаруженный в сети Wi-Fi телевизор

struct DiscoveredTVDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let platform: TVPlatform
    let connectionMethod: TVConnectionMethod
    let host: String
    let port: Int
    let pairingPort: Int
    let sberDeviceId: String?
    let detail: String
}

// MARK: - Быстрый запуск приложений на ТВ (Android TV / Google TV / YaOS / Сбер)

struct TVQuickApp: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let deepLink: String
    let androidPackage: String?
    let tint: Color

    static let presets: [TVQuickApp] = [
        TVQuickApp(
            id: "kinopoisk",
            title: "Кинопоиск",
            symbol: "film.fill",
            deepLink: "https://hd.kinopoisk.ru",
            androidPackage: "ru.kinopoisk.tv",
            tint: Color(red: 1.0, green: 0.42, blue: 0.08)
        ),
        TVQuickApp(
            id: "youtube",
            title: "YouTube",
            symbol: "play.rectangle.fill",
            deepLink: "https://www.youtube.com",
            androidPackage: "com.google.android.youtube.tv",
            tint: Color(red: 0.96, green: 0.16, blue: 0.22)
        ),
        TVQuickApp(
            id: "vkvideo",
            title: "VK Видео",
            symbol: "play.tv.fill",
            deepLink: "https://vkvideo.ru",
            androidPackage: "com.vk.vkvideo.tv",
            tint: Color(red: 0.16, green: 0.52, blue: 1.0)
        ),
        TVQuickApp(
            id: "rutube",
            title: "Rutube",
            symbol: "tv.circle.fill",
            deepLink: "https://rutube.ru",
            androidPackage: "ru.rutube.tv",
            tint: Color(red: 0.10, green: 0.68, blue: 0.92)
        ),
        TVQuickApp(
            id: "okko",
            title: "Okko",
            symbol: "sparkles.tv",
            deepLink: "https://okko.tv",
            androidPackage: "ru.more.play",
            tint: Color(red: 0.55, green: 0.34, blue: 1.0)
        ),
        TVQuickApp(
            id: "ivi",
            title: "Иви",
            symbol: "video.fill",
            deepLink: "https://www.ivi.ru",
            androidPackage: "ru.ivi.client",
            tint: Color(red: 0.92, green: 0.12, blue: 0.38)
        ),
        TVQuickApp(
            id: "wink",
            title: "Wink",
            symbol: "antenna.radiowaves.left.and.right",
            deepLink: "https://wink.ru",
            androidPackage: "ru.rt.video.app.tv",
            tint: Color(red: 1.0, green: 0.50, blue: 0.14)
        ),
        TVQuickApp(
            id: "settings",
            title: "Настройки",
            symbol: "gearshape.fill",
            deepLink: "android.settings.SETTINGS",
            androidPackage: nil,
            tint: Color(red: 0.45, green: 0.56, blue: 0.68)
        )
    ]
}

// MARK: - Локальное хранилище сохранённых телевизоров

enum SavedTVStore {
    private static let key = "SaluteRemotePlus.savedTVProfiles.v1"

    static func load() -> [SavedTVProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedTVProfile].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ profiles: [SavedTVProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
