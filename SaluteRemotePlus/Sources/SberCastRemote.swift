import Foundation
import Network
import Security
import LibSberCast
import Combine

/// Хранилище токенов сопряжения в Keychain (чтобы не терять авторизацию между запусками).
private enum DeviceTokenStore {
    private static let service = "com.andrey.saluteremoteplus.sbercast-token"

    static func save(_ token: String, for deviceId: String) {
        guard !token.isEmpty, let data = token.data(using: .utf8) else { return }
        delete(for: deviceId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceId,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(for deviceId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    static func delete(for deviceId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceId
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class SberCastRemote: NSObject, ObservableObject, LibSberCast.SberCastListener, LibSberCast.VoiceTransportListener {
    @Published private(set) var devices: [LibSberCast.SberCastDevice] = []
    @Published private(set) var status = "Запуск…"
    @Published private(set) var connectedDevice: LibSberCast.SberCastDevice?
    @Published private(set) var session: GamepadSession? {
        didSet { if let s = session { wire.prepare(session: s) } else { wire.stop() } }
    }
    @Published private(set) var wireReady = false
    @Published private(set) var voiceState: VoiceState = .idle
    @Published private(set) var notice: String?
    enum VoiceState: Equatable { case idle, starting, listening }
    let wire = GamepadWire()
    private let mic = MicStreamer()
    @Published var pin: String = ""
    @Published private(set) var needsPin = false
    @Published private(set) var error: String?

    private let cast: any LibSberCast.SberCast
    private var activeDeviceID: String?
    private var permissionBrowser: NWBrowser?
    private var autoConnectAttempted = false
    private var started = false
    private var paused = false
    private var gamepadRequestInFlight = false
    private var deviceConnectInFlight = false
    private var awaitingGamepadAfterConnect = false
    private var connectTimeoutTask: Task<Void, Never>?
    private var waitConnectedTask: Task<Void, Never>?
    private var gamepadRetryTask: Task<Void, Never>?
    private var resumeCheckTask: Task<Void, Never>?
    private var gamepadRetryCount = 0
    private var reconnectRetryCount = 0
    private var wireReconnectCount = 0
    private var restartTask: Task<Void, Never>?
    private var noticeClearTask: Task<Void, Never>?
    private var discoveryRestarts = 0

    private let savedDeviceIDKey = "SaluteRemotePlus.savedDeviceID"
    private let savedDeviceNameKey = "SaluteRemotePlus.savedDeviceName"

    private var lastKnownVolume = 25
    private var lastVolumeTapAt: Date = .distantPast
    private var lastKnownMuted = false
    private var lastKnownPlaying = false

    override init() {
        self.cast = LibSberCast.SberCastFactory.makeSberCast(clientName: "SaluteRemotePlus")
        super.init()
        cast.setMetaDataUpdatesFilter(filter: [.basic, .volumeInfo, .mediaState])
        cast.addListener(listener: self)
        cast.setClientName(name: "SaluteRemotePlus")
        cast.setClientId(name: "saluteremoteplus")
        _ = cast.voiceTransport.resetListener(listener: self)
        Publishers.CombineLatest(wire.$ready, wire.$handshakeConfirmed)
            .map { $0 && $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                self?.wireReady = ready
                if ready { self?.wireReconnectCount = 0 }
            }
            .store(in: &cancellables)
        wire.onReconnectNeeded = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleWireReconnectNeeded()
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()

    private func handleWireReconnectNeeded() {
        guard !paused,
              connectedDevice != nil,
              !needsPin,
              !gamepadRequestInFlight,
              !deviceConnectInFlight else { return }
        wireReconnectCount += 1
        guard wireReconnectCount <= 3 else {
            error = "Канал пульта разорван. Нажмите обновление для переподключения."
            status = "Канал пульта закрыт"
            return
        }
        session = nil
        awaitingGamepadAfterConnect = true
        if isActiveDeviceConnected {
            gamepadRetryCount = 0
            requestGamepadSession()
        } else {
            connectAuthorizedDevice()
        }
    }

    private var activeDeviceFromList: LibSberCast.SberCastDevice? {
        guard let id = activeDeviceID else { return nil }
        return devices.first(where: { $0.id == id })
    }

    private var isActiveDeviceConnected: Bool {
        activeDeviceFromList?.isConnected == true
    }

    private func showNotice(_ text: String?, autoClear: Bool = true) {
        noticeClearTask?.cancel()
        noticeClearTask = nil
        notice = text
        guard autoClear, let text, !text.isEmpty else { return }
        noticeClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.notice == text { self?.notice = nil }
            }
        }
    }

    // MARK: - Кнопки, курсор, текст, голос

    func send(_ command: RemoteCommand) {
        // Громкость с шагом 1: если подтверждён официальный UDP-канал пульта — шлём нативные
        // кнопки Салют (37/38), как родной пульт; иначе используем LibSberCast с шагом ±1.
        if command == .volumeUp || command == .volumeDown {
            if session != nil && wire.ready && wire.handshakeConfirmed {
                showNotice(nil)
                wire.press(Int32(command.buttonCode))
                return
            }
            if let id = activeDeviceID, isActiveDeviceConnected {
                let now = Date()
                let base: Int
                if now.timeIntervalSince(lastVolumeTapAt) < 0.8 {
                    base = lastKnownVolume
                } else {
                    base = connectedDevice?.metadata?.volume.percent ?? lastKnownVolume
                }
                let next = command == .volumeUp ? min(100, base + 1) : max(0, base - 1)
                lastKnownVolume = next
                lastVolumeTapAt = now
                _ = cast.sendRequest(deviceId: id, request: LibSberCast.CastRequest(type: .setVolumeRequest(volumePercentValue: next)))
                showNotice("Громкость: \(next)%")
                return
            }
        }

        // Mute, Play/Pause и Настройки отправляем напрямую через официальный канал LibSberCast.
        if let id = activeDeviceID, isActiveDeviceConnected {
            switch command {
            case .mute:
                let muted = connectedDevice?.metadata?.volume.muted ?? lastKnownMuted
                let nextMuted = !muted
                lastKnownMuted = nextMuted
                let cmd: LibSberCast.CastRequestType.MediaCommandType = nextMuted ? .mute : .unmute
                _ = cast.sendRequest(deviceId: id, request: LibSberCast.CastRequest(type: .mediaCommandRequest(command: cmd)))
                showNotice(nextMuted ? "Звук выключен" : "Звук включён")
                return
            case .playPause:
                let playing = currentMediaPlaying ?? lastKnownPlaying
                let nextPlaying = !playing
                lastKnownPlaying = nextPlaying
                let cmd: LibSberCast.CastRequestType.MediaCommandType = nextPlaying ? .play : .pause
                _ = cast.sendRequest(deviceId: id, request: LibSberCast.CastRequest(type: .mediaCommandRequest(command: cmd)))
                showNotice(nextPlaying ? "Воспроизведение" : "Пауза")
                return
            case .settings:
                _ = cast.sendDirective(deviceId: id, directive: LibSberCast.CastDirective(.openDeeplink("sberdevices_app_v2://settings")))
                showNotice("Открываем настройки ТВ")
                return
            default:
                break
            }
        }

        guard session != nil else {
            showNotice("Канал пульта ещё не готов — переподключаем…", autoClear: false)
            if !gamepadRequestInFlight && !deviceConnectInFlight { reconnectChannel() }
            return
        }
        showNotice(nil)
        wire.press(Int32(command.keyCode))
    }

    func sendDown(_ command: RemoteCommand) {
        guard session != nil else {
            showNotice("Канал пульта ещё не готов — переподключаем…", autoClear: false)
            if !gamepadRequestInFlight && !deviceConnectInFlight { reconnectChannel() }
            return
        }
        showNotice(nil)
        wire.keyDown(Int32(command.keyCode))
    }

    func sendUp(_ command: RemoteCommand) {
        guard session != nil else { return }
        wire.keyUp(Int32(command.keyCode))
    }

    func sendLongPress(_ command: RemoteCommand, duration: TimeInterval = 1.2) {
        guard session != nil else {
            showNotice("Канал пульта ещё не готов — переподключаем…", autoClear: false)
            if !gamepadRequestInFlight && !deviceConnectInFlight { reconnectChannel() }
            return
        }
        wire.longPress(Int32(command.keyCode), duration: duration)
    }

    private var currentMediaPlaying: Bool? {
        guard let info = connectedDevice?.metadata?.mediaInfo.playerInfo else { return nil }
        switch info {
        case .music(let player): return player.playing
        case .radio(let player): return player.playing
        case .bluetooth(let player): return player.playing
        case .noPlayer: return nil
        }
    }

    func findRemote() {
        guard let id = activeDeviceID, isActiveDeviceConnected else {
            showNotice("Телевизор не подключён")
            return
        }
        _ = cast.sendRequest(deviceId: id, request: LibSberCast.CastRequest(type: .findRemoteControllerRequest))
        showNotice("Отправлен сигнал поиска пульта")
    }

    func sendKey(_ code: Int32) {
        guard session != nil else {
            showNotice("Канал пульта ещё не готов")
            return
        }
        wire.sendKeyboardKey(code)
    }

    /// Повторно запросить у ТВ параметры игрового канала (с проверкой состояния соединения).
    func reconnectChannel() {
        guard connectedDevice != nil, !needsPin else { return }
        gamepadRetryTask?.cancel()
        gamepadRetryTask = nil
        waitConnectedTask?.cancel()
        waitConnectedTask = nil
        gamepadRequestInFlight = false
        gamepadRetryCount = 0
        reconnectRetryCount = 0
        wireReconnectCount = 0
        awaitingGamepadAfterConnect = true
        error = nil
        session = nil

        if isActiveDeviceConnected {
            requestGamepadSession()
        } else {
            connectAuthorizedDevice()
        }
    }

    /// Отменить подключение, ожидающее PIN-код.
    func cancelPin() {
        if let id = activeDeviceID { _ = cast.cancelDeviceConnectionRequest(deviceId: id) }
        cancelPendingConnectionTasks()
        needsPin = false
        pin = ""
        connectedDevice = nil
        activeDeviceID = nil
        session = nil
        status = "Подключение отменено"
    }

    private func cancelPendingConnectionTasks() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        waitConnectedTask?.cancel()
        waitConnectedTask = nil
        gamepadRetryTask?.cancel()
        gamepadRetryTask = nil
        resumeCheckTask?.cancel()
        resumeCheckTask = nil
        deviceConnectInFlight = false
        gamepadRequestInFlight = false
        awaitingGamepadAfterConnect = false
    }

    private func scheduleDiscoveryRestart() {
        guard discoveryRestarts < 5 else {
            error = "Нет доступа к локальной сети. Проверьте Настройки → Конфиденциальность → Локальная сеть → RemoteA"
            return
        }
        discoveryRestarts += 1
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !self.paused, self.started, self.connectedDevice == nil else { return }
                self.cast.stop()
                self.cast.start()
            }
        }
    }

    func typeText(_ text: String, submit: Bool) {
        guard session != nil else {
            showNotice("Канал пульта ещё не готов")
            return
        }
        wire.typeSymbols(text)
        if submit { wire.sendKeyboardKey(KeyMap.enter) }
        showNotice(nil)
    }

    func tvSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = activeDeviceID, isActiveDeviceConnected else {
            showNotice("Телевизор не подключён")
            return
        }
        guard !trimmed.isEmpty else { return }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+#/")
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        let deeplink = "star_launcher://search?query=\(encoded)&source=salute_remote_control"
        _ = cast.sendDirective(deviceId: id, directive: LibSberCast.CastDirective(.openDeeplink(deeplink)))
        showNotice("Ищем на ТВ…")
    }

    func setControllerMode(_ mode: GamepadWire.ControllerMode) {
        wire.switchControllerMode(mode)
    }

    func sendMouseOffset(dx: Float, dy: Float) {
        guard session != nil else { return }
        wire.sendMouseOffset(dx: dx, dy: dy)
    }

    func sendMouseVerticalScroll(_ offset: Float) {
        guard session != nil else { return }
        wire.sendMouseVerticalScroll(offset)
    }

    func sendMouseHorizontalScroll(_ offset: Float) {
        guard session != nil else { return }
        wire.sendMouseHorizontalScroll(offset)
    }

    func youtubeSearch(_ text: String) {
        guard let id = activeDeviceID, !text.isEmpty else { return }
        _ = cast.sendDirective(deviceId: id, directive: LibSberCast.CastDirective(.showYouTubeSearchDirective(textToSearch: text)))
    }

    func toggleVoice() {
        voiceState == .idle ? startVoice() : cancelVoice()
    }

    private func startVoice() {
        guard let id = activeDeviceID, connectedDevice != nil else {
            notice = "Телевизор не подключён"
            return
        }
        MicStreamer.requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else { self.error = "Нет доступа к микрофону — разрешите в Настройках iOS"; return }
            self.error = nil; self.notice = nil; self.voiceState = .starting
            self.cast.voiceTransport.startVoiceInput(deviceId: id)
        }
    }

    private func cancelVoice() {
        if let id = activeDeviceID { cast.voiceTransport.cancelVoiceInput(deviceId: id) }
        endVoice()
    }

    private func endVoice() { mic.stop(); voiceState = .idle }

    private func beginStreaming(deviceId: String) {
        let transport = cast.voiceTransport
        do {
            try mic.start { chunk in
                transport.sendAudioData(deviceId: deviceId, audioType: .pcm16khz16bit, audioData: chunk)
            }
            voiceState = .listening
        } catch {
            self.error = "Микрофон: \(error.localizedDescription)"
            cancelVoice()
        }
    }

    private func handleVoice(deviceId: String, status: LibSberCast.VoiceTransportConversationStatus) {
        switch status {
        case .listening: if voiceState == .starting { beginStreaming(deviceId: deviceId) }
        case .listeningComplete, .ended, .cancelled: endVoice()
        case .error, .deviceNotConnected: error = "Голосовой ввод недоступен на этом ТВ"; endVoice()
        case .notStarted, .unknown: break
        }
    }

    nonisolated func onStartVoiceInputResponse(deviceId: String, status: LibSberCast.VoiceTransportConversationStatus) {
        Task { @MainActor [weak self] in self?.handleVoice(deviceId: deviceId, status: status) }
    }
    nonisolated func onSendAudioDataResponse(deviceId: String, status: LibSberCast.VoiceTransportConversationStatus) {
        Task { @MainActor [weak self] in self?.handleVoice(deviceId: deviceId, status: status) }
    }
    nonisolated func onCancelVoiceInputResponse(deviceId: String, status: LibSberCast.VoiceTransportConversationStatus) {
        Task { @MainActor [weak self] in self?.endVoice() }
    }

    var hasSavedDevice: Bool {
        UserDefaults.standard.string(forKey: savedDeviceIDKey) != nil
    }

    func start() {
        guard !started else { return }
        started = true
        paused = false
        error = nil
        autoConnectAttempted = false
        gamepadRetryCount = 0
        reconnectRetryCount = 0
        status = hasSavedDevice ? "Восстанавливаем телевизор…" : "Подключаемся к локальной сети…"
        startBonjourPermissionProbe()
    }

    func resume() {
        if started && !paused {
            return
        }
        paused = false
        if !started {
            start()
            return
        }

        if cast.isPaused || !cast.isRunning {
            cast.start()
        }

        if connectedDevice != nil && !needsPin {
            // После сворачивания ТВ закрывает старую UDP-сессию — всегда запрашиваем свежую
            // сразу после восстановления WSS-подключения SberCast.
            session = nil
            error = nil
            gamepadRetryCount = 0
            reconnectRetryCount = 0
            wireReconnectCount = 0
            awaitingGamepadAfterConnect = true
            status = "Восстанавливаем канал пульта…"

            resumeCheckTask?.cancel()
            resumeCheckTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self,
                          !self.paused,
                          self.connectedDevice != nil,
                          !self.needsPin,
                          self.session == nil,
                          !self.gamepadRequestInFlight else { return }
                    if self.isActiveDeviceConnected {
                        self.requestGamepadSession()
                    } else {
                        self.scheduleGamepadSessionWhenConnected()
                    }
                }
            }
        } else if connectedDevice == nil {
            reconnectSavedDeviceIfPossible()
        }
    }

    func pause() {
        guard !paused else { return }
        paused = true
        cancelPendingConnectionTasks()
        session = nil
        if voiceState != .idle { cancelVoice() }
        restartTask?.cancel()
        restartTask = nil
        permissionBrowser?.cancel()
        permissionBrowser = nil
        if cast.isRunning && !cast.isPaused {
            cast.pause()
        }
    }

    private func startBonjourPermissionProbe() {
        guard !paused, permissionBrowser == nil else { return }

        let browser = NWBrowser(
            for: .bonjour(type: "_staros._tcp", domain: "local."),
            using: .tcp
        )
        permissionBrowser = browser
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.permissionBrowser?.cancel()
                    self.permissionBrowser = nil
                    guard !self.paused else { return }
                    self.status = self.hasSavedDevice ? "Ищем сохранённый телевизор…" : "Ищем телевизор…"
                    if !self.cast.isRunning || self.cast.isPaused {
                        self.cast.start()
                    }
                case .failed(let error):
                    self.permissionBrowser?.cancel()
                    self.permissionBrowser = nil
                    guard !self.paused else { return }

                    self.error = "Доступ к локальной сети: \(error.localizedDescription) (код \(error.errorCode))"
                    self.status = self.hasSavedDevice ? "Ищем сохранённый телевизор…" : "Ищем телевизор…"
                    if !self.cast.isRunning || self.cast.isPaused {
                        self.cast.start()
                    }
                case .cancelled:
                    self.permissionBrowser = nil
                default:
                    break
                }
            }
        }
        browser.start(queue: DispatchQueue(label: "SaluteRemotePlus.LocalNetwork"))
    }

    func stop() {
        restartTask?.cancel()
        restartTask = nil
        cancelPendingConnectionTasks()
        permissionBrowser?.cancel()
        permissionBrowser = nil
        cast.stop()
        started = false
        paused = false
        status = hasSavedDevice ? "Остановлено — телевизор сохранён" : "Остановлено"
    }

    private func resolvedAccessToken(for deviceId: String) -> String {
        let sdkToken = cast.accessTokenForDevice(deviceId)
        if !sdkToken.isEmpty { return sdkToken }
        if let stored = DeviceTokenStore.load(for: deviceId) {
            cast.setAccessTokenForDevice(deviceId, accessToken: stored)
            return stored
        }
        return ""
    }

    func connect(_ device: LibSberCast.SberCastDevice, save: Bool = true) {
        cancelPendingConnectionTasks()
        gamepadRetryCount = 0
        reconnectRetryCount = 0
        session = nil

        activeDeviceID = device.id
        connectedDevice = device
        needsPin = false
        pin = ""
        error = nil

        if save {
            UserDefaults.standard.set(device.id, forKey: savedDeviceIDKey)
            UserDefaults.standard.set(device.name, forKey: savedDeviceNameKey)
        }

        let token = resolvedAccessToken(for: device.id)

        if device.isConnected && !token.isEmpty {
            awaitingGamepadAfterConnect = true
            requestGamepadSession()
            return
        }

        startConnectToDevice(deviceId: device.id, token: token, statusText: "Подключаемся к \(device.name)…")
    }

    func reconnectSavedDeviceIfPossible() {
        guard !autoConnectAttempted,
              let savedID = UserDefaults.standard.string(forKey: savedDeviceIDKey),
              let device = devices.first(where: { $0.id == savedID }) else { return }
        autoConnectAttempted = true
        connect(device, save: false)
    }

    private func connectAuthorizedDevice() {
        guard let id = activeDeviceID,
              connectedDevice != nil,
              !needsPin,
              !deviceConnectInFlight else { return }
        let token = resolvedAccessToken(for: id)
        awaitingGamepadAfterConnect = true
        startConnectToDevice(deviceId: id, token: token, statusText: "Завершаем подключение к телевизору…")
    }

    private func startConnectToDevice(deviceId: String, token: String, statusText: String) {
        gamepadRetryTask?.cancel()
        gamepadRetryTask = nil
        waitConnectedTask?.cancel()
        waitConnectedTask = nil
        gamepadRequestInFlight = false
        deviceConnectInFlight = true
        status = statusText

        if !token.isEmpty {
            cast.setAccessTokenForDevice(deviceId, accessToken: token)
        }
        _ = cast.connectToDevice(deviceId: deviceId, accessToken: token)

        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.deviceConnectInFlight else { return }
                self.deviceConnectInFlight = false
                if self.isActiveDeviceConnected && self.session == nil && !self.needsPin {
                    self.requestGamepadSession()
                } else {
                    self.error = "Телевизор не ответил на подключение"
                    self.status = "Таймаут подключения"
                }
            }
        }
    }

    private func scheduleGamepadSessionWhenConnected() {
        awaitingGamepadAfterConnect = true
        if isActiveDeviceConnected {
            requestGamepadSession()
            return
        }
        status = "Ждём защищённое подключение к ТВ…"
        waitConnectedTask?.cancel()
        waitConnectedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.awaitingGamepadAfterConnect,
                      self.session == nil,
                      !self.needsPin,
                      !self.gamepadRequestInFlight else { return }

                if self.isActiveDeviceConnected {
                    self.requestGamepadSession()
                    return
                }

                if !self.deviceConnectInFlight, self.reconnectRetryCount < 3 {
                    self.reconnectRetryCount += 1
                    self.connectAuthorizedDevice()
                } else {
                    self.awaitingGamepadAfterConnect = false
                    self.error = "Телевизор не установил защищённое подключение. Попробуйте переподключиться."
                    self.status = "Нет защищённого соединения с ТВ"
                }
            }
        }
    }

    func forgetSavedDevice() {
        if let savedID = UserDefaults.standard.string(forKey: savedDeviceIDKey) {
            DeviceTokenStore.delete(for: savedID)
        }
        if let activeID = activeDeviceID {
            DeviceTokenStore.delete(for: activeID)
        }
        cancelPendingConnectionTasks()
        UserDefaults.standard.removeObject(forKey: savedDeviceIDKey)
        UserDefaults.standard.removeObject(forKey: savedDeviceNameKey)
        if voiceState != .idle { cancelVoice() }
        session = nil
        connectedDevice = nil
        activeDeviceID = nil
        needsPin = false
        pin = ""
        error = nil
        reconnectRetryCount = 0
        gamepadRetryCount = 0
        wireReconnectCount = 0
        status = "Телевизор отвязан"
    }

    func confirmPIN() {
        guard let id = activeDeviceID else { return }
        let code = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        pin = code
        error = nil
        status = "Проверяем код…"
        _ = cast.confirmDeviceConnectionCode(deviceId: id, code: code)
    }

    private func requestGamepadSession() {
        guard let id = activeDeviceID, !gamepadRequestInFlight else { return }
        guard isActiveDeviceConnected else {
            scheduleGamepadSessionWhenConnected()
            return
        }
        waitConnectedTask?.cancel()
        waitConnectedTask = nil
        gamepadRequestInFlight = true
        let sid = UUID().uuidString.lowercased()
        status = "Запускаем канал пульта…"
        _ = cast.sendRequest(
            deviceId: id,
            request: LibSberCast.CastRequest(type: .getGamepadSessionCastRequest(sessionId: sid))
        )

        gamepadRetryTask?.cancel()
        gamepadRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await MainActor.run {
                guard self.gamepadRequestInFlight, self.session == nil else { return }
                self.gamepadRequestInFlight = false
                guard self.isActiveDeviceConnected else {
                    self.scheduleGamepadSessionWhenConnected()
                    return
                }
                self.gamepadRetryCount += 1
                if self.gamepadRetryCount <= 5 {
                    self.requestGamepadSession()
                } else {
                    self.error = "Телевизор не вернул параметры канала пульта"
                    self.status = self.connectedDevice == nil ? "Телевизор сохранён, но не подключён" : "Не удалось запустить канал пульта"
                }
            }
        }
    }

    // MARK: - LibSberCast.SberCastListener (nonisolated → @MainActor)

    nonisolated func onStatusChanged(status: LibSberCast.CastStatus) {
        Task { @MainActor [weak self] in self?.handleStatusChanged(status) }
    }

    nonisolated func onError(error: LibSberCast.CastError) {
        Task { @MainActor [weak self] in self?.handleError(error) }
    }

    nonisolated func onDevicesChanged(_ devices: [LibSberCast.SberCastDevice]) {
        Task { @MainActor [weak self] in self?.handleDevicesChanged(devices) }
    }

    nonisolated func onCastMessageResponse(message: LibSberCast.CastMessage) {
        Task { @MainActor [weak self] in self?.handleCastMessageResponse(message) }
    }

    nonisolated func onCastRequestResponse(response: LibSberCast.CastRequestResponse) {
        Task { @MainActor [weak self] in self?.handleCastRequestResponse(response) }
    }

    nonisolated func onBLEDeeplinkReceived(deeplink: String) { }

    nonisolated func onBLEDeeplinkRunInfo(_ info: LibSberCast.RunBLEDeeplinkOnDeviceInfo) { }

    // MARK: - MainActor handlers

    private func handleStatusChanged(_ status: LibSberCast.CastStatus) {
        switch status.state {
        case .stopped: self.status = hasSavedDevice ? "Телевизор сохранён" : "Остановлено"
        case .starting: self.status = "Запускаем обнаружение…"
        case .running:
            if connectedDevice == nil {
                self.status = hasSavedDevice ? "Ищем сохранённый телевизор…" : "Ищем телевизор…"
            }
        }
    }

    private func handleError(_ error: LibSberCast.CastError) {
        if error.msg.contains("-72000") {
            if connectedDevice != nil { return }
            scheduleDiscoveryRestart()
            return
        }
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        deviceConnectInFlight = false
        gamepadRequestInFlight = false
        self.error = error.msg
        self.status = hasSavedDevice ? "Ошибка подключения — телевизор сохранён" : "Ошибка подключения"
    }

    private func handleDevicesChanged(_ devices: [LibSberCast.SberCastDevice]) {
        self.devices = devices
        if !devices.isEmpty {
            discoveryRestarts = 0
            if error?.contains("локальной сети") == true { error = nil }
        }
        if devices.isEmpty {
            if connectedDevice == nil {
                status = hasSavedDevice ? "Ищем сохранённый телевизор…" : "Телевизор не найден"
            }
            return
        }

        if let id = activeDeviceID, let updated = devices.first(where: { $0.id == id }) {
            connectedDevice = updated

            if let meta = updated.metadata {
                lastKnownVolume = meta.volume.percent
                lastKnownMuted = meta.volume.muted
                if let playing = currentMediaPlaying {
                    lastKnownPlaying = playing
                }
            }

            if updated.isConnected,
               awaitingGamepadAfterConnect,
               session == nil,
               !needsPin,
               !gamepadRequestInFlight {
                connectTimeoutTask?.cancel()
                connectTimeoutTask = nil
                deviceConnectInFlight = false
                requestGamepadSession()
            }
        }

        if !autoConnectAttempted { reconnectSavedDeviceIfPossible() }
        if connectedDevice == nil && !hasSavedDevice { status = "Выберите телевизор" }
    }

    private func handleCastMessageResponse(_ message: LibSberCast.CastMessage) {
        if message.code != .success {
            error = message.description
        }
    }

    private func handleCastRequestResponse(_ response: LibSberCast.CastRequestResponse) {
        if case .pinConnectConfirmationCastResponse(let deviceId, let pinStatus, let token) = response.type {
            activeDeviceID = deviceId

            guard response.code == .success else {
                error = "ТВ отклонил подтверждение: \(pinStatus) (\(response.code))"
                status = "Не удалось подтвердить подключение"
                return
            }

            switch pinStatus {
            case .authorized:
                DeviceTokenStore.save(token, for: deviceId)
                cast.setAccessTokenForDevice(deviceId, accessToken: token)
                needsPin = false
                pin = ""
                error = nil
                gamepadRetryCount = 0
                reconnectRetryCount = 0
                awaitingGamepadAfterConnect = true
                connectAuthorizedDevice()
            case .wrongPin:
                error = "Неверный код. Проверьте, что код не обновился на экране ТВ."
                status = "Телевизор отклонил код"
            case .attemptsLimitReached:
                error = "Телевизор ограничил попытки ввода кода. Запросите новый код на ТВ."
                status = "Лимит попыток исчерпан"
            case .badSessionIdentifiers:
                error = "Сеанс сопряжения устарел. Начните подключение заново."
                status = "Сеанс сопряжения истёк"
            case .disabled:
                error = "Подключение по PIN отключено на телевизоре."
                status = "Сопряжение отключено"
            case .error:
                error = "Телевизор вернул ошибку подтверждения PIN."
                status = "Ошибка сопряжения"
            }
            return
        }

        guard response.code == .success else {
            gamepadRequestInFlight = false
            gamepadRetryTask?.cancel()
            gamepadRetryTask = nil

            if !deviceConnectInFlight,
               connectedDevice != nil,
               !needsPin,
               (response.code == .deviceNotConnected || response.code == .unknownDevice) {
                session = nil
                reconnectRetryCount += 1
                if reconnectRetryCount <= 4 {
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            guard let self, self.connectedDevice != nil, !self.needsPin else { return }
                            if self.isActiveDeviceConnected {
                                self.requestGamepadSession()
                            } else {
                                self.connectAuthorizedDevice()
                            }
                        }
                    }
                    return
                }
            }

            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            deviceConnectInFlight = false
            error = "Запрос к телевизору отклонён (\(response.code))"
            status = connectedDevice == nil ? "Телевизор сохранён, но недоступен" : "Ошибка подключения"
            return
        }

        switch response.type {
        case .pinConnectCastResponse(let deviceId, let status):
            activeDeviceID = deviceId
            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            deviceConnectInFlight = false

            switch status {
            case .inputPinCode:
                awaitingGamepadAfterConnect = false
                needsPin = true
                error = nil
                self.status = "Введите код с телевизора"
            case .authorized, .sessionAlreadyActive:
                needsPin = false
                error = nil
                gamepadRetryCount = 0
                scheduleGamepadSessionWhenConnected()
            default:
                awaitingGamepadAfterConnect = false
                error = "Телевизор отклонил подключение (\(status))"
                self.status = "Ошибка подключения"
            }

        case .gamepadSessionConnectionInfoCastResponse(let deviceId, let status, let sessionId, let port, let serviceVersion, let aesKey, let ipV4List):
            gamepadRequestInFlight = false
            gamepadRetryTask?.cancel()
            gamepadRetryTask = nil

            guard status == .success else {
                session = nil
                error = "Канал пульта: \(status)"
                self.status = "Канал пульта недоступен — повторяем…"
                gamepadRetryCount += 1
                if gamepadRetryCount <= 5 { requestGamepadSession() }
                return
            }

            guard !sessionId.isEmpty, port > 0, !aesKey.isEmpty, !ipV4List.isEmpty else {
                session = nil
                error = "Телевизор вернул неполные параметры канала пульта"
                self.status = "Неполные параметры канала — повторяем…"
                gamepadRetryCount += 1
                if gamepadRetryCount <= 5 { requestGamepadSession() }
                return
            }

            activeDeviceID = deviceId
            awaitingGamepadAfterConnect = false
            gamepadRetryCount = 0
            reconnectRetryCount = 0
            error = nil
            notice = nil
            session = GamepadSession(
                sessionId: sessionId,
                port: port,
                serviceVersion: serviceVersion,
                aesKey: aesKey,
                ipv4: Array(ipV4List)
            )
            self.status = "Пульт подключён"

        default:
            break
        }
    }
}
