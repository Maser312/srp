import Foundation
import Network
import CFNetwork
import LocalAuthentication
import Darwin

// MARK: - Изолированный TLS-делегат (доверяет самоподписанному SSL только для выбранного хоста сервера)

final class ScopedServerURLDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let allowedHost: String
    private let allowUntrustedSSL: Bool
    private let blockCrossHostRedirect: Bool

    init(allowedHost: String, allowUntrustedSSL: Bool, blockCrossHostRedirect: Bool = false) {
        self.allowedHost = allowedHost.lowercased()
        self.allowUntrustedSSL = allowUntrustedSSL
        self.blockCrossHostRedirect = blockCrossHostRedirect
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

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if blockCrossHostRedirect {
            if let newHost = request.url?.host?.lowercased(), newHost != allowedHost {
                completionHandler(nil)
                return
            }
        }
        completionHandler(request)
    }
}

// MARK: - Менеджер серверов (Dell iDRAC / iRU BMC / Автоопределение возможностей / Автопоиск в сети)

@MainActor
final class ServerManager: ObservableObject {
    @Published private(set) var servers: [ServerProfile] = []
    @Published private(set) var telemetry: [UUID: ServerTelemetry] = [:]
    @Published private(set) var logsByServer: [UUID: [String: [ServerLogEntry]]] = [:]
    @Published private(set) var loadingSensorsFor: Set<UUID> = []
    @Published private(set) var loadingLogsFor: Set<String> = []
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

    // Автопоиск iDRAC / BMC в локальной сети / Kerio VPN
    @Published private(set) var isScanningNetwork = false
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var scanStatusText: String = ""
    @Published private(set) var discoveredBMCs: [DiscoveredBMC] = []
    @Published private(set) var suggestedSubnets: [String] = []

    private let serversStorageKey = "SaluteRemotePlus.serverProfiles.v1"
    private let biometricLockKey = "SaluteRemotePlus.serverBiometricLock.v1"

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.andrey.saluteremoteplus.server-netmon")
    private var monitorStarted = false
    private var noticeTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var bonjourBrowser: NWBrowser?

    init() {
        let lockEnabled = UserDefaults.standard.bool(forKey: biometricLockKey)
        self.requireBiometricLock = lockEnabled
        self.isUnlocked = !lockEnabled
        loadProfiles()
    }

    var isMonitoring: Bool {
        monitorStarted
    }

    var onlineCount: Int {
        servers.filter { telemetry[$0.id]?.reachability.isOnline == true }.count
    }

    func capabilities(for server: ServerProfile) -> ServerCapabilities? {
        if let live = telemetry[server.id]?.capabilities {
            return live
        }
        return server.detectedCapabilities
    }

    func isAlreadySaved(ip: String) -> Bool {
        let normalized = ip.lowercased()
        return servers.contains { ($0.host?.lowercased() ?? "") == normalized }
    }

    // MARK: - Жизненный цикл и мониторинг сети / Kerio VPN

    func startMonitoring() {
        guard !monitorStarted else {
            refreshNetworkRoute()
            refreshSuggestedSubnets()
            return
        }
        monitorStarted = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let route = ServerNetworkHelper.detectNetworkRoute(from: path)
            Task { @MainActor [weak self] in
                self?.networkRoute = route
                self?.refreshSuggestedSubnets()
            }
        }
        pathMonitor.start(queue: monitorQueue)
        refreshNetworkRoute()
        refreshSuggestedSubnets()
    }

    func refreshNetworkRoute() {
        networkRoute = ServerNetworkHelper.detectNetworkRoute(from: pathMonitor.currentPath)
    }

    func refreshSuggestedSubnets() {
        var subnets: [String] = []

        for localIP in ServerNetworkHelper.detectLocalIPv4Addresses() {
            if let cidr = ServerNetworkHelper.subnetCIDR(fromIP: localIP), !subnets.contains(cidr) {
                subnets.append(cidr)
            }
        }

        for server in servers {
            if let host = server.host, let cidr = ServerNetworkHelper.subnetCIDR(fromIP: host), !subnets.contains(cidr) {
                subnets.append(cidr)
            }
        }

        if subnets.isEmpty {
            subnets = ["192.168.1.0/24", "192.168.0.0/24", "10.0.0.0/24"]
        }
        suggestedSubnets = subnets
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
        var updatedProfile = profile
        if let idx = servers.firstIndex(where: { $0.id == profile.id }) {
            if updatedProfile.address != servers[idx].address || updatedProfile.username != servers[idx].username {
                updatedProfile.detectedCapabilities = nil
            } else if updatedProfile.detectedCapabilities == nil {
                updatedProfile.detectedCapabilities = servers[idx].detectedCapabilities
            }
            servers[idx] = updatedProfile
        } else {
            servers.append(updatedProfile)
        }
        if let password = password, !password.isEmpty {
            ServerCredentialStore.savePassword(password, for: updatedProfile.id)
        }
        persistProfiles()
        refreshSuggestedSubnets()
        Task {
            await checkServer(updatedProfile, deepProbe: true)
        }
    }

    func deleteServer(_ profile: ServerProfile) {
        servers.removeAll { $0.id == profile.id }
        telemetry.removeValue(forKey: profile.id)
        logsByServer.removeValue(forKey: profile.id)
        ServerCredentialStore.deletePassword(for: profile.id)
        persistProfiles()
        refreshSuggestedSubnets()
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
        for server in decoded {
            if let caps = server.detectedCapabilities {
                var state = ServerTelemetry()
                state.capabilities = caps
                state.redfishAvailable = caps.redfishSupported
                state.systemPath = caps.systemPath
                state.chassisPath = caps.chassisPath
                telemetry[server.id] = state
            }
        }
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: serversStorageKey)
    }

    private func persistDetectedCapabilities(_ caps: ServerCapabilities, for serverId: UUID, autoUpdateVendor: Bool = false) {
        guard let idx = servers.firstIndex(where: { $0.id == serverId }) else { return }
        servers[idx].detectedCapabilities = caps
        if autoUpdateVendor && servers[idx].vendor == .genericWeb {
            let suggested = caps.bmcFamily.suggestedVendor
            if suggested != .genericWeb {
                servers[idx].vendor = suggested
            }
        }
        persistProfiles()
    }

    // MARK: - Проверка доступности + автоопределение версии и возможностей iDRAC / BMC

    func refreshAllServers() {
        refreshNetworkRoute()
        guard !servers.isEmpty else { return }
        isRefreshingAll = true
        let snapshot = servers
        Task {
            await withTaskGroup(of: Void.self) { group in
                for server in snapshot {
                    let needsDeepProbe = (server.detectedCapabilities == nil)
                    group.addTask { [weak self] in
                        await self?.checkServer(server, deepProbe: needsDeepProbe)
                    }
                }
            }
            isRefreshingAll = false
        }
    }

    func checkServer(_ profile: ServerProfile, deepProbe: Bool = false) async {
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

        let shouldProbeCapabilities = deepProbe || profile.detectedCapabilities == nil

        if profile.redfishEnabled, !profile.username.isEmpty {
            let pass = password(for: profile)
            if !pass.isEmpty {
                let probed = await fetchRedfishFullState(
                    profile: profile,
                    baseURL: url,
                    password: pass,
                    existingCapabilities: shouldProbeCapabilities ? nil : (updated.capabilities ?? profile.detectedCapabilities),
                    includeDetailedSensors: deepProbe
                )

                if let result = probed {
                    var merged = result
                    merged.reachability = .online(latencyMs: latencyMs)
                    merged.lastChecked = Date()
                    if !deepProbe {
                        if merged.temperatures.isEmpty { merged.temperatures = updated.temperatures }
                        if merged.fans.isEmpty { merged.fans = updated.fans }
                        if merged.voltages.isEmpty { merged.voltages = updated.voltages }
                        if merged.powerSupplies.isEmpty { merged.powerSupplies = updated.powerSupplies }
                        if merged.drives.isEmpty { merged.drives = updated.drives }
                    }
                    telemetry[profile.id] = merged
                    if let caps = merged.capabilities {
                        persistDetectedCapabilities(caps, for: profile.id, autoUpdateVendor: shouldProbeCapabilities)
                    }
                    return
                }
            }
        }

        // Если Redfish недоступен — пробуем пассивный фингерпринт веб-панели (например, старый iDRAC 6/7 или старый iRU BMC)
        if shouldProbeCapabilities {
            if let fp = await ServerDiscoveryHelper.fingerprintHost(
                ip: host,
                port: profile.effectivePort,
                scheme: url.scheme ?? "https",
                latencyMs: latencyMs
            ) {
                var webCaps = ServerCapabilities()
                webCaps.bmcFamily = fp.bmcFamily == .unknown ? .webOnly : fp.bmcFamily
                webCaps.bmcName = fp.detectedTitle ?? fp.bmcFamily.displayName
                webCaps.redfishVersion = fp.redfishVersion
                webCaps.redfishSupported = false
                webCaps.detectedAt = Date()

                var state = telemetry[profile.id] ?? updated
                state.capabilities = webCaps
                state.redfishAvailable = false
                telemetry[profile.id] = state
                persistDetectedCapabilities(webCaps, for: profile.id, autoUpdateVendor: true)
            }
        }
    }

    func loadDetailedSensors(for profile: ServerProfile) async {
        guard let url = profile.normalizedURL else { return }
        let pass = password(for: profile)
        guard profile.redfishEnabled, !profile.username.isEmpty, !pass.isEmpty else { return }

        loadingSensorsFor.insert(profile.id)
        defer { loadingSensorsFor.remove(profile.id) }

        let existingCaps = capabilities(for: profile)
        if let result = await fetchRedfishFullState(
            profile: profile,
            baseURL: url,
            password: pass,
            existingCapabilities: existingCaps,
            includeDetailedSensors: true
        ) {
            var merged = result
            merged.reachability = telemetry[profile.id]?.reachability ?? .online(latencyMs: 1)
            merged.lastChecked = Date()
            telemetry[profile.id] = merged
            if let caps = merged.capabilities {
                persistDetectedCapabilities(caps, for: profile.id)
            }
        }
    }

    // MARK: - Загрузка и очистка журналов (SEL / Lifecycle Log / FaultList / EventLog)

    func loadLogs(for profile: ServerProfile, service: ServerLogServiceInfo) async {
        guard let baseURL = profile.normalizedURL, let host = profile.host else { return }
        let pass = password(for: profile)
        guard !profile.username.isEmpty, !pass.isEmpty else { return }

        let key = "\(profile.id.uuidString)::\(service.id)"
        loadingLogsFor.insert(key)
        defer { loadingLogsFor.remove(key) }

        let session = makeSession(host: host, allowUntrustedSSL: profile.allowUntrustedSSL, timeout: 10)
        defer { session.invalidateAndCancel() }

        // Сначала пробуем ограничить выборку свежими записями через OData $top, затем fallback на базовый путь
        var dict = await fetchRedfishJSON(
            session: session,
            baseURL: baseURL,
            pathWithQuery: "\(service.entriesPath)?$top=50",
            username: profile.username,
            password: pass
        )
        if dict == nil {
            dict = await fetchRedfishJSON(
                session: session,
                baseURL: baseURL,
                path: service.entriesPath,
                username: profile.username,
                password: pass
            )
        }

        guard let payload = dict else {
            showNotice("Не удалось загрузить журнал «\(service.name)»")
            return
        }

        let rawMembers = (payload["Members"] as? [[String: Any]]) ?? []
        var entries: [ServerLogEntry] = []
        entries.reserveCapacity(min(rawMembers.count, 80))

        for (index, item) in rawMembers.prefix(80).enumerated() {
            let entryId = (item["Id"] as? String) ?? "\(index)"
            let message = (item["Message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (item["Name"] as? String)
                ?? "Событие #\(entryId)"
            let created = item["Created"] as? String
            let severity = item["Severity"] as? String
            let sensorType = item["SensorType"] as? String
            let entryCode = item["EntryCode"] as? String

            entries.append(
                ServerLogEntry(
                    id: "\(service.id)-\(entryId)-\(index)",
                    created: created,
                    severity: severity,
                    message: message,
                    sensorType: sensorType,
                    entryCode: entryCode
                )
            )
        }

        entries.sort { lhs, rhs in
            let l = lhs.created ?? ""
            let r = rhs.created ?? ""
            if l != r { return l > r }
            return lhs.id > rhs.id
        }

        var serverLogs = logsByServer[profile.id] ?? [:]
        serverLogs[service.id] = entries
        logsByServer[profile.id] = serverLogs
    }

    func clearLog(for profile: ServerProfile, service: ServerLogServiceInfo) async {
        guard let baseURL = profile.normalizedURL,
              let host = profile.host,
              let clearPath = service.clearActionPath else {
            showNotice("Очистка журнала не поддерживается этим BMC")
            return
        }
        let pass = password(for: profile)
        guard !profile.username.isEmpty, !pass.isEmpty else { return }

        let session = makeSession(host: host, allowUntrustedSSL: profile.allowUntrustedSSL, timeout: 8)
        defer { session.invalidateAndCancel() }

        guard let url = resolveRedfishURL(baseURL: baseURL, path: clearPath) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(basicAuthHeader(username: profile.username, password: pass), forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                showNotice("Журнал «\(service.name)» очищен")
                await loadLogs(for: profile, service: service)
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                showNotice("BMC отклонил очистку журнала (HTTP \(code))")
            }
        } catch {
            showNotice("Не удалось очистить журнал")
        }
    }

    // MARK: - Управление питанием, разовой загрузкой, перезапуском iDRAC/BMC и индикатором LED

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

        let resetPath: String
        if let cachedAction = capabilities(for: profile)?.resetActionPath {
            resetPath = cachedAction
        } else if let sys = telemetry[profile.id]?.systemPath ?? capabilities(for: profile)?.systemPath {
            resetPath = "\(sys)/Actions/ComputerSystem.Reset"
        } else if let discovered = await discoverFirstMemberPath(
            session: session,
            baseURL: baseURL,
            collectionPath: "/redfish/v1/Systems",
            username: profile.username,
            password: pass
        ) {
            resetPath = "\(discovered)/Actions/ComputerSystem.Reset"
        } else {
            showNotice("Redfish API недоступен — выполните действие через веб-панель")
            return
        }

        guard let resetURL = resolveRedfishURL(baseURL: baseURL, path: resetPath) else {
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
                showNotice("\(profile.name): отправлено «\(action.shortTitle)»")
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

    func setOneTimeBoot(_ target: ServerBootTarget, for profile: ServerProfile, rebootNow: Bool) async {
        guard let baseURL = profile.normalizedURL, let host = profile.host else { return }
        let pass = password(for: profile)
        guard !profile.username.isEmpty, !pass.isEmpty else {
            showNotice("Укажите логин и пароль сервера")
            return
        }
        guard let systemPath = telemetry[profile.id]?.systemPath ?? capabilities(for: profile)?.systemPath,
              let url = resolveRedfishURL(baseURL: baseURL, path: systemPath) else {
            showNotice("Однократная загрузка недоступна для этого BMC")
            return
        }

        let session = makeSession(host: host, allowUntrustedSSL: profile.allowUntrustedSSL, timeout: 8)
        defer { session.invalidateAndCancel() }

        let bootPayload: [String: Any] = [
            "Boot": [
                "BootSourceOverrideTarget": target.rawValue,
                "BootSourceOverrideEnabled": target == .none ? "Disabled" : "Once"
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(basicAuthHeader(username: profile.username, password: pass), forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: bootPayload)

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                var state = telemetry[profile.id] ?? ServerTelemetry()
                state.bootOverrideTarget = target.rawValue
                state.bootOverrideEnabled = target == .none ? "Disabled" : "Once"
                telemetry[profile.id] = state

                if rebootNow && target != .none {
                    showNotice("Назначено «\(target.title)», перезагружаем…")
                    let caps = capabilities(for: profile)
                    let restartAction: ServerPowerAction
                    if let allowed = caps?.allowedResetTypes {
                        if allowed.contains(.gracefulRestart) {
                            restartAction = .gracefulRestart
                        } else if allowed.contains(.forceRestart) {
                            restartAction = .forceRestart
                        } else {
                            restartAction = .powerCycle
                        }
                    } else {
                        restartAction = .gracefulRestart
                    }
                    await sendPowerAction(restartAction, to: profile)
                } else {
                    showNotice("Разовая загрузка: \(target.title)")
                }
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                showNotice("BMC отклонил смену загрузки (HTTP \(code))")
            }
        } catch {
            showNotice("Ошибка настройки разовой загрузки")
        }
    }

    func resetBMCManager(for profile: ServerProfile) async {
        guard let baseURL = profile.normalizedURL, let host = profile.host else { return }
        let pass = password(for: profile)
        guard !profile.username.isEmpty, !pass.isEmpty else { return }
        guard let caps = capabilities(for: profile),
              let actionPath = caps.managerResetActionPath,
              let url = resolveRedfishURL(baseURL: baseURL, path: actionPath) else {
            showNotice("Перезапуск контроллера BMC недоступен")
            return
        }

        let resetType = caps.allowedManagerResetTypes.contains("GracefulRestart")
            ? "GracefulRestart"
            : (caps.allowedManagerResetTypes.first ?? "GracefulRestart")

        let session = makeSession(host: host, allowUntrustedSSL: profile.allowUntrustedSSL, timeout: 8)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(basicAuthHeader(username: profile.username, password: pass), forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["ResetType": resetType])

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                showNotice("Контроллер \(caps.bmcFamily.shortBadge) перезагружается (сервер продолжит работу)")
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                showNotice("Отклонён перезапуск BMC (HTTP \(code))")
            }
        } catch {
            showNotice("Не удалось перезапустить контроллер BMC")
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

        let caps = capabilities(for: profile)
        let targetPath: String?
        if let chassis = telemetry[profile.id]?.chassisPath ?? caps?.chassisPath {
            targetPath = chassis
        } else if let system = telemetry[profile.id]?.systemPath ?? caps?.systemPath {
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

        let currentlyLit = telemetry[profile.id]?.isLocatorLit == true
        let nextLit = !currentlyLit
        let nextStringState = nextLit ? "Lit" : "Off"

        let useModernField = caps?.usesLocationIndicatorActive == true
        let payload: [String: Any] = useModernField
            ? ["LocationIndicatorActive": nextLit]
            : ["IndicatorLED": nextStringState]

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(username: profile.username, password: pass), forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                var state = telemetry[profile.id] ?? ServerTelemetry()
                state.indicatorLED = nextStringState
                telemetry[profile.id] = state
                showNotice(nextLit ? "Индикатор локатора включён" : "Индикатор локатора выключен")
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

    // MARK: - Автопоиск iDRAC / BMC в локальной сети и через Kerio VPN

    func startNetworkScan(subnetInput: String, includeHTTP: Bool) {
        stopNetworkScan()
        refreshNetworkRoute()

        let targets = ServerDiscoveryHelper.parseTargets(from: subnetInput)
        guard !targets.isEmpty else {
            scanStatusText = "Неверный формат подсети (например: 192.168.1.0/24)"
            return
        }

        isScanningNetwork = true
        scanProgress = 0
        discoveredBMCs = []
        scanStatusText = "Сканирование \(targets.count) адресов…"

        startPassiveBonjourDiscovery()

        scanTask = Task { [weak self] in
            guard let self = self else { return }
            let total = targets.count
            var completed = 0
            let maxConcurrency = 24

            await withTaskGroup(of: DiscoveredBMC?.self) { group in
                var nextIndex = 0
                let initialCount = min(maxConcurrency, total)

                while nextIndex < initialCount && !Task.isCancelled {
                    let ip = targets[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await ServerDiscoveryHelper.probeAndFingerprint(ip: ip, includeHTTP: includeHTTP)
                    }
                }

                for await found in group {
                    if Task.isCancelled { break }
                    completed += 1
                    self.scanProgress = Double(completed) / Double(total)
                    self.scanStatusText = "Проверено \(completed) из \(total) · найдено \(self.discoveredBMCs.count)"

                    if let item = found {
                        self.mergeDiscoveredBMC(item)
                    }

                    if nextIndex < total && !Task.isCancelled {
                        let ip = targets[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            await ServerDiscoveryHelper.probeAndFingerprint(ip: ip, includeHTTP: includeHTTP)
                        }
                    }
                }
            }

            if !Task.isCancelled {
                self.stopBonjourBrowser()
                self.isScanningNetwork = false
                self.scanProgress = 1.0
                let confirmed = self.discoveredBMCs.filter { $0.isConfirmedBMC }.count
                if self.discoveredBMCs.isEmpty {
                    self.scanStatusText = "Устройства не найдены. Проверьте подсеть или Kerio VPN."
                } else if confirmed > 0 {
                    self.scanStatusText = "Найдено BMC/iDRAC: \(confirmed) (всего веб-хостов: \(self.discoveredBMCs.count))"
                } else {
                    self.scanStatusText = "Найдено HTTPS/HTTP хостов: \(self.discoveredBMCs.count)"
                }
            }
        }
    }

    func stopNetworkScan() {
        scanTask?.cancel()
        scanTask = nil
        stopBonjourBrowser()
        if isScanningNetwork {
            isScanningNetwork = false
            scanStatusText = "Поиск остановлен · найдено \(discoveredBMCs.count)"
        }
    }

    private func mergeDiscoveredBMC(_ item: DiscoveredBMC) {
        if let idx = discoveredBMCs.firstIndex(where: { $0.ip == item.ip }) {
            if item.isConfirmedBMC && !discoveredBMCs[idx].isConfirmedBMC {
                discoveredBMCs[idx] = item
            }
        } else {
            discoveredBMCs.append(item)
        }
        discoveredBMCs.sort { lhs, rhs in
            if lhs.isConfirmedBMC != rhs.isConfirmedBMC {
                return lhs.isConfirmedBMC && !rhs.isConfirmedBMC
            }
            if lhs.redfishSupported != rhs.redfishSupported {
                return lhs.redfishSupported && !rhs.redfishSupported
            }
            return ServerDiscoveryHelper.ipSortKey(lhs.ip) < ServerDiscoveryHelper.ipSortKey(rhs.ip)
        }
    }

    private func startPassiveBonjourDiscovery() {
        stopBonjourBrowser()
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_https._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                guard case .service(let name, _, _, _) = result.endpoint else { continue }
                let lower = name.lowercased()
                let looksLikeBMC = lower.contains("idrac")
                    || lower.contains("bmc")
                    || lower.contains("megarac")
                    || lower.contains("iru")
                    || lower.contains("openbmc")
                    || lower.contains("ipmi")
                    || lower.contains("dell")
                guard looksLikeBMC else { continue }
                Task.detached {
                    if let resolvedIP = await ServerNetworkHelper.resolveBonjourIPv4(endpoint: result.endpoint),
                       let found = await ServerDiscoveryHelper.probeAndFingerprint(ip: resolvedIP, includeHTTP: false) {
                        await MainActor.run {
                            self?.mergeDiscoveredBMC(found)
                        }
                    }
                }
            }
        }
        browser.start(queue: monitorQueue)
        bonjourBrowser = browser
    }

    private func stopBonjourBrowser() {
        bonjourBrowser?.cancel()
        bonjourBrowser = nil
    }

    // MARK: - Глубокий опрос Redfish и автоопределение версии/возможностей iDRAC и iRU BMC

    private func fetchRedfishFullState(
        profile: ServerProfile,
        baseURL: URL,
        password: String,
        existingCapabilities: ServerCapabilities?,
        includeDetailedSensors: Bool
    ) async -> ServerTelemetry? {
        guard let host = profile.host else { return nil }
        let session = makeSession(host: host, allowUntrustedSSL: profile.allowUntrustedSSL, timeout: 7)
        defer { session.invalidateAndCancel() }

        let serviceRoot = await fetchRedfishJSON(
            session: session,
            baseURL: baseURL,
            path: "/redfish/v1",
            username: profile.username,
            password: password
        )

        let systemPath: String
        if let existingSys = existingCapabilities?.systemPath {
            systemPath = existingSys
        } else if let discovered = await discoverFirstMemberPath(
            session: session,
            baseURL: baseURL,
            collectionPath: "/redfish/v1/Systems",
            username: profile.username,
            password: password
        ) {
            systemPath = discovered
        } else {
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

        var caps = existingCapabilities ?? ServerCapabilities()
        caps.redfishSupported = true
        caps.systemPath = systemPath
        if let rfVer = serviceRoot?["RedfishVersion"] as? String, !rfVer.isEmpty {
            caps.redfishVersion = rfVer
        }

        var result = ServerTelemetry()
        result.redfishAvailable = true
        result.systemPath = systemPath
        result.powerState = sysDict["PowerState"] as? String
        result.model = (sysDict["Model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.manufacturer = (sysDict["Manufacturer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.serialNumber = (sysDict["SerialNumber"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.sku = (sysDict["SKU"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.hostname = (sysDict["HostName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.biosVersion = sysDict["BiosVersion"] as? String

        if let led = sysDict["IndicatorLED"] as? String {
            result.indicatorLED = led
            caps.supportsIndicatorLED = true
        } else if let locActive = sysDict["LocationIndicatorActive"] as? Bool {
            result.indicatorLED = locActive ? "Lit" : "Off"
            caps.supportsIndicatorLED = true
            caps.usesLocationIndicatorActive = true
        }

        if let statusDict = sysDict["Status"] as? [String: Any] {
            result.health = (statusDict["HealthRollup"] as? String) ?? (statusDict["Health"] as? String)
            result.systemState = statusDict["State"] as? String
        }
        if let proc = sysDict["ProcessorSummary"] as? [String: Any],
           let count = proc["Count"] as? Int {
            result.cpuCount = count
        }
        if let mem = sysDict["MemorySummary"] as? [String: Any] {
            if let gib = mem["TotalSystemMemoryGiB"] as? Int {
                result.memoryGiB = gib
            } else if let gibDouble = mem["TotalSystemMemoryGiB"] as? Double {
                result.memoryGiB = Int(gibDouble.rounded())
            }
        }

        // Парсим доступные действия питания прямо из Redfish Actions
        if let actions = sysDict["Actions"] as? [String: Any],
           let resetAction = actions["#ComputerSystem.Reset"] as? [String: Any] {
            if let target = resetAction["target"] as? String, !target.isEmpty {
                caps.resetActionPath = target
            } else {
                caps.resetActionPath = "\(systemPath)/Actions/ComputerSystem.Reset"
            }

            if let allowedStrings = resetAction["ResetType@Redfish.AllowableValues"] as? [String] {
                let parsed = allowedStrings.compactMap { ServerPowerAction(rawValue: $0) }
                if !parsed.isEmpty {
                    caps.allowedResetTypes = parsed
                }
            } else if let actionInfoPath = resetAction["@Redfish.ActionInfo"] as? String,
                      caps.allowedResetTypes.isEmpty,
                      let actionInfo = await fetchRedfishJSON(
                        session: session,
                        baseURL: baseURL,
                        path: actionInfoPath,
                        username: profile.username,
                        password: password
                      ),
                      let params = actionInfo["Parameters"] as? [[String: Any]] {
                for param in params where (param["Name"] as? String) == "ResetType" {
                    if let vals = param["AllowableValues"] as? [String] {
                        let parsed = vals.compactMap { ServerPowerAction(rawValue: $0) }
                        if !parsed.isEmpty {
                            caps.allowedResetTypes = parsed
                        }
                    }
                }
            }
        }
        if caps.resetActionPath == nil {
            caps.resetActionPath = "\(systemPath)/Actions/ComputerSystem.Reset"
        }
        if caps.allowedResetTypes.isEmpty {
            caps.allowedResetTypes = [.on, .gracefulShutdown, .gracefulRestart, .forceRestart, .forceOff]
        }

        // Парсим однократную загрузку (One-Time Boot)
        if let bootDict = sysDict["Boot"] as? [String: Any] {
            result.bootOverrideTarget = bootDict["BootSourceOverrideTarget"] as? String
            result.bootOverrideEnabled = bootDict["BootSourceOverrideEnabled"] as? String
            if let allowableTargets = bootDict["BootSourceOverrideTarget@Redfish.AllowableValues"] as? [String] {
                let mapped = allowableTargets.compactMap { ServerBootTarget(rawValue: $0) }
                if !mapped.isEmpty {
                    caps.allowedBootTargets = mapped
                    caps.supportsBootOverride = true
                }
            } else if result.bootOverrideTarget != nil {
                caps.supportsBootOverride = true
                if caps.allowedBootTargets.isEmpty {
                    caps.allowedBootTargets = [.none, .biosSetup, .pxe, .usb, .hdd, .cd]
                }
            }
        }

        // Определяем контроллер Manager (iDRAC 7/8/9, iRU MegaRAC, OpenBMC, версия прошивки)
        let managerPath: String?
        if let existingMgr = existingCapabilities?.managerPath {
            managerPath = existingMgr
        } else {
            managerPath = await discoverFirstMemberPath(
                session: session,
                baseURL: baseURL,
                collectionPath: "/redfish/v1/Managers",
                username: profile.username,
                password: password
            )
        }
        caps.managerPath = managerPath

        var mgrDict: [String: Any]?
        if let mPath = managerPath {
            mgrDict = await fetchRedfishJSON(
                session: session,
                baseURL: baseURL,
                path: mPath,
                username: profile.username,
                password: password
            )
            if let mgr = mgrDict {
                caps.bmcModel = (mgr["Model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                caps.bmcFirmwareVersion = (mgr["FirmwareVersion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                caps.bmcName = (mgr["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

                if let mgrActions = mgr["Actions"] as? [String: Any],
                   let mgrReset = mgrActions["#Manager.Reset"] as? [String: Any] {
                    caps.managerResetActionPath = (mgrReset["target"] as? String) ?? "\(mPath)/Actions/Manager.Reset"
                    if let allowed = mgrReset["ResetType@Redfish.AllowableValues"] as? [String], !allowed.isEmpty {
                        caps.allowedManagerResetTypes = allowed
                    } else {
                        caps.allowedManagerResetTypes = ["GracefulRestart"]
                    }
                }
            }
        }

        caps.bmcFamily = classifyBMCFamily(
            serviceRoot: serviceRoot,
            managerDict: mgrDict,
            systemDict: sysDict,
            fallbackVendor: profile.vendor
        )

        // Chassis: LED, Thermal (температуры + вентиляторы), Power (ватты + БП + напряжения)
        let chassisPath: String?
        if let existingCh = existingCapabilities?.chassisPath {
            chassisPath = existingCh
        } else {
            chassisPath = await discoverFirstMemberPath(
                session: session,
                baseURL: baseURL,
                collectionPath: "/redfish/v1/Chassis",
                username: profile.username,
                password: password
            )
        }

        var chassisDict: [String: Any]?
        if let chPath = chassisPath {
            result.chassisPath = chPath
            caps.chassisPath = chPath

            chassisDict = await fetchRedfishJSON(
                session: session,
                baseURL: baseURL,
                path: chPath,
                username: profile.username,
                password: password
            )
            if let ch = chassisDict {
                if result.indicatorLED == nil {
                    if let led = ch["IndicatorLED"] as? String {
                        result.indicatorLED = led
                        caps.supportsIndicatorLED = true
                    } else if let locActive = ch["LocationIndicatorActive"] as? Bool {
                        result.indicatorLED = locActive ? "Lit" : "Off"
                        caps.supportsIndicatorLED = true
                        caps.usesLocationIndicatorActive = true
                    }
                }
                if result.health == nil, let st = chassisDict?["Status"] as? [String: Any] {
                    result.health = (st["HealthRollup"] as? String) ?? (st["Health"] as? String)
                }
                if result.systemState == nil, let st = chassisDict?["Status"] as? [String: Any] {
                    result.systemState = st["State"] as? String
                }
            }

            // Thermal
            let thermalPath = ((chassisDict?["Thermal"] as? [String: Any])?["@odata.id"] as? String) ?? "\(chPath)/Thermal"
            if let thermalDict = await fetchRedfishJSON(
                session: session,
                baseURL: baseURL,
                path: thermalPath,
                username: profile.username,
                password: password
            ) {
                let parsedThermal = parseThermal(thermalDict)
                result.temperatures = parsedThermal.temperatures
                result.fans = parsedThermal.fans
                result.maxTempC = parsedThermal.temperatures.map { Int($0.readingC.rounded()) }.max()
                let rpmFans = parsedThermal.fans.filter { $0.units.uppercased() == "RPM" && $0.reading > 0 }
                if !rpmFans.isEmpty {
                    result.fanRPM = rpmFans.map(\.reading).reduce(0, +) / rpmFans.count
                }
                if !parsedThermal.temperatures.isEmpty || !parsedThermal.fans.isEmpty {
                    caps.supportsThermal = true
                }
            }

            // Power (Ватты, PSU, Напряжения)
            let powerPath = ((chassisDict?["Power"] as? [String: Any])?["@odata.id"] as? String) ?? "\(chPath)/Power"
            if includeDetailedSensors || existingCapabilities == nil || caps.supportsPowerMetrics {
                if let powerDict = await fetchRedfishJSON(
                    session: session,
                    baseURL: baseURL,
                    path: powerPath,
                    username: profile.username,
                    password: password
                ) {
                    let parsedPower = parsePower(powerDict)
                    result.powerConsumedWatts = parsedPower.consumedWatts
                    result.powerCapacityWatts = parsedPower.capacityWatts
                    result.powerSupplies = parsedPower.psus
                    result.voltages = parsedPower.voltages
                    if parsedPower.consumedWatts != nil || !parsedPower.psus.isEmpty || !parsedPower.voltages.isEmpty {
                        caps.supportsPowerMetrics = true
                    }
                }
            }
        }

        // Storage / Drives (при первом глубоком опросе или открытии датчиков)
        let storageCollectionPath = ((sysDict["Storage"] as? [String: Any])?["@odata.id"] as? String)
        let simpleStoragePath = ((sysDict["SimpleStorage"] as? [String: Any])?["@odata.id"] as? String)
        if storageCollectionPath != nil || simpleStoragePath != nil {
            if includeDetailedSensors {
                let drives = await fetchStorageDrives(
                    session: session,
                    baseURL: baseURL,
                    storagePath: storageCollectionPath,
                    simpleStoragePath: simpleStoragePath,
                    username: profile.username,
                    password: password
                )
                result.drives = drives
                if !drives.isEmpty {
                    caps.supportsStorage = true
                }
            } else if existingCapabilities == nil {
                caps.supportsStorage = true
            }
        }

        // Обнаружение доступных журналов (SEL, Lifecycle Log, FaultList, EventLog)
        if existingCapabilities == nil || caps.logServices.isEmpty {
            var logCollectionPaths: [String] = []
            if let mgrLogs = (mgrDict?["LogServices"] as? [String: Any])?["@odata.id"] as? String {
                logCollectionPaths.append(mgrLogs)
            }
            if let sysLogs = (sysDict["LogServices"] as? [String: Any])?["@odata.id"] as? String {
                logCollectionPaths.append(sysLogs)
            }
            if let chLogs = (chassisDict?["LogServices"] as? [String: Any])?["@odata.id"] as? String {
                logCollectionPaths.append(chLogs)
            }
            if !logCollectionPaths.isEmpty {
                caps.logServices = await discoverLogServices(
                    session: session,
                    baseURL: baseURL,
                    collectionPaths: logCollectionPaths,
                    username: profile.username,
                    password: password
                )
            }
        }

        caps.detectedAt = Date()
        result.capabilities = caps
        return result
    }

    private func classifyBMCFamily(
        serviceRoot: [String: Any]?,
        managerDict: [String: Any]?,
        systemDict: [String: Any],
        fallbackVendor: ServerVendor
    ) -> ServerBMCFamily {
        let rootProduct = (serviceRoot?["Product"] as? String) ?? ""
        let rootVendor = (serviceRoot?["Vendor"] as? String) ?? ""
        let rootOemKeys = (serviceRoot?["Oem"] as? [String: Any])?.keys.joined(separator: " ") ?? ""
        let mgrName = (managerDict?["Name"] as? String) ?? ""
        let mgrModel = (managerDict?["Model"] as? String) ?? ""
        let mgrDesc = (managerDict?["Description"] as? String) ?? ""
        let mgrFW = (managerDict?["FirmwareVersion"] as? String) ?? ""
        let sysMfr = (systemDict["Manufacturer"] as? String) ?? ""
        let sysModel = (systemDict["Model"] as? String) ?? ""

        let combined = [rootProduct, rootVendor, rootOemKeys, mgrName, mgrModel, mgrDesc, sysMfr, sysModel]
            .joined(separator: " ")
            .lowercased()

        if combined.contains("dell") || combined.contains("idrac") || combined.contains("poweredge") {
            if combined.contains("idrac9") || combined.contains("14g") || combined.contains("15g") || combined.contains("16g") || combined.contains("17g") {
                return .dellIDRAC9
            }
            if combined.contains("idrac8") || combined.contains("13g") {
                return .dellIDRAC8
            }
            if combined.contains("idrac7") || combined.contains("12g") {
                return .dellIDRAC7
            }
            if let majorStr = mgrFW.split(separator: ".").first, let major = Int(majorStr) {
                if major >= 3 { return .dellIDRAC9 }
                if major == 2 { return .dellIDRAC8 }
                if major == 1 { return .dellIDRAC7 }
            }
            return .dellIDRAC8
        }

        if combined.contains("openbmc") || combined.contains("phosphor") {
            return .iruOpenBMC
        }

        if combined.contains("iru")
            || combined.contains("megarac")
            || combined.contains("american megatrends")
            || combined.contains("ami")
            || combined.contains("aspeed")
            || combined.contains("ast2500")
            || combined.contains("ast2600") {
            return .iruMegaRAC
        }

        switch fallbackVendor {
        case .dellIDRAC: return .dellIDRAC8
        case .iruBMC: return .iruMegaRAC
        case .genericWeb: return .genericRedfish
        }
    }

    private func parseThermal(_ dict: [String: Any]) -> (temperatures: [ServerTempSensor], fans: [ServerFanSensor]) {
        var temps: [ServerTempSensor] = []
        if let rawTemps = dict["Temperatures"] as? [[String: Any]] {
            for (idx, item) in rawTemps.enumerated() {
                let value: Double?
                if let d = item["ReadingCelsius"] as? Double {
                    value = d
                } else if let i = item["ReadingCelsius"] as? Int {
                    value = Double(i)
                } else {
                    value = nil
                }
                guard let reading = value, reading > 0, reading < 140 else { continue }
                let name = (item["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Датчик \(idx + 1)"
                let warn = (item["UpperThresholdNonCritical"] as? Double)
                    ?? (item["UpperThresholdNonCritical"] as? Int).map(Double.init)
                let crit = (item["UpperThresholdCritical"] as? Double)
                    ?? (item["UpperThresholdCritical"] as? Int).map(Double.init)
                let health = (item["Status"] as? [String: Any])?["Health"] as? String
                let id = (item["MemberId"] as? String) ?? "temp-\(idx)-\(name)"
                temps.append(
                    ServerTempSensor(
                        id: id,
                        name: name,
                        readingC: reading,
                        upperWarningC: warn,
                        upperCriticalC: crit,
                        health: health
                    )
                )
            }
        }

        var fans: [ServerFanSensor] = []
        if let rawFans = dict["Fans"] as? [[String: Any]] {
            for (idx, item) in rawFans.enumerated() {
                let value: Int?
                if let i = item["Reading"] as? Int {
                    value = i
                } else if let d = item["Reading"] as? Double {
                    value = Int(d.rounded())
                } else {
                    value = nil
                }
                guard let reading = value, reading >= 0 else { continue }
                let status = item["Status"] as? [String: Any]
                if (status?["State"] as? String)?.lowercased() == "absent" { continue }
                let name = (item["FanName"] as? String)
                    ?? (item["Name"] as? String)
                    ?? "Вентилятор \(idx + 1)"
                let units = (item["ReadingUnits"] as? String) ?? "RPM"
                let health = status?["Health"] as? String
                let id = (item["MemberId"] as? String) ?? "fan-\(idx)-\(name)"
                fans.append(
                    ServerFanSensor(
                        id: id,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        reading: reading,
                        units: units,
                        health: health
                    )
                )
            }
        }
        return (temps, fans)
    }

    private func parsePower(_ dict: [String: Any]) -> (
        consumedWatts: Int?,
        capacityWatts: Int?,
        psus: [ServerPSUSensor],
        voltages: [ServerVoltageSensor]
    ) {
        var consumed: Int?
        var capacity: Int?
        if let controls = dict["PowerControl"] as? [[String: Any]], let first = controls.first {
            if let w = first["PowerConsumedWatts"] as? Int {
                consumed = w
            } else if let d = first["PowerConsumedWatts"] as? Double {
                consumed = Int(d.rounded())
            }
            if let cap = first["PowerCapacityWatts"] as? Int {
                capacity = cap
            } else if let d = first["PowerCapacityWatts"] as? Double {
                capacity = Int(d.rounded())
            }
        }

        var psus: [ServerPSUSensor] = []
        if let rawPSUs = dict["PowerSupplies"] as? [[String: Any]] {
            for (idx, item) in rawPSUs.enumerated() {
                let status = item["Status"] as? [String: Any]
                let state = status?["State"] as? String
                if state?.lowercased() == "absent" { continue }
                let name = (item["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "БП \(idx + 1)"
                let model = (item["Model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let output: Int? = (item["PowerOutputWatts"] as? Int)
                    ?? (item["PowerOutputWatts"] as? Double).map { Int($0.rounded()) }
                    ?? (item["LastPowerOutputWatts"] as? Int)
                    ?? (item["LastPowerOutputWatts"] as? Double).map { Int($0.rounded()) }
                let cap: Int? = (item["PowerCapacityWatts"] as? Int)
                    ?? (item["PowerCapacityWatts"] as? Double).map { Int($0.rounded()) }
                let health = status?["Health"] as? String
                let id = (item["MemberId"] as? String) ?? "psu-\(idx)"
                psus.append(
                    ServerPSUSensor(
                        id: id,
                        name: name,
                        model: model,
                        powerOutputWatts: output,
                        capacityWatts: cap,
                        health: health,
                        state: state
                    )
                )
            }
        }

        var voltages: [ServerVoltageSensor] = []
        if let rawVolts = dict["Voltages"] as? [[String: Any]] {
            for (idx, item) in rawVolts.enumerated() {
                let reading: Double? = (item["ReadingVolts"] as? Double)
                    ?? (item["ReadingVolts"] as? Int).map(Double.init)
                guard let v = reading, v > 0 else { continue }
                let name = (item["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Линия \(idx + 1)"
                let health = (item["Status"] as? [String: Any])?["Health"] as? String
                let id = (item["MemberId"] as? String) ?? "volt-\(idx)-\(name)"
                voltages.append(ServerVoltageSensor(id: id, name: name, readingVolts: v, health: health))
            }
        }

        return (consumed, capacity, psus, voltages)
    }

    private func fetchStorageDrives(
        session: URLSession,
        baseURL: URL,
        storagePath: String?,
        simpleStoragePath: String?,
        username: String,
        password: String
    ) async -> [ServerDriveInfo] {
        var drives: [ServerDriveInfo] = []

        if let sPath = storagePath,
           let coll = await fetchRedfishJSON(session: session, baseURL: baseURL, path: sPath, username: username, password: password),
           let members = coll["Members"] as? [[String: Any]] {
            let controllerPaths = members.compactMap { $0["@odata.id"] as? String }.prefix(3)
            var drivePaths: [String] = []
            for ctrlPath in controllerPaths {
                if let ctrl = await fetchRedfishJSON(session: session, baseURL: baseURL, path: ctrlPath, username: username, password: password),
                   let ctrlDrives = ctrl["Drives"] as? [[String: Any]] {
                    for d in ctrlDrives {
                        if let p = d["@odata.id"] as? String {
                            drivePaths.append(p)
                        }
                    }
                }
            }

            for (idx, dPath) in drivePaths.prefix(12).enumerated() {
                if let dDict = await fetchRedfishJSON(session: session, baseURL: baseURL, path: dPath, username: username, password: password) {
                    let name = (dDict["Name"] as? String) ?? "Диск \(idx + 1)"
                    let model = (dDict["Model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let media = dDict["MediaType"] as? String
                    let bytes = (dDict["CapacityBytes"] as? Int64)
                        ?? (dDict["CapacityBytes"] as? Int).map(Int64.init)
                        ?? (dDict["CapacityBytes"] as? Double).map { Int64($0) }
                    let gib = bytes.map { Int($0 / (1024 * 1024 * 1024)) }
                    let status = dDict["Status"] as? [String: Any]
                    drives.append(
                        ServerDriveInfo(
                            id: (dDict["Id"] as? String) ?? "drv-\(idx)",
                            name: name,
                            model: model,
                            mediaType: media,
                            capacityGiB: gib,
                            health: status?["Health"] as? String,
                            state: status?["State"] as? String
                        )
                    )
                }
            }
        }

        if drives.isEmpty,
           let ssPath = simpleStoragePath,
           let coll = await fetchRedfishJSON(session: session, baseURL: baseURL, path: ssPath, username: username, password: password),
           let members = coll["Members"] as? [[String: Any]] {
            for ctrlMember in members.prefix(2) {
                guard let ctrlPath = ctrlMember["@odata.id"] as? String,
                      let ctrlDict = await fetchRedfishJSON(session: session, baseURL: baseURL, path: ctrlPath, username: username, password: password),
                      let devices = ctrlDict["Devices"] as? [[String: Any]] else { continue }
                for (idx, dev) in devices.prefix(12).enumerated() {
                    let name = (dev["Name"] as? String) ?? "Устройство \(idx + 1)"
                    let model = (dev["Model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let bytes = (dev["CapacityBytes"] as? Int64)
                        ?? (dev["CapacityBytes"] as? Int).map(Int64.init)
                        ?? (dev["CapacityBytes"] as? Double).map { Int64($0) }
                    let gib = bytes.map { Int($0 / (1024 * 1024 * 1024)) }
                    let status = dev["Status"] as? [String: Any]
                    drives.append(
                        ServerDriveInfo(
                            id: "ss-\(idx)-\(name)",
                            name: name,
                            model: model,
                            mediaType: nil,
                            capacityGiB: gib,
                            health: status?["Health"] as? String,
                            state: status?["State"] as? String
                        )
                    )
                }
            }
        }

        return drives
    }

    private func discoverLogServices(
        session: URLSession,
        baseURL: URL,
        collectionPaths: [String],
        username: String,
        password: String
    ) async -> [ServerLogServiceInfo] {
        var seenPaths = Set<String>()
        var result: [ServerLogServiceInfo] = []

        for collectionPath in collectionPaths {
            guard let coll = await fetchRedfishJSON(
                session: session,
                baseURL: baseURL,
                path: collectionPath,
                username: username,
                password: password
            ), let members = coll["Members"] as? [[String: Any]] else { continue }

            for member in members.prefix(6) {
                guard let svcPath = member["@odata.id"] as? String,
                      !svcPath.isEmpty,
                      !seenPaths.contains(svcPath) else { continue }
                seenPaths.insert(svcPath)

                guard let svcDict = await fetchRedfishJSON(
                    session: session,
                    baseURL: baseURL,
                    path: svcPath,
                    username: username,
                    password: password
                ) else { continue }

                let rawId = (svcDict["Id"] as? String) ?? svcPath.split(separator: "/").last.map(String.init) ?? "Log"
                let rawName = (svcDict["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawId
                let entriesPath = ((svcDict["Entries"] as? [String: Any])?["@odata.id"] as? String) ?? "\(svcPath)/Entries"
                let clearTarget = ((svcDict["Actions"] as? [String: Any])?["#LogService.ClearLog"] as? [String: Any])?["target"] as? String

                result.append(
                    ServerLogServiceInfo(
                        id: rawId,
                        name: localizeLogServiceName(id: rawId, rawName: rawName),
                        path: svcPath,
                        entriesPath: entriesPath,
                        canClear: clearTarget != nil,
                        clearActionPath: clearTarget
                    )
                )
            }
        }

        return result
    }

    private func localizeLogServiceName(id: String, rawName: String) -> String {
        let lower = "\(id) \(rawName)".lowercased()
        if lower.contains("lclog") || lower.contains("lifecycle") {
            return "Lifecycle Log"
        }
        if lower.contains("fault") {
            return "Активные ошибки"
        }
        if lower.contains("sel") || lower.contains("system event") {
            return "Журнал SEL"
        }
        if lower.contains("audit") {
            return "Аудит"
        }
        if lower.contains("event") {
            return "События BMC"
        }
        return rawName
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
        return await performJSONGet(session: session, url: url, username: username, password: password)
    }

    private func fetchRedfishJSON(
        session: URLSession,
        baseURL: URL,
        pathWithQuery: String,
        username: String,
        password: String
    ) async -> [String: Any]? {
        let parts = pathWithQuery.split(separator: "?", maxSplits: 1)
        let path = String(parts[0])
        let query = parts.count > 1 ? String(parts[1]) : nil
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.percentEncodedQuery = query
        components.fragment = nil
        guard let url = components.url else { return nil }
        return await performJSONGet(session: session, url: url, username: username, password: password)
    }

    private func performJSONGet(
        session: URLSession,
        url: URL,
        username: String,
        password: String
    ) async -> [String: Any]? {
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
        config.timeoutIntervalForResource = timeout + 3
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

// MARK: - Неизолированные утилиты автопоиска iDRAC / iRU BMC

private enum ServerDiscoveryHelper {
    static func parseTargets(from rawInput: String) -> [String] {
        let cleaned = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        // Диапазон вида 192.168.1.10-50 или 192.168.1.10-192.168.1.50
        if cleaned.contains("-") {
            let parts = cleaned.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                let startOctets = parts[0].split(separator: ".").compactMap { Int($0) }
                guard startOctets.count == 4, startOctets.allSatisfy({ (0...255).contains($0) }) else { return [] }
                let endLast: Int?
                if let directEnd = Int(parts[1]), (1...254).contains(directEnd) {
                    endLast = directEnd
                } else {
                    let endOctets = parts[1].split(separator: ".").compactMap { Int($0) }
                    if endOctets.count == 4, endOctets[0] == startOctets[0], endOctets[1] == startOctets[1], endOctets[2] == startOctets[2] {
                        endLast = endOctets[3]
                    } else {
                        endLast = nil
                    }
                }
                if let endVal = endLast {
                    let low = max(1, min(startOctets[3], endVal))
                    let high = min(254, max(startOctets[3], endVal))
                    return (low...high).map { "\(startOctets[0]).\(startOctets[1]).\(startOctets[2]).\($0)" }
                }
            }
            return []
        }

        // CIDR вида 192.168.1.0/24
        if cleaned.contains("/") {
            let base = cleaned.split(separator: "/").first.map(String.init) ?? ""
            let octets = base.split(separator: ".").compactMap { Int($0) }
            guard octets.count >= 3, octets.prefix(3).allSatisfy({ (0...255).contains($0) }) else { return [] }
            let prefix = "\(octets[0]).\(octets[1]).\(octets[2])"
            return (1...254).map { "\(prefix).\($0)" }
        }

        // Префикс вида 192.168.1 или 192.168.1.
        let trimmedDot = cleaned.hasSuffix(".") ? String(cleaned.dropLast()) : cleaned
        let octets = trimmedDot.split(separator: ".").compactMap { Int($0) }
        if octets.count == 3, octets.allSatisfy({ (0...255).contains($0) }) {
            let prefix = "\(octets[0]).\(octets[1]).\(octets[2])"
            return (1...254).map { "\(prefix).\($0)" }
        }
        if octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) {
            if octets[3] == 0 {
                let prefix = "\(octets[0]).\(octets[1]).\(octets[2])"
                return (1...254).map { "\(prefix).\($0)" }
            }
            return ["\(octets[0]).\(octets[1]).\(octets[2]).\(octets[3])"]
        }
        return []
    }

    static func ipSortKey(_ ip: String) -> UInt32 {
        let octets = ip.split(separator: ".").compactMap { UInt32($0) }
        guard octets.count == 4 else { return 0 }
        return (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
    }

    static func probeAndFingerprint(ip: String, includeHTTP: Bool) async -> DiscoveredBMC? {
        let start = Date()
        if await ServerNetworkHelper.probeTCP(host: ip, port: 443, timeoutSeconds: 0.75) {
            let latency = max(1, Int(Date().timeIntervalSince(start) * 1000))
            return await fingerprintHost(ip: ip, port: 443, scheme: "https", latencyMs: latency)
        }
        if includeHTTP {
            let httpStart = Date()
            if await ServerNetworkHelper.probeTCP(host: ip, port: 80, timeoutSeconds: 0.55) {
                let latency = max(1, Int(Date().timeIntervalSince(httpStart) * 1000))
                return await fingerprintHost(ip: ip, port: 80, scheme: "http", latencyMs: latency)
            }
        }
        return nil
    }

    static func fingerprintHost(ip: String, port: Int, scheme: String, latencyMs: Int) async -> DiscoveredBMC? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.2
        config.timeoutIntervalForResource = 3.0
        let delegate = ScopedServerURLDelegate(allowedHost: ip, allowUntrustedSSL: true, blockCrossHostRedirect: true)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let baseString: String
        if (scheme == "https" && port == 443) || (scheme == "http" && port == 80) {
            baseString = "\(scheme)://\(ip)"
        } else {
            baseString = "\(scheme)://\(ip):\(port)"
        }

        var redfishSupported = false
        var redfishVersion: String?
        var family: ServerBMCFamily = .unknown
        var vendor: ServerVendor = .genericWeb
        var detectedTitle: String?
        var confirmedBMC = false

        // 1. Быстрая проверка публичного корня Redfish (/redfish/v1)
        if let rfURL = URL(string: "\(baseString)/redfish/v1") {
            var rfReq = URLRequest(url: rfURL)
            rfReq.httpMethod = "GET"
            rfReq.setValue("application/json", forHTTPHeaderField: "Accept")
            if let (data, resp) = try? await session.data(for: rfReq),
               let http = resp as? HTTPURLResponse {
                if http.statusCode == 200,
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   (json["RedfishVersion"] != nil || json["@odata.type"] != nil || json["Systems"] != nil) {
                    redfishSupported = true
                    confirmedBMC = true
                    redfishVersion = json["RedfishVersion"] as? String

                    let product = (json["Product"] as? String) ?? ""
                    let rfVendor = (json["Vendor"] as? String) ?? ""
                    let oemKeys = (json["Oem"] as? [String: Any])?.keys.joined(separator: " ") ?? ""
                    let sig = "\(product) \(rfVendor) \(oemKeys)".lowercased()

                    if sig.contains("dell") || sig.contains("idrac") {
                        vendor = .dellIDRAC
                        if sig.contains("14g") || sig.contains("15g") || sig.contains("16g") || sig.contains("idrac9") {
                            family = .dellIDRAC9
                        } else if sig.contains("13g") || sig.contains("idrac8") {
                            family = .dellIDRAC8
                        } else {
                            family = .dellIDRAC9
                        }
                        detectedTitle = product.isEmpty ? family.displayName : product
                    } else if sig.contains("openbmc") {
                        vendor = .iruBMC
                        family = .iruOpenBMC
                        detectedTitle = product.isEmpty ? "OpenBMC" : product
                    } else if sig.contains("ami") || sig.contains("megarac") || sig.contains("iru") || sig.contains("aspeed") {
                        vendor = .iruBMC
                        family = .iruMegaRAC
                        detectedTitle = product.isEmpty ? "AMI MegaRAC" : product
                    } else {
                        family = .genericRedfish
                        detectedTitle = product.isEmpty ? "Redfish BMC" : product
                    }
                } else if http.statusCode == 401 {
                    let wwwAuth = (http.value(forHTTPHeaderField: "WWW-Authenticate") ?? "").lowercased()
                    if wwwAuth.contains("redfish") || wwwAuth.contains("idrac") || wwwAuth.contains("bmc") {
                        redfishSupported = true
                        confirmedBMC = true
                        family = wwwAuth.contains("idrac") ? .dellIDRAC8 : .genericRedfish
                        vendor = wwwAuth.contains("idrac") ? .dellIDRAC : .iruBMC
                    }
                }
            }
        }

        // 2. HTML / Header фингерпринт главной страницы (ловит iDRAC 6/7/8 и iRU MegaRAC даже без публичного /redfish/v1)
        if !confirmedBMC || family == .genericRedfish {
            if let rootURL = URL(string: "\(baseString)/") {
                var rootReq = URLRequest(url: rootURL)
                rootReq.httpMethod = "GET"
                if let (data, resp) = try? await session.data(for: rootReq),
                   let http = resp as? HTTPURLResponse {
                    let prefixData = data.prefix(16_384)
                    let html = String(data: prefixData, encoding: .utf8)
                        ?? String(data: prefixData, encoding: .isoLatin1)
                        ?? ""
                    let serverHeader = http.value(forHTTPHeaderField: "Server") ?? ""
                    let locationHeader = http.value(forHTTPHeaderField: "Location") ?? ""
                    let title = extractHTMLTitle(from: html)
                    let combined = "\(title ?? "") \(serverHeader) \(locationHeader) \(html)".lowercased()

                    if combined.contains("idrac") || combined.contains("integrated dell remote access") || combined.contains("/restgui/") {
                        confirmedBMC = true
                        vendor = .dellIDRAC
                        if combined.contains("idrac9") || combined.contains("idrac 9") {
                            family = .dellIDRAC9
                        } else if combined.contains("idrac8") || combined.contains("idrac 8") {
                            family = .dellIDRAC8
                        } else if combined.contains("idrac7") || combined.contains("idrac 7") {
                            family = .dellIDRAC7
                        } else if family == .unknown {
                            family = redfishSupported ? .dellIDRAC8 : .dellIDRACLegacy
                        }
                        detectedTitle = title ?? family.displayName
                    } else if combined.contains("megarac")
                        || combined.contains("american megatrends")
                        || combined.contains("openbmc")
                        || combined.contains("iru")
                        || combined.contains("aspeed")
                        || combined.contains("ipmi")
                        || combined.contains("bmc") {
                        confirmedBMC = true
                        vendor = .iruBMC
                        if combined.contains("openbmc") {
                            family = .iruOpenBMC
                        } else {
                            family = .iruMegaRAC
                        }
                        detectedTitle = title ?? family.displayName
                    } else if detectedTitle == nil {
                        detectedTitle = title ?? (serverHeader.isEmpty ? nil : serverHeader)
                    }
                }
            }
        }

        let suggestedName: String
        if confirmedBMC {
            suggestedName = "\(family.shortBadge) (\(ip))"
        } else if let title = detectedTitle, !title.isEmpty {
            suggestedName = String(title.prefix(32))
        } else {
            suggestedName = "Хост \(ip)"
        }

        return DiscoveredBMC(
            ip: ip,
            port: port,
            scheme: scheme,
            vendor: vendor,
            bmcFamily: family,
            suggestedName: suggestedName,
            detectedTitle: detectedTitle,
            redfishVersion: redfishVersion,
            redfishSupported: redfishSupported,
            isConfirmedBMC: confirmedBMC,
            latencyMs: latencyMs
        )
    }

    private static func extractHTMLTitle(from html: String) -> String? {
        guard let startRange = html.range(of: "<title", options: .caseInsensitive),
              let tagClose = html.range(of: ">", range: startRange.upperBound..<html.endIndex),
              let endRange = html.range(of: "</title>", options: .caseInsensitive, range: tagClose.upperBound..<html.endIndex) else {
            return nil
        }
        let raw = String(html[tagClose.upperBound..<endRange.lowerBound])
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }
}

// MARK: - Неизолированные сетевые утилиты (TCP-пинг, локальный IP без ifaddrs.h, Kerio VPN, WoL UDP)

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

private final class BonjourResolveState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let connection: NWConnection
    private let continuation: CheckedContinuation<String?, Never>

    init(connection: NWConnection, continuation: CheckedContinuation<String?, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ ip: String?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()

        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(returning: ip)
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

    static func resolveBonjourIPv4(endpoint: NWEndpoint) async -> String? {
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.andrey.saluteremoteplus.bonjour-resolve")
            let conn = NWConnection(to: endpoint, using: .tcp)
            let state = BonjourResolveState(connection: conn, continuation: continuation)

            conn.stateUpdateHandler = { connState in
                switch connState {
                case .ready:
                    if let remote = conn.currentPath?.remoteEndpoint,
                       case .hostPort(let host, _) = remote {
                        let raw = "\(host)".split(separator: "%").first.map(String.init) ?? ""
                        let parts = raw.split(separator: ".")
                        if parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) {
                            state.finish(raw)
                            return
                        }
                    }
                    state.finish(nil)
                case .failed, .cancelled:
                    state.finish(nil)
                default:
                    break
                }
            }

            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2.0) {
                state.finish(nil)
            }
        }
    }

    /// Определяет локальные IPv4-адреса устройства (Wi-Fi / Kerio VPN) через BSD UDP connect+getsockname без <ifaddrs.h>.
    static func detectLocalIPv4Addresses() -> [String] {
        let probeTargets = ["192.168.1.1", "10.0.0.1", "172.16.0.1", "1.1.1.1"]
        var found: [String] = []
        for target in probeTargets {
            if let local = localIPv4(routedToward: target),
               !local.hasPrefix("127."),
               !local.hasPrefix("169.254."),
               !found.contains(local) {
                found.append(local)
            }
        }
        return found
    }

    private static func localIPv4(routedToward remoteIP: String) -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var remote = sockaddr_in()
        remote.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = UInt16(53).bigEndian
        guard inet_pton(AF_INET, remoteIP, &remote.sin_addr) == 1 else { return nil }

        let connectResult: Int32 = withUnsafePointer(to: &remote) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else { return nil }

        var local = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult: Int32 = withUnsafeMutablePointer(to: &local) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(fd, sockPtr, &len)
            }
        }
        guard nameResult == 0 else { return nil }

        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var addrCopy = local.sin_addr
        guard inet_ntop(AF_INET, &addrCopy, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buf)
    }

    static func subnetCIDR(fromIP ip: String) -> String? {
        let octets = ip.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return nil }
        return "\(octets[0]).\(octets[1]).\(octets[2]).0/24"
    }

    static func detectNetworkRoute(from path: NWPath) -> NetworkRouteStatus {
        guard path.status == .satisfied else { return .offline }
        let vpnInterface = activeVPNInterfaceName(from: path)
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
    /// через системные scoped-интерфейсы CFNetwork и активные интерфейсы NWPath (без C-заголовка ifaddrs.h).
    static func activeVPNInterfaceName(from path: NWPath) -> String? {
        let vpnPrefixes = ["utun", "ipsec", "ppp", "tap", "tun"]

        if let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
           let scoped = proxySettings["__SCOPED__"] as? [String: Any] {
            for key in scoped.keys {
                let lower = key.lowercased()
                if vpnPrefixes.contains(where: { lower.hasPrefix($0) }) {
                    return key
                }
            }
        }

        for iface in path.availableInterfaces where iface.type == .other {
            let lower = iface.name.lowercased()
            if vpnPrefixes.contains(where: { lower.hasPrefix($0) }) {
                return iface.name
            }
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
