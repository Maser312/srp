import Foundation
import Security
import SwiftUI

// MARK: - Типы серверов, семейства BMC и возможности контроллера

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

enum ServerBMCFamily: String, Codable, Equatable, Sendable {
    case dellIDRAC9
    case dellIDRAC8
    case dellIDRAC7
    case dellIDRACLegacy
    case iruMegaRAC
    case iruOpenBMC
    case genericRedfish
    case webOnly
    case unknown

    var displayName: String {
        switch self {
        case .dellIDRAC9: return "Dell iDRAC 9"
        case .dellIDRAC8: return "Dell iDRAC 8"
        case .dellIDRAC7: return "Dell iDRAC 7"
        case .dellIDRACLegacy: return "Dell iDRAC (Legacy)"
        case .iruMegaRAC: return "iRU · AMI MegaRAC"
        case .iruOpenBMC: return "iRU · OpenBMC"
        case .genericRedfish: return "Redfish BMC"
        case .webOnly: return "Веб-интерфейс BMC"
        case .unknown: return "Определяется…"
        }
    }

    var shortBadge: String {
        switch self {
        case .dellIDRAC9: return "iDRAC 9"
        case .dellIDRAC8: return "iDRAC 8"
        case .dellIDRAC7: return "iDRAC 7"
        case .dellIDRACLegacy: return "iDRAC Legacy"
        case .iruMegaRAC: return "MegaRAC"
        case .iruOpenBMC: return "OpenBMC"
        case .genericRedfish: return "Redfish"
        case .webOnly: return "Web BMC"
        case .unknown: return "BMC"
        }
    }

    var suggestedVendor: ServerVendor {
        switch self {
        case .dellIDRAC9, .dellIDRAC8, .dellIDRAC7, .dellIDRACLegacy:
            return .dellIDRAC
        case .iruMegaRAC, .iruOpenBMC:
            return .iruBMC
        case .genericRedfish, .webOnly, .unknown:
            return .genericWeb
        }
    }
}

// MARK: - Действия питания и разовой загрузки (динамически по Redfish AllowableValues)

enum ServerPowerAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case on = "On"
    case gracefulShutdown = "GracefulShutdown"
    case gracefulRestart = "GracefulRestart"
    case forceRestart = "ForceRestart"
    case forceOff = "ForceOff"
    case powerCycle = "PowerCycle"
    case pushPowerButton = "PushPowerButton"
    case nmi = "Nmi"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .on: return "Включить сервер (Power On)"
        case .gracefulShutdown: return "Мягкое выключение (ACPI)"
        case .gracefulRestart: return "Мягкая перезагрузка"
        case .forceRestart: return "Жёсткая перезагрузка (Reset)"
        case .forceOff: return "Принудительно обесточить"
        case .powerCycle: return "Цикл питания (Power Cycle)"
        case .pushPowerButton: return "Нажатие кнопки Power"
        case .nmi: return "Послать NMI (Дамп ОС)"
        }
    }

    var shortTitle: String {
        switch self {
        case .on: return "Включить"
        case .gracefulShutdown: return "Выключить (ACPI)"
        case .gracefulRestart: return "Перезагрузка"
        case .forceRestart: return "Жёсткий Reset"
        case .forceOff: return "Обесточить"
        case .powerCycle: return "Power Cycle"
        case .pushPowerButton: return "Кнопка Power"
        case .nmi: return "NMI"
        }
    }

    var symbol: String {
        switch self {
        case .on: return "power"
        case .gracefulShutdown: return "power.circle"
        case .gracefulRestart: return "arrow.clockwise"
        case .forceRestart: return "bolt.trianglebadge.exclamationmark.fill"
        case .forceOff: return "bolt.slash.fill"
        case .powerCycle: return "arrow.triangle.2.circlepath"
        case .pushPowerButton: return "hand.tap.fill"
        case .nmi: return "waveform.path.ecg"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .forceRestart, .forceOff, .powerCycle, .nmi: return true
        default: return false
        }
    }

    var requiresConfirmation: Bool {
        self != .on
    }

    var tintColor: Color {
        switch self {
        case .on: return Color(red: 0.14, green: 0.88, blue: 0.60)
        case .gracefulShutdown: return Color(red: 1.00, green: 0.72, blue: 0.22)
        case .gracefulRestart, .pushPowerButton: return Color(red: 0.08, green: 0.78, blue: 0.96)
        case .forceRestart, .powerCycle: return Color(red: 1.00, green: 0.52, blue: 0.20)
        case .forceOff, .nmi: return Color(red: 1.00, green: 0.28, blue: 0.34)
        }
    }
}

enum ServerBootTarget: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "None"
    case biosSetup = "BiosSetup"
    case pxe = "Pxe"
    case usb = "Usb"
    case hdd = "Hdd"
    case cd = "Cd"
    case uefiTarget = "UefiTarget"
    case utilities = "Utilities"
    case diags = "Diags"
    case sdCard = "SDCard"
    case floppy = "Floppy"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Обычная загрузка"
        case .biosSetup: return "BIOS / UEFI Setup"
        case .pxe: return "Сеть (PXE)"
        case .usb: return "USB-накопитель"
        case .hdd: return "Жёсткий диск (HDD)"
        case .cd: return "CD / Virtual ISO"
        case .uefiTarget: return "UEFI Boot"
        case .utilities: return "Lifecycle / Утилиты"
        case .diags: return "Диагностика"
        case .sdCard: return "SD-карта"
        case .floppy: return "Виртуальный Floppy"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "play.circle"
        case .biosSetup: return "gearshape.2.fill"
        case .pxe: return "network"
        case .usb: return "externaldrive.connected.to.line.below"
        case .hdd: return "internaldrive.fill"
        case .cd: return "opticaldisc"
        case .uefiTarget: return "cpu"
        case .utilities: return "wrench.and.screwdriver.fill"
        case .diags: return "stethoscope"
        case .sdCard: return "sdcard.fill"
        case .floppy: return "externaldrive"
        }
    }
}

// MARK: - Журналы событий и обнаруженные возможности BMC

struct ServerLogServiceInfo: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var path: String
    var entriesPath: String
    var canClear: Bool
    var clearActionPath: String?
}

struct ServerCapabilities: Codable, Equatable, Sendable {
    var bmcFamily: ServerBMCFamily = .unknown
    var bmcName: String?
    var bmcFirmwareVersion: String?
    var bmcModel: String?
    var redfishVersion: String?
    var redfishSupported: Bool = false

    var systemPath: String?
    var chassisPath: String?
    var managerPath: String?
    var resetActionPath: String?
    var managerResetActionPath: String?

    var allowedResetTypes: [ServerPowerAction] = []
    var allowedManagerResetTypes: [String] = []
    var allowedBootTargets: [ServerBootTarget] = []

    var supportsBootOverride: Bool = false
    var supportsIndicatorLED: Bool = false
    var usesLocationIndicatorActive: Bool = false
    var supportsThermal: Bool = false
    var supportsPowerMetrics: Bool = false
    var supportsStorage: Bool = false
    var logServices: [ServerLogServiceInfo] = []
    var detectedAt: Date?

    var hasAnySensors: Bool {
        supportsThermal || supportsPowerMetrics || supportsStorage
    }

    var hasLogs: Bool {
        !logServices.isEmpty
    }

    var supportsManagerReset: Bool {
        managerResetActionPath != nil && !allowedManagerResetTypes.isEmpty
    }

    var shortVersionLabel: String? {
        guard bmcFamily != .unknown else { return nil }
        if let fw = bmcFirmwareVersion, !fw.isEmpty {
            return "\(bmcFamily.shortBadge) · v\(fw)"
        }
        if let rf = redfishVersion, !rf.isEmpty {
            return "\(bmcFamily.shortBadge) · RF \(rf)"
        }
        return bmcFamily.shortBadge
    }

    var fullDescriptor: String {
        var parts: [String] = [bmcFamily.displayName]
        if let fw = bmcFirmwareVersion, !fw.isEmpty {
            parts.append("FW \(fw)")
        }
        if let rf = redfishVersion, !rf.isEmpty {
            parts.append("Redfish \(rf)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Профиль сервера (обратная совместимость декодирования)

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
    var detectedCapabilities: ServerCapabilities? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, vendor, address, username, macAddress
        case allowUntrustedSSL, desktopMode, autoFillLogin, redfishEnabled, notes
        case detectedCapabilities
    }

    init(
        id: UUID = UUID(),
        name: String,
        vendor: ServerVendor,
        address: String,
        username: String,
        macAddress: String = "",
        allowUntrustedSSL: Bool = true,
        desktopMode: Bool = true,
        autoFillLogin: Bool = true,
        redfishEnabled: Bool = true,
        notes: String = "",
        detectedCapabilities: ServerCapabilities? = nil
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.address = address
        self.username = username
        self.macAddress = macAddress
        self.allowUntrustedSSL = allowUntrustedSSL
        self.desktopMode = desktopMode
        self.autoFillLogin = autoFillLogin
        self.redfishEnabled = redfishEnabled
        self.notes = notes
        self.detectedCapabilities = detectedCapabilities
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        vendor = try c.decode(ServerVendor.self, forKey: .vendor)
        address = try c.decode(String.self, forKey: .address)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        macAddress = try c.decodeIfPresent(String.self, forKey: .macAddress) ?? ""
        allowUntrustedSSL = try c.decodeIfPresent(Bool.self, forKey: .allowUntrustedSSL) ?? true
        desktopMode = try c.decodeIfPresent(Bool.self, forKey: .desktopMode) ?? true
        autoFillLogin = try c.decodeIfPresent(Bool.self, forKey: .autoFillLogin) ?? true
        redfishEnabled = try c.decodeIfPresent(Bool.self, forKey: .redfishEnabled) ?? true
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        detectedCapabilities = try c.decodeIfPresent(ServerCapabilities.self, forKey: .detectedCapabilities)
    }

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

// MARK: - Датчики, диски и журналы

struct ServerTempSensor: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var readingC: Double
    var upperWarningC: Double?
    var upperCriticalC: Double?
    var health: String?
}

struct ServerFanSensor: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var reading: Int
    var units: String
    var health: String?
}

struct ServerVoltageSensor: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var readingVolts: Double
    var health: String?
}

struct ServerPSUSensor: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var model: String?
    var powerOutputWatts: Int?
    var capacityWatts: Int?
    var health: String?
    var state: String?
}

struct ServerDriveInfo: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var model: String?
    var mediaType: String?
    var capacityGiB: Int?
    var health: String?
    var state: String?
}

struct ServerLogEntry: Identifiable, Equatable, Sendable {
    var id: String
    var created: String?
    var severity: String?
    var message: String
    var sensorType: String?
    var entryCode: String?
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
    var serialNumber: String?
    var sku: String?
    var hostname: String?
    var cpuCount: Int?
    var memoryGiB: Int?
    var maxTempC: Int?
    var fanRPM: Int?
    var powerConsumedWatts: Int?
    var powerCapacityWatts: Int?
    var biosVersion: String?
    var indicatorLED: String?
    var bootOverrideTarget: String?
    var bootOverrideEnabled: String?
    var systemPath: String?
    var chassisPath: String?
    var redfishAvailable: Bool = false
    var capabilities: ServerCapabilities?
    var temperatures: [ServerTempSensor] = []
    var fans: [ServerFanSensor] = []
    var voltages: [ServerVoltageSensor] = []
    var powerSupplies: [ServerPSUSensor] = []
    var drives: [ServerDriveInfo] = []
    var lastChecked: Date?

    var isPoweredOn: Bool? {
        guard let state = powerState?.lowercased() else { return nil }
        if state == "on" { return true }
        if state == "off" { return false }
        return nil
    }

    var isLocatorLit: Bool {
        let low = indicatorLED?.lowercased() ?? ""
        return low == "lit" || low == "blinking" || low == "true"
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

// MARK: - Автопоиск BMC / iDRAC в локальной сети / Kerio VPN

struct DiscoveredBMC: Identifiable, Equatable, Sendable {
    var id: String { "\(ip):\(port)" }
    var ip: String
    var port: Int
    var scheme: String
    var vendor: ServerVendor
    var bmcFamily: ServerBMCFamily
    var suggestedName: String
    var detectedTitle: String?
    var redfishVersion: String?
    var redfishSupported: Bool
    var isConfirmedBMC: Bool
    var latencyMs: Int

    var addressURLString: String {
        if scheme == "https" && port == 443 {
            return "https://\(ip)"
        }
        if scheme == "http" && port == 80 {
            return "http://\(ip)"
        }
        return "\(scheme)://\(ip):\(port)"
    }
}

struct ServerEditorPrefill: Identifiable, Equatable, Sendable {
    let id = UUID()
    var name: String
    var vendor: ServerVendor
    var address: String
    var username: String
    var redfishEnabled: Bool
    var notes: String
}

// MARK: - Статус сетевого маршрута (Wi-Fi / Kerio VPN)

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
