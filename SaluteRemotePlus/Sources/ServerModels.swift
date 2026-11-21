import Foundation
import Security
import SwiftUI

// MARK: - Типы серверов и модели

enum ServerVendor: String, CaseIterable, Codable, Identifiable, Sendable {
    case dellIDRAC
    case iruBMC
    case genericWeb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dellIDRAC: return "Dell iDRAC"
        case .iruBMC: return "iRU BMC / IPMI"
        case .genericWeb: return "Веб-панель"
        }
    }

    var shortBadge: String {
        switch self {
        case .dellIDRAC: return "DELL iDRAC"
        case .iruBMC: return "iRU BMC"
        case .genericWeb: return "SERVER"
        }
    }

    var defaultUsername: String {
        switch self {
        case .dellIDRAC: return "root"
        case .iruBMC: return "admin"
        case .genericWeb: return "admin"
        }
    }

    var addressPlaceholder: String {
        switch self {
        case .dellIDRAC: return "https://192.168.1.10"
        case .iruBMC: return "https://192.168.1.11"
        case .genericWeb: return "https://192.168.1.20:8006"
        }
    }

    var symbol: String {
        switch self {
        case .dellIDRAC: return "server.rack"
        case .iruBMC: return "cpu"
        case .genericWeb: return "globe"
        }
    }

    var accentColor: Color {
        switch self {
        case .dellIDRAC: return Color(red: 0.00, green: 0.54, blue: 0.88) // Dell Cobalt Blue
        case .iruBMC: return Color(red: 0.08, green: 0.78, blue: 0.96)    // iRU Cyber Cyan
        case .genericWeb: return Color(red: 0.36, green: 0.58, blue: 0.98)
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .dellIDRAC: return Color(red: 0.02, green: 0.34, blue: 0.68)
        case .iruBMC: return Color(red: 0.04, green: 0.45, blue: 0.76)
        case .genericWeb: return Color(red: 0.22, green: 0.32, blue: 0.72)
        }
    }
}

struct ServerProfile: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var vendor: ServerVendor
    var address: String
    var username: String
    var macAddress: String = ""
    var allowUntrustedSSL: Bool = true
    var desktopMode: Bool = true
    var autoFillLogin: Bool = true
    var redfishEnabled: Bool = true
    var notes: String = ""

    /// Нормализованный URL панели управления (если схема не указана — добавляет `https://`).
    var normalizedURL: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }
        return URL(string: withScheme)
    }

    var host: String? {
        normalizedURL?.host
    }

    var effectivePort: Int {
        if let port = normalizedURL?.port {
            return port
        }
        return normalizedURL?.scheme?.lowercased() == "http" ? 80 : 443
    }

    var displayAddress: String {
        guard let url = normalizedURL, let host = url.host else { return address }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    var hasValidMAC: Bool {
        Self.parseMAC(macAddress) != nil
    }

    static func parseMAC(_ raw: String) -> [UInt8]? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: ":")
            .replacingOccurrences(of: ".", with: ":")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 6 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(6)
        for part in parts {
            guard part.count == 2, let byte = UInt8(part, radix: 16) else { return nil }
            bytes.append(byte)
        }
        return bytes
    }
}

// MARK: - Состояние и телеметрия сервера (Redfish / Reachability)

enum ServerReachability: Equatable, Sendable {
    case unknown
    case checking
    case online(latencyMs: Int)
    case offline(reason: String)

    var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .unknown: return "Не проверялся"
        case .checking: return "Проверка…"
        case .online(let ms): return "Онлайн · \(ms) мс"
        case .offline(let reason): return reason
        }
    }
}

struct ServerTelemetry: Equatable, Sendable {
    var reachability: ServerReachability = .unknown
    var powerState: String?
    var health: String?
    var model: String?
    var manufacturer: String?
    var cpuCount: Int?
    var memoryGiB: Int?
    var maxTempC: Int?
    var fanRPM: Int?
    var biosVersion: String?
    var indicatorLED: String?
    var systemPath: String?
    var chassisPath: String?
    var redfishAvailable: Bool = false
    var lastChecked: Date?

    var isPoweredOn: Bool? {
        guard let state = powerState?.lowercased() else { return nil }
        if state == "on" { return true }
        if state == "off" { return false }
        return nil
    }

    var healthColor: Color {
        switch health?.lowercased() {
        case "ok": return Color(red: 0.16, green: 0.86, blue: 0.56)
        case "warning": return Color(red: 1.00, green: 0.72, blue: 0.22)
        case "critical": return Color(red: 1.00, green: 0.28, blue: 0.34)
        default: return .white.opacity(0.65)
        }
    }
}

enum ServerPowerAction: String, CaseIterable, Identifiable, Sendable {
    case on = "On"
    case gracefulShutdown = "GracefulShutdown"
    case gracefulRestart = "GracefulRestart"
    case forceRestart = "ForceRestart"
    case forceOff = "ForceOff"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .on: return "Включить сервер (Power On)"
        case .gracefulShutdown: return "Мягкое выключение (ACPI)"
        case .gracefulRestart: return "Мягкая перезагрузка"
        case .forceRestart: return "Жёсткая перезагрузка (Reset)"
        case .forceOff: return "Принудительно обесточить"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .forceRestart, .forceOff: return true
        default: return false
        }
    }
}

enum NetworkRouteStatus: Equatable, Sendable {
    case vpnAndWiFi(interfaceName: String)
    case vpnOnly(interfaceName: String)
    case localWiFi
    case cellularNoVPN
    case offline

    var title: String {
        switch self {
        case .vpnAndWiFi: return "VPN активен + Wi-Fi"
        case .vpnOnly: return "VPN активен (Kerio / Туннель)"
        case .localWiFi: return "Локальная сеть Wi-Fi"
        case .cellularNoVPN: return "Сотовая сеть · Включите Kerio VPN"
        case .offline: return "Нет подключения к сети"
        }
    }

    var shortBadge: String {
        switch self {
        case .vpnAndWiFi, .vpnOnly: return "VPN"
        case .localWiFi: return "LAN Wi-Fi"
        case .cellularNoVPN: return "Нужен VPN"
        case .offline: return "Офлайн"
        }
    }

    var isReadyForLAN: Bool {
        switch self {
        case .vpnAndWiFi, .vpnOnly, .localWiFi: return true
        case .cellularNoVPN, .offline: return false
        }
    }

    var indicatorColor: Color {
        switch self {
        case .vpnAndWiFi, .vpnOnly: return Color(red: 0.14, green: 0.88, blue: 0.62)
        case .localWiFi: return Color(red: 0.10, green: 0.78, blue: 0.98)
        case .cellularNoVPN: return Color(red: 1.00, green: 0.72, blue: 0.22)
        case .offline: return Color(red: 1.00, green: 0.30, blue: 0.34)
        }
    }
}

// MARK: - Защищённое хранилище паролей серверов в iOS Keychain

enum ServerCredentialStore {
    private static let service = "com.andrey.saluteremoteplus.server-bmc-password"

    static func savePassword(_ password: String, for serverId: UUID) {
        let account = serverId.uuidString
        deletePassword(for: serverId)
        guard !password.isEmpty, let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadPassword(for serverId: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8),
              !password.isEmpty else {
            return nil
        }
        return password
    }

    static func deletePassword(for serverId: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverId.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
