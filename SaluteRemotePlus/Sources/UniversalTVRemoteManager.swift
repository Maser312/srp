import Foundation
import SwiftUI
import Combine
import LibSberCast
import Darwin

/// Единый координатор универсального пульта ТВ:
/// объединяет Сбер Салют ТВ (SberCast/StarOS), Android TV / Google TV (Remote Protocol v2)
/// и YaOS / Яндекс ТВ (Remote v2 + ADB Wi-Fi :5555), хранит несколько сохранённых ТВ
/// и мгновенно переключает активный пульт.
@MainActor
final class UniversalTVRemoteManager: NSObject, ObservableObject {
    // MARK: - Подчинённые движки протоколов
    let sber = SberCastRemote()
    let androidClient = AndroidTVRemoteClient()
    let adbClient = ADBTVRemoteClient()

    // MARK: - Состояние и профили
    @Published private(set) var savedTVs: [SavedTVProfile] = []
    @Published private(set) var discoveredTVs: [DiscoveredTVDevice] = []
    @Published private(set) var activeProfile: SavedTVProfile?
    @Published private(set) var isScanning = false
    @Published var pin: String = ""
    @Published private(set) var noticeText: String?

    private let lastActiveProfileIdKey = "SaluteRemotePlus.lastActiveTVProfileId"
    private var isSectionActive = false
    private var browsers: [NetServiceBrowser] = []
    private var resolvingServices: [NetService] = []
    private var bonjourDiscovered: [String: DiscoveredTVDevice] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var noticeTask: Task<Void, Never>?

    override init() {
        super.init()
        savedTVs = SavedTVStore.load()

        // Автосохранение признака сопряжения после успешного PIN Android TV / YaOS
        androidClient.onPairingSucceeded = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, var profile = self.activeProfile else { return }
                profile.isPaired = true
                profile.lastConnectedAt = Date()
                self.upsertProfile(profile, makeActive: true)
            }
        }

        // Пробрасываем обновления всех трёх клиентов в SwiftUI
        sber.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.syncSberDiscoveryAndConnection()
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        androidClient.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        adbClient.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Вычисляемое состояние для UI

    var activePlatform: TVPlatform {
        if let profile = activeProfile {
            return profile.platform
        }
        if sber.connectedDevice != nil {
            return .sberSalute
        }
        return .sberSalute
    }

    var isShowingRemotePad: Bool {
        if let profile = activeProfile {
            if profile.platform == .sberSalute {
                return sber.connectedDevice != nil
            }
            return true
        }
        return sber.connectedDevice != nil
    }

    var activeDeviceName: String {
        if let profile = activeProfile {
            return profile.name
        }
        return sber.connectedDevice?.name ?? "Салют ТВ"
    }

    var isChannelReady: Bool {
        switch activePlatform {
        case .sberSalute:
            return sber.session != nil && sber.wireReady
        case .androidTV, .yaOS:
            if activeProfile?.connectionMethod == .adbWiFi {
                return adbClient.isReady
            }
            return androidClient.isReady
        }
    }

    var statusText: String {
        switch activePlatform {
        case .sberSalute:
            if sber.connectedDevice != nil {
                if sber.session == nil { return "Подключение канала…" }
                return sber.wireReady ? "Пульт готов" : "Открываем канал…"
            }
            return sber.status
        case .androidTV, .yaOS:
            if activeProfile?.connectionMethod == .adbWiFi {
                return adbClient.statusText
            }
            return androidClient.statusText
        }
    }

    var errorText: String? {
        switch activePlatform {
        case .sberSalute:
            return sber.error
        case .androidTV, .yaOS:
            if activeProfile?.connectionMethod == .adbWiFi {
                return adbClient.errorText
            }
            return androidClient.errorText
        }
    }

    var effectiveNotice: String? {
        noticeText ?? (activePlatform == .sberSalute ? sber.notice : nil)
    }

    var voiceState: SberCastRemote.VoiceState {
        activePlatform == .sberSalute ? sber.voiceState : .idle
    }

    var needsPin: Bool {
        sber.needsPin || androidClient.needsPin
    }

    var pinIsHex: Bool {
        androidClient.needsPin && !sber.needsPin
    }

    var pinTargetName: String {
        if sber.needsPin {
            return sber.connectedDevice?.name ?? "Салют ТВ"
        }
        return activeProfile?.name ?? "Android TV"
    }

    var availablePadModes: [CenterPadMode] {
        if activePlatform.supportsMouseAndAir {
            return [.dpad, .gestures, .airMouse, .trackpad]
        }
        return [.dpad, .gestures]
    }

    // MARK: - Жизненный цикл (строго по требованию при открытии раздела «Пульт ТВ»)

    func resume() {
        isSectionActive = true
        sber.resume()
        startBonjourDiscovery()

        // Если активный не-Сбер профиль был выбран ранее, переподключаем его
        if let profile = activeProfile, profile.platform != .sberSalute {
            connectExternalProfile(profile)
        } else if activeProfile == nil,
                  let lastId = UserDefaults.standard.string(forKey: lastActiveProfileIdKey),
                  let lastProfile = savedTVs.first(where: { $0.id == lastId }),
                  lastProfile.platform != .sberSalute {
            activeProfile = lastProfile
            connectExternalProfile(lastProfile)
        }
    }

    func pause() {
        isSectionActive = false
        stopBonjourDiscovery()
        sber.pause()
        androidClient.disconnect(silent: true)
        adbClient.disconnect(silent: true)
    }

    func refreshDiscovery() {
        stopBonjourDiscovery()
        bonjourDiscovered.removeAll()
        rebuildDiscoveredList()
        startBonjourDiscovery()
        if isSectionActive {
            sber.resume()
        }
    }

    // MARK: - Управление списком сохранённых ТВ и переключение

    func upsertProfile(_ profile: SavedTVProfile, makeActive: Bool = false) {
        if let idx = savedTVs.firstIndex(where: { $0.id == profile.id }) {
            savedTVs[idx] = profile
        } else {
            savedTVs.insert(profile, at: 0)
        }
        SavedTVStore.save(savedTVs)
        if makeActive {
            activeProfile = profile
            UserDefaults.standard.set(profile.id, forKey: lastActiveProfileIdKey)
        }
    }

    func deleteProfile(_ profile: SavedTVProfile) {
        savedTVs.removeAll { $0.id == profile.id }
        SavedTVStore.save(savedTVs)
        if activeProfile?.id == profile.id {
            disconnectActiveTV()
        }
    }

    func switchToProfile(_ profile: SavedTVProfile) {
        var updated = profile
        updated.lastConnectedAt = Date()
        upsertProfile(updated, makeActive: true)

        switch updated.platform {
        case .sberSalute:
            androidClient.disconnect(silent: true)
            adbClient.disconnect(silent: true)
            if let devId = updated.sberDeviceId,
               let match = sber.devices.first(where: { $0.id == devId }) {
                sber.connect(match)
            } else if let matchByName = sber.devices.first(where: { $0.name == updated.name }) {
                sber.connect(matchByName)
            } else {
                sber.resume()
                showNotice("Поиск \(updated.name) в сети Wi-Fi…")
            }

        case .androidTV, .yaOS:
            sber.pause()
            connectExternalProfile(updated)
        }
    }

    func connectDiscovered(_ device: DiscoveredTVDevice) {
        switch device.platform {
        case .sberSalute:
            androidClient.disconnect(silent: true)
            adbClient.disconnect(silent: true)
            if let devId = device.sberDeviceId,
               let sberDev = sber.devices.first(where: { $0.id == devId }) {
                let profile = findOrCreateSberProfile(for: sberDev)
                upsertProfile(profile, makeActive: true)
                sber.connect(sberDev)
            }

        case .androidTV, .yaOS:
            sber.pause()
            let existing = savedTVs.first {
                $0.platform == device.platform &&
                $0.host.caseInsensitiveCompare(device.host) == .orderedSame &&
                $0.connectionMethod == device.connectionMethod
            }
            var profile = existing ?? SavedTVProfile(
                name: device.name,
                platform: device.platform,
                connectionMethod: device.connectionMethod,
                host: device.host,
                remotePort: device.port,
                pairingPort: device.pairingPort,
                isPaired: false
            )
            profile.host = device.host
            profile.remotePort = device.port
            if device.pairingPort > 0 { profile.pairingPort = device.pairingPort }
            profile.lastConnectedAt = Date()
            upsertProfile(profile, makeActive: true)
            connectExternalProfile(profile)
        }
    }

    func disconnectActiveTV() {
        if activePlatform == .sberSalute || sber.connectedDevice != nil {
            sber.forgetSavedDevice()
        }
        androidClient.disconnect(silent: true)
        adbClient.disconnect(silent: true)
        activeProfile = nil
        UserDefaults.standard.removeObject(forKey: lastActiveProfileIdKey)
        if isSectionActive {
            startBonjourDiscovery()
        }
    }

    func reconnectActiveTV() {
        guard let profile = activeProfile else {
            sber.reconnectChannel()
            return
        }
        switch profile.platform {
        case .sberSalute:
            sber.reconnectChannel()
        case .androidTV, .yaOS:
            connectExternalProfile(profile)
        }
    }

    private func connectExternalProfile(_ profile: SavedTVProfile) {
        switch profile.connectionMethod {
        case .androidTVRemoteV2:
            adbClient.disconnect(silent: true)
            androidClient.connect(
                host: profile.host,
                remotePort: profile.remotePort,
                pairingPort: profile.pairingPort,
                alreadyPaired: profile.isPaired
            )
        case .adbWiFi:
            androidClient.disconnect(silent: true)
            adbClient.connect(host: profile.host, port: profile.remotePort)
        case .sberCast:
            break
        }
    }

    // MARK: - Унифицированное подтверждение PIN

    func confirmPIN() {
        if sber.needsPin {
            sber.pin = pin
            sber.confirmPIN()
            pin = ""
        } else if androidClient.needsPin {
            androidClient.submitPairingPin(pin)
            if androidClient.errorText == nil {
                pin = ""
            }
        }
    }

    func cancelPin() {
        pin = ""
        if sber.needsPin {
            sber.cancelPin()
        }
        if androidClient.needsPin {
            androidClient.cancelPairing()
        }
    }

    // MARK: - Унифицированная отправка команд

    func send(_ command: RemoteCommand) {
        switch activePlatform {
        case .sberSalute:
            sber.send(command)
        case .androidTV, .yaOS:
            if activeProfile?.connectionMethod == .adbWiFi {
                adbClient.sendCommand(command)
            } else {
                androidClient.sendCommand(command)
            }
        }
    }

    func sendDown(_ command: RemoteCommand) {
        switch activePlatform {
        case .sberSalute:
            sber.sendDown(command)
        case .androidTV, .yaOS:
            if activeProfile?.connectionMethod == .adbWiFi {
                adbClient.sendCommandDown(command)
            } else {
                androidClient.sendCommandDown(command)
            }
        }
    }

    func sendUp(_ command: RemoteCommand) {
        switch activePlatform {
        case .sberSalute:
            sber.sendUp(command)
        case .androidTV, .yaOS:
            if activeProfile?.connectionMethod == .adbWiFi {
                adbClient.sendCommandUp(command)
            } else {
                androidClient.sendCommandUp(command)
            }
        }
    }

    func toggleVoice() {
        switch activePlatform {
        case .sberSalute:
            sber.toggleVoice()
        case .androidTV:
            send(.assist)
            showNotice("Вызван Google Ассистент")
        case .yaOS:
            send(.assist)
            showNotice("Вызвана Алиса на ТВ")
        }
    }

    func findRemote() {
        if activePlatform == .sberSalute {
            sber.findRemote()
        } else {
            send(.source)
            showNotice("Переключение входа (HDMI / TV)")
        }
    }

    func setControllerMode(_ mode: GamepadWire.ControllerMode) {
        if activePlatform == .sberSalute {
            sber.setControllerMode(mode)
        }
    }

    func sendMouseOffset(dx: Float, dy: Float) {
        if activePlatform == .sberSalute {
            sber.sendMouseOffset(dx: dx, dy: dy)
        }
    }

    func sendMouseVerticalScroll(_ offset: Float) {
        if activePlatform == .sberSalute {
            sber.sendMouseVerticalScroll(offset)
        } else if offset > 0 {
            send(.up)
        } else if offset < 0 {
            send(.down)
        }
    }

    func sendMouseHorizontalScroll(_ offset: Float) {
        if activePlatform == .sberSalute {
            sber.sendMouseHorizontalScroll(offset)
        } else if offset > 0 {
            send(.right)
        } else if offset < 0 {
            send(.left)
        }
    }

    func sendKey(_ linuxKeyCode: Int32) {
        switch activePlatform {
        case .sberSalute:
            sber.sendKey(linuxKeyCode)
        case .androidTV, .yaOS:
            let code = KeyMap.androidKeyCode(for: linuxKeyCode)
            if activeProfile?.connectionMethod == .adbWiFi {
                adbClient.sendKeyCode(code)
            } else {
                androidClient.sendKeyCode(code)
            }
        }
    }

    func typeText(_ text: String, submit: Bool) {
        switch activePlatform {
        case .sberSalute:
            sber.typeText(text, submit: submit)
        case .androidTV, .yaOS:
            if activeProfile?.connectionMethod == .adbWiFi {
                adbClient.sendText(text, submit: submit)
            } else {
                androidClient.sendText(text, submit: submit)
            }
            showNotice("Текст отправлен на ТВ")
        }
    }

    func tvSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch activePlatform {
        case .sberSalute:
            sber.tvSearch(trimmed)
        case .androidTV, .yaOS:
            send(.search)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.typeText(trimmed, submit: true)
            }
            showNotice("Поиск: \(trimmed)")
        }
    }

    func youtubeSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch activePlatform {
        case .sberSalute:
            sber.youtubeSearch(trimmed)
        case .androidTV, .yaOS:
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            let url = "https://www.youtube.com/results?search_query=\(encoded)"
            if activeProfile?.connectionMethod == .adbWiFi {
                adbClient.openDeepLink(url)
            } else {
                androidClient.sendAppLink(url)
            }
            showNotice("Поиск на YouTube: \(trimmed)")
        }
    }

    private func showNotice(_ text: String) {
        noticeText = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.noticeText == text {
                    self?.noticeText = nil
                }
            }
        }
    }

    // MARK: - Синхронизация Сбер-устройств

    private func syncSberDiscoveryAndConnection() {
        if let connected = sber.connectedDevice {
            if activeProfile == nil || activeProfile?.platform == .sberSalute {
                let profile = findOrCreateSberProfile(for: connected)
                if activeProfile?.id != profile.id {
                    upsertProfile(profile, makeActive: true)
                }
            }
        }
        rebuildDiscoveredList()
    }

    private func findOrCreateSberProfile(for dev: LibSberCast.SberCastDevice) -> SavedTVProfile {
        if var existing = savedTVs.first(where: { $0.platform == .sberSalute && ($0.sberDeviceId == dev.id || $0.name == dev.name) }) {
            existing.name = dev.name
            existing.sberDeviceId = dev.id
            existing.isPaired = true
            existing.lastConnectedAt = Date()
            return existing
        }
        return SavedTVProfile(
            name: dev.name,
            platform: .sberSalute,
            connectionMethod: .sberCast,
            host: "",
            sberDeviceId: dev.id,
            isPaired: true,
            lastConnectedAt: Date()
        )
    }

    private func rebuildDiscoveredList() {
        var list: [DiscoveredTVDevice] = []
        for sberDev in sber.devices {
            list.append(
                DiscoveredTVDevice(
                    id: "sber-\(sberDev.id)",
                    name: sberDev.name,
                    platform: .sberSalute,
                    connectionMethod: .sberCast,
                    host: "",
                    port: 0,
                    pairingPort: 0,
                    sberDeviceId: sberDev.id,
                    detail: sberDev.features?.contains(.gamepadService) == true ? "Сбер Салют · Пульт доступен" : "Сбер Салют ТВ"
                )
            )
        }
        let sortedBonjour = bonjourDiscovered.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        list.append(contentsOf: sortedBonjour)
        discoveredTVs = list
    }

    // MARK: - Многопротокольный поиск Bonjour (Android TV Remote v2, YaOS / YandexIO, ADB)

    private func startBonjourDiscovery() {
        guard browsers.isEmpty else { return }
        isScanning = true
        let serviceTypes = [
            "_androidtvremote2._tcp.",
            "_yandexio._tcp.",
            "_adb-tls-connect._tcp."
        ]
        for type in serviceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.searchForServices(ofType: type, inDomain: "local.")
            browsers.append(browser)
        }
    }

    private func stopBonjourDiscovery() {
        isScanning = false
        for browser in browsers {
            browser.stop()
            browser.delegate = nil
        }
        browsers.removeAll()
        for service in resolvingServices {
            service.stop()
            service.delegate = nil
        }
        resolvingServices.removeAll()
    }

    private func classifyBonjourService(_ service: NetService, ipv4: String) -> DiscoveredTVDevice {
        let lowerName = service.name.lowercased()
        let lowerType = service.type.lowercased()
        let isYaOSName = lowerName.contains("yandex")
            || lowerName.contains("яндекс")
            || lowerName.contains("yaos")
            || lowerName.contains("station")
            || lowerName.contains("станция")
            || lowerName.contains("tuvio")
            || lowerName.contains("hartens")

        if lowerType.contains("_yandexio._tcp") {
            return DiscoveredTVDevice(
                id: "yaos-adb-\(ipv4)",
                name: service.name,
                platform: .yaOS,
                connectionMethod: .adbWiFi,
                host: ipv4,
                port: 5555,
                pairingPort: 0,
                sberDeviceId: nil,
                detail: "YaOS (Яндекс ТВ) · ADB :5555 · \(ipv4)"
            )
        }

        if lowerType.contains("_adb-tls-connect._tcp") {
            let platform: TVPlatform = isYaOSName ? .yaOS : .androidTV
            let port = service.port > 0 ? service.port : 5555
            return DiscoveredTVDevice(
                id: "adb-\(ipv4)-\(port)",
                name: service.name,
                platform: platform,
                connectionMethod: .adbWiFi,
                host: ipv4,
                port: port,
                pairingPort: 0,
                sberDeviceId: nil,
                detail: "\(platform.shortBadge) · ADB :\(port) · \(ipv4)"
            )
        }

        // _androidtvremote2._tcp (Android TV / Google TV / YaOS с Remote v2)
        let platform: TVPlatform = isYaOSName ? .yaOS : .androidTV
        let remotePort = service.port > 0 ? service.port : 6466
        return DiscoveredTVDevice(
            id: "atv2-\(ipv4)-\(remotePort)",
            name: service.name,
            platform: platform,
            connectionMethod: .androidTVRemoteV2,
            host: ipv4,
            port: remotePort,
            pairingPort: 6467,
            sberDeviceId: nil,
            detail: "\(platform.shortBadge) · Remote v2 · \(ipv4)"
        )
    }

    private func extractIPv4(from addresses: [Data]) -> String? {
        for data in addresses {
            let ip: String? = data.withUnsafeBytes { rawBuf in
                guard let base = rawBuf.baseAddress else { return nil }
                let sa = base.assumingMemoryBound(to: sockaddr.self)
                guard sa.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
                let sin = base.assumingMemoryBound(to: sockaddr_in.self)
                var addr = sin.pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buffer)
            }
            if let ip, !ip.hasPrefix("127.") {
                return ip
            }
        }
        return nil
    }
}

// MARK: - NetServiceBrowserDelegate & NetServiceDelegate

extension UniversalTVRemoteManager: NetServiceBrowserDelegate, NetServiceDelegate {
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            service.delegate = self
            self.resolvingServices.append(service)
            service.resolve(withTimeout: 5.0)
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let name = service.name
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.bonjourDiscovered = self.bonjourDiscovered.filter { $0.value.name != name }
            self.rebuildDiscoveredList()
        }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let addresses = sender.addresses ?? []
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let ipv4 = self.extractIPv4(from: addresses) {
                let device = self.classifyBonjourService(sender, ipv4: ipv4)
                self.bonjourDiscovered[device.id] = device
                self.rebuildDiscoveredList()
            }
            self.resolvingServices.removeAll { $0 === sender }
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Task { @MainActor [weak self] in
            self?.resolvingServices.removeAll { $0 === sender }
        }
    }
}
