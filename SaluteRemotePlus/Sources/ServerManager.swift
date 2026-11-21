import Foundation
import Network
import LocalAuthentication
import Darwin

// MARK: - Изолированный TLS-делегат (доверяет самоподписанному SSL только для выбранного хоста сервера)

final class ScopedServerURLDelegate: NSObject, URLSessionDelegate {
    private let allowedHost: String
    private let allowUntrustedSSL: Bool

    init(allowedHost: String, allowUntrustedSSL: Bool) {
        self.allowedHost = allowedHost.lowercased()
        self.allowUntrustedSSL = allowUntrustedSSL
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           allowUntrustedSSL,
           challenge.protectionSpace.host.lowercased() == allowedHost,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

// MARK: - Менеджер серверов (Dell iDRAC / iRU BMC / Redfish / WoL / VPN-мониторинг)

@MainActor
final class ServerManager: ObservableObject {
    @Published private(set) var servers: [ServerProfile] = []
    @Published private(set) var telemetry: [UUID: ServerTelemetry] = [:]
    @Published private(set) var networkRoute: NetworkRouteStatus = .offline
    @Published private(set) var isRefreshingAll = false
    @Published var requireBiometricLock: Bool {
        didSet {
            UserDefaults.standard.set(requireBiometricLock, forKey: biometricLockKey)
            if !requireBiometricLock {
                isUnlocked = true
            }
        }
    }
    @Published private(set) var isUnlocked: Bool = true
    @Published private(set) var actionNotice: String?

    private let serversStorageKey = "SaluteRemotePlus.serverProfiles.v1"
    private let biometricLockKey = "SaluteRemotePlus.serverBiometricLock.v1"

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.andrey.saluteremoteplus.server-netmon")
    private var monitorStarted = false
    private var noticeTask: Task<Void, Never>?

    init() {
        let lockEnabled = UserDefaults.standard.bool(forKey: biometricLockKey)
        self.requireBiometricLock = lockEnabled
        self.isUnlocked = !lockEnabled
        loadProfiles()
    }

    var onlineCount: Int {
        servers.filter { telemetry[$0.id]?.reachability.isOnline == true }.count
    }

    // MARK: - Жизненный цикл и мониторинг сети / Kerio VPN

    func startMonitoring() {
        guard !monitorStarted else {
            refreshNetworkRoute()
            return
        }
        monitorStarted = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let route = ServerNetworkHelper.detectNetworkRoute(from: path)
            Task { @MainActor [weak self] in
                self?.networkRoute = route
            }
        }
        pathMonitor.start(queue: monitorQueue)
        refreshNetworkRoute()
    }

    func refreshNetworkRoute() {
        networkRoute = ServerNetworkHelper.detectNetworkRoute(from: pathMonitor.currentPath)
    }

    func lockIfRequired() {
        if requireBiometricLock {
            isUnlocked = false
        }
    }

    func unlockWithBiometrics() {
        let context = LAContext()
        var error: NSError?
        let reason = "Подтвердите личность для доступа к панелям серверов Dell / iRU"
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        context.evaluatePolicy(policy, localizedReason: reason) { [weak self] success, _ in
            Task { @MainActor [weak self] in
                if success {
                    self?.isUnlocked = true
                }
            }
        }
    }

    // MARK: - CRUD профилей (пароли хранятся исключительно в Keychain)

    func saveServer(_ profile: ServerProfile, password: String?) {
        if let idx = servers.firstIndex(where: { $0.id == profile.id }) {
            servers[idx] = profile
        } else {
            servers.append(profile)
        }
        if let password = password {
            if !password.isEmpty {
                ServerCredentialStore.savePassword(password, for: profile.id)
            }
        }
        persistProfiles()
        Task {
            await checkServer(profile)
        }
    }

    func deleteServer(_ profile: ServerProfile) {
        servers.removeAll { $0.id == profile.id }
        telemetry.removeValue(forKey: profile.id)
        ServerCredentialStore.deletePassword(for: profile.id)
        persistProfiles()
    }

    func password(for profile: ServerProfile) -> String {
        ServerCredentialStore.loadPassword(for: profile.id) ?? ""
    }

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: serversStorageKey),
              let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) else {
            return
        }
        servers = decoded
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: serversStorageKey)
    }

    // MARK: - Проверка доступности и Redfish-телеметрии (Dell iDRAC + iRU BMC)

    func refreshAllServers() {
        refreshNetworkRoute()
        guard !servers.isEmpty else { return }
        isRefreshingAll = true
        let snapshot = servers
        Task {
            await withTaskGroup(of: Void.self) { group in
                for server in snapshot {
                    group.addTask { [weak self] in
                        await self?.checkServer(server)
                    }
                }
            }
            isRefreshingAll = false
        }
    }

    func checkServer(_ profile: ServerProfile) async {
        guard let url = profile.normalizedURL, let host = profile.host else {
            var state = telemetry[profile.id] ?? ServerTelemetry()
            state.reachability = .offline(reason: "Неверный адрес")
            telemetry[profile.id] = state
            return
        }

        var checkingState = telemetry[profile.id] ?? ServerTelemetry()
        checkingState.reachability = .checking
        telemetry[profile.id] = checkingState

        let startTime = Date()
        let reachable = await ServerNetworkHelper.probeTCP(host: host, port: profile.effectivePort, timeoutSeconds: 4.0)
        let latencyMs = max(1, Int(Date().timeIntervalSince(startTime) * 1000.0))

        guard reachable else {
            var offline = telemetry[profile.id] ?? ServerTelemetry()
            offline.reachability = .offline(reason: networkRoute.isReadyForLAN ? "Недоступен" : "Нет VPN / LAN")
            offline.lastChecked = Date()
            telemetry[profile.id] = offline
            return
        }

        var updated = telemetry[profile.id] ?? ServerTelemetry()
        updated.reachability = .online(latencyMs: latencyMs)
        updated.lastChecked = Date()
        telemetry[profile.id] = updated

        // Если включён Redfish и задан логин/пароль — забираем живой статус Dell iDRAC / iRU BMC
        if profile.redfishEnabled, !profile.username.isEmpty {
            let pass = password(for: profile)
            if !pass.isEmpty {
                if let rf = await fetchRedfishTelemetry(profile: profile, baseURL: url, password: pass) {
                    var merged = telemetry[profile.id] ?? updated
                    merged.reachability = .online(latencyMs: latencyMs)
                    merged.redfishAvailable = true
                    merged.powerState = rf.powerState
                    merged.health = rf.health
                    merged.model = rf.model
                    merged.manufacturer = rf.manufacturer
                    merged.cpuCount = rf.cpuCount
                    merged.memoryGiB = rf.memoryGiB
                    merged.maxTempC = rf.maxTempC
                    merged.fanRPM = rf.fanRPM
                    merged.biosVersion = rf.biosVersion
                    merged.indicatorLED = rf.indicatorLED
                    merged.systemPath = rf.systemPath
                    merged.chassisPath = rf.chassisPath
                    merged.lastChecked = Date()
                    telemetry[profile.id] = merged
                }
            }
        }
    }

    // MARK: - Управление питанием и индикатором через DMTF Redfish API

    func sendPowerAction(_ action: ServerPowerAction, to profile: ServerProfile) async {
        guard let baseURL = profile.normalizedURL, let host = profile.host else {
            showNotice("Некорректный адрес сервера")
            return
        }
        let pass = password(for: profile)
        guard !profile.username.isEmpty, !pass.isEmpty else {
            showNotice("Укажите логин и пароль для управления питанием")
            return
        }

        let session = makeSession(host: host, allowUntrustedSSL: profile.allowUntrustedSSL, timeout: 8)
        defer { session.invalidateAndCancel() }

        let systemPath: String
        if let cached = telemetry[profile.id]?.systemPath {
            systemPath = cached
        } else if let discovered = await discoverFirstMemberPath(
            session: session,
            baseURL: baseURL,
            collectionPath: "/redfish/v1/Systems",
            username: profile.username,
            password: pass
        ) {
            systemPath = discovered
        } else {
            showNotice("Redfish API недоступен — выполните действие через веб-панель")
            return
        }

        guard let resetURL = resolveRedfishURL(baseURL: baseURL, path: "\(systemPath)/Actions/ComputerSystem.Reset") else {
            showNotice("Ошибка адреса команды питания")
            return
        }

        var request = URLRequest(url: resetURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(basicAuthHeader(username: profile.username, password: pass), forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["ResetType": action.rawValue])

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                showNotice("\(profile.name): отправлено «\(action.title)»")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await checkServer(profile)
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                showNotice("BMC отклонил команду питания (HTTP \(code))")
            }
        } catch {
            showNotice("Не удалось отправить команду питания")
        }
    }

    func toggleLocatorLED(for profile: ServerProfile) async {
        guard let baseURL = profile.normalizedURL, let host = profile.host else { return }
        let pass = password(for: profile)
        guard !profile.username.isEmpty, !pass.isEmpty else {
            showNotice("Укажите логин и пароль сервера")
            return
        }

        let session = makeSession(host: host, allowUntrustedSSL: profile.allowUntrustedSSL, timeout: 8)
        defer { session.invalidateAndCancel() }

        let targetPath: String?
        if let chassis = telemetry[profile.id]?.chassisPath {
            targetPath = chassis
        } else if let system = telemetry[profile.id]?.systemPath {
            targetPath = system
        } else {
            targetPath = await discoverFirstMemberPath(
                session: session,
                baseURL: baseURL,
                collectionPath: "/redfish/v1/Chassis",
                username: profile.username,
                password: pass
            )
        }

        guard let path = targetPath, let url = resolveRedfishURL(baseURL: baseURL, path: path) else {
            showNotice("Локатор LED недоступен по Redfish")
            return
        }

        let currentLit = (telemetry[profile.id]?.indicatorLED?.lowercased() ?? "") == "lit"
            || (telemetry[profile.id]?.indicatorLED?.lowercased() ?? "") == "blinking"
        let nextState = currentLit ? "Off" : "Lit"

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(username: profile.username, password: pass), forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["IndicatorLED": nextState])

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                var state = telemetry[profile.id] ?? ServerTelemetry()
                state.indicatorLED = nextState
                telemetry[profile.id] = state
                showNotice(nextState == "Lit" ? "Индикатор локатора включён" : "Индикатор локатора выключен")
            } else {
                showNotice("Этот BMC не поддерживает смену LED по Redfish")
            }
        } catch {
            showNotice("Ошибка переключения локатора LED")
        }
    }

    // MARK: - Wake-on-LAN (UDP Magic Packet)

    func sendWakeOnLAN(to profile: ServerProfile) {
        guard let macBytes = ServerProfile.parseMAC(profile.macAddress) else {
            showNotice("Укажите корректный MAC-адрес в настройках сервера")
            return
        }

        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }

        let targets = buildWoLTargets(host: profile.host)
        DispatchQueue.global(qos: .userInitiated).async {
            for targetIP in targets {
                ServerNetworkHelper.sendUDPMagicPacket(packet, to: targetIP, port: 9)
                ServerNetworkHelper.sendUDPMagicPacket(packet, to: targetIP, port: 7)
            }
        }
        showNotice("Wake-on-LAN отправлен на \(profile.name)")
    }

    // MARK: - Внутренние Redfish-запросы

    private func fetchRedfishTelemetry(
        profile: ServerProfile,
        baseURL: URL,
        password: String
    ) async -> ServerTelemetry? {
        guard let host = profile.host else { return nil }
        let session = makeSession(host: host, allowUntrustedSSL: profile.allowUntrustedSSL, timeout: 6)
        defer { session.invalidateAndCancel() }

        guard let systemPath = await discoverFirstMemberPath(
            session: session,
            baseURL: baseURL,
            collectionPath: "/redfish/v1/Systems",
            username: profile.username,
            password: password
        ) else {
            return nil
        }

        guard let sysDict = await fetchRedfishJSON(
            session: session,
            baseURL: baseURL,
            path: systemPath,
            username: profile.username,
            password: password
        ) else {
            return nil
        }

        var result = ServerTelemetry()
        result.redfishAvailable = true
        result.systemPath = systemPath
        result.powerState = sysDict["PowerState"] as? String
        result.model = (sysDict["Model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.manufacturer = (sysDict["Manufacturer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.biosVersion = sysDict["BiosVersion"] as? String
        result.indicatorLED = sysDict["IndicatorLED"] as? String

        if let statusDict = sysDict["Status"] as? [String: Any] {
            result.health = (statusDict["HealthRollup"] as? String) ?? (statusDict["Health"] as? String)
        }
        if let proc = sysDict["ProcessorSummary"] as? [String: Any] {
            if let count = proc["Count"] as? Int {
                result.cpuCount = count
            }
        }
        if let mem = sysDict["MemorySummary"] as? [String: Any] {
            if let gib = mem["TotalSystemMemoryGiB"] as? Int {
                result.memoryGiB = gib
            } else if let gibDouble = mem["TotalSystemMemoryGiB"] as? Double {
                result.memoryGiB = Int(gibDouble.rounded())
            }
        }

        if let chassisPath = await discoverFirstMemberPath(
            session: session,
            baseURL: baseURL,
            collectionPath: "/redfish/v1/Chassis",
            username: profile.username,
            password: password
        ) {
            result.chassisPath = chassisPath
            if let chassisDict = await fetchRedfishJSON(
                session: session,
                baseURL: baseURL,
                path: chassisPath,
                username: profile.username,
                password: password
            ) {
                if result.indicatorLED == nil {
                    result.indicatorLED = chassisDict["IndicatorLED"] as? String
                }
                if result.health == nil, let st = chassisDict["Status"] as? [String: Any] {
                    result.health = (st["HealthRollup"] as? String) ?? (st["Health"] as? String)
                }
            }

            if let thermalDict = await fetchRedfishJSON(
                session: session,
                baseURL: baseURL,
                path: "\(chassisPath)/Thermal",
                username: profile.username,
                password: password
            ) {
                if let temps = thermalDict["Temperatures"] as? [[String: Any]] {
                    let readings: [Int] = temps.compactMap { item in
                        if let v = item["ReadingCelsius"] as? Int, v > 0, v < 130 { return v }
                        if let d = item["ReadingCelsius"] as? Double, d > 0, d < 130 { return Int(d.rounded()) }
                        return nil
                    }
                    result.maxTempC = readings.max()
                }
                if let fans = thermalDict["Fans"] as? [[String: Any]] {
                    let rpms: [Int] = fans.compactMap { item in
                        if let v = item["Reading"] as? Int, v > 0 { return v }
                        if let d = item["Reading"] as? Double, d > 0 { return Int(d.rounded()) }
                        return nil
                    }
                    if !rpms.isEmpty {
                        result.fanRPM = rpms.reduce(0, +) / rpms.count
                    }
                }
            }
        }

        return result
    }

    private func discoverFirstMemberPath(
        session: URLSession,
        baseURL: URL,
        collectionPath: String,
        username: String,
        password: String
    ) async -> String? {
        guard let dict = await fetchRedfishJSON(
            session: session,
            baseURL: baseURL,
            path: collectionPath,
            username: username,
            password: password
        ) else { return nil }

        if let members = dict["Members"] as? [[String: Any]],
           let first = members.first?["@odata.id"] as? String,
           !first.isEmpty {
            return first
        }
        return nil
    }

    private func fetchRedfishJSON(
        session: URLSession,
        baseURL: URL,
        path: String,
        username: String,
        password: String
    ) async -> [String: Any]? {
        guard let url = resolveRedfishURL(baseURL: baseURL, path: path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(basicAuthHeader(username: username, password: password), forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } catch {
            return nil
        }
    }

    private func resolveRedfishURL(baseURL: URL, path: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func makeSession(host: String, allowUntrustedSSL: Bool, timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 2
        let delegate = ScopedServerURLDelegate(allowedHost: host, allowUntrustedSSL: allowUntrustedSSL)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    private func basicAuthHeader(username: String, password: String) -> String {
        let raw = "\(username):\(password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    // MARK: - Уведомления

    func showNotice(_ text: String) {
        noticeTask?.cancel()
        actionNotice = text
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.actionNotice == text {
                    self?.actionNotice = nil
                }
            }
        }
    }

    private func buildWoLTargets(host: String?) -> [String] {
        var result: [String] = ["255.255.255.255"]
        if let host = host {
            let octets = host.split(separator: ".")
            if octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) {
                let subnetBroadcast = "\(octets[0]).\(octets[1]).\(octets[2]).255"
                if !result.contains(subnetBroadcast) {
                    result.append(subnetBroadcast)
                }
            }
        }
        return result
    }
}

// MARK: - Неизолированные сетевые утилиты (TCP-пинг, определение Kerio VPN, WoL UDP)

private final class TCPProbeState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Bool, Never>

    init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ value: Bool) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()

        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(returning: value)
    }
}

private enum ServerNetworkHelper {
    static func probeTCP(host: String, port: Int, timeoutSeconds: Double) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.andrey.saluteremoteplus.tcp-probe")
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let state = TCPProbeState(connection: conn, continuation: continuation)

            conn.stateUpdateHandler = { connState in
                switch connState {
                case .ready:
                    state.finish(true)
                case .failed, .cancelled:
                    state.finish(false)
                default:
                    break
                }
            }

            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                state.finish(false)
            }
        }
    }

    static func detectNetworkRoute(from path: NWPath) -> NetworkRouteStatus {
        guard path.status == .satisfied else { return .offline }
        let vpnInterface = activeVPNInterfaceName()
        let usesWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)

        if let vpn = vpnInterface {
            return usesWiFi ? .vpnAndWiFi(interfaceName: vpn) : .vpnOnly(interfaceName: vpn)
        }
        if usesWiFi {
            return .localWiFi
        }
        return .cellularNoVPN
    }

    /// Проверяет наличие активного VPN-туннеля (Kerio Control VPN / IPSec / OpenVPN / WireGuard)
    /// по интерфейсам `utun*`, `ipsec*`, `ppp*` с назначенным не-link-local IPv4-адресом.
    static func activeVPNInterfaceName() -> String? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else { return nil }
        defer { freeifaddrs(ifaddrPointer) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            if isUp,
               let namePtr = current.pointee.ifa_name,
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: namePtr)
                if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if !ip.isEmpty && !ip.hasPrefix("169.254.") && !ip.hasPrefix("127.") {
                            return name
                        }
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }
        return nil
    }

    static func sendUDPMagicPacket(_ packet: [UInt8], to ip: String, port: UInt16) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var broadcast: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return }

        packet.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    _ = sendto(fd, baseAddress, packet.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
