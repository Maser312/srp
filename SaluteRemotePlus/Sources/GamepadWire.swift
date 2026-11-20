import Foundation
import Network
import Security
import CommonCrypto

/// UDP-канал пульта Salute TV (`gamepad`, порт 6801).
/// Официальный протокол Салют:
/// UDP · AES-256-CBC/PKCS7 · AES(BE32(order) + Protobuf3) · IV = 16 байт UUID(sessionId) ·
/// обязательный пакет Introduction (field 21, apiVersion "1.7.2") + keepalive Ping (field 15) раз в 500 мс.
final class GamepadWire: ObservableObject {
    /// Официальный `Message.ControllerMode` протокола Salute TV (`SwitchControllerMode`, field 22).
    enum ControllerMode: UInt32, Equatable {
        case touchpad = 0          // REMOTE_TOUCHPAD_CONTROLS
        case airMousePointer = 1   // REMOTE_MOUSE_POINTER
        case mouseTrackpad = 2     // REMOTE_MOUSE_TRACKPAD
        case circleDPad = 3        // REMOTE_CIRCLE
        case keyboard = 4          // REMOTE_KEYBOARD
        case gamepad = 5           // GAMEPAD
        case retroGamepad = 6      // RETRO_GAMEPAD
    }

    @Published private(set) var ready = false
    @Published private(set) var handshakeConfirmed = false

    private static let clientName = "SaluteRemotePlus"
    private static let gamepadApiVersion = "1.7.2"

    private let queue = DispatchQueue(label: "SaluteRemotePlus.GamepadWire")
    private var connection: NWConnection?
    private var session: GamepadSession?
    private var desiredControllerMode: ControllerMode = .circleDPad
    private var key: Data?
    private var staticIV: Data?

    private enum OutboundPayload {
        case introduction(sessionId: String)
        case button(code: UInt32, pressed: Bool)
        case keyboardSignal(keyCode: Int32, pressed: Bool)
        case keyboardSymbols(text: String)
        case launchApp(signal: UInt32, packageName: String)
    }

    private struct PendingEvent {
        let payload: OutboundPayload
        let delayAfter: TimeInterval
    }

    private var hosts: [String] = []
    private var hostIndex = 0
    private var pending: [PendingEvent] = []
    private var sendInFlight = false
    private var delayWorkItem: DispatchWorkItem?
    private var pingTimer: DispatchSourceTimer?
    private var introRetryWorkItem: DispatchWorkItem?
    private var introTimeoutWorkItem: DispatchWorkItem?
    private var introAcked = false
    private var order: UInt32 = 0
    private var lastServerOrder: Int32 = -1
    private var generation = 0
    private var transportReady = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 2

    /// Вызывается на main-потоке, если локальные попытки переподключения исчерпаны.
    var onReconnectNeeded: (() -> Void)?

    func prepare(session: GamepadSession) {
        queue.async {
            if let current = self.session,
               current.sessionId == session.sessionId,
               current.port == session.port,
               current.serviceVersion == session.serviceVersion,
               current.aesKey == session.aesKey,
               current.ipv4 == session.ipv4,
               self.transportReady,
               self.connection != nil,
               self.key != nil {
                self.startPingTimerLocked(generation: self.generation)
                return
            }

            self.reconnectAttempt = 0
            self.teardownLocked(preservePending: false)
            self.session = session
            self.restartLocked(preservePending: false)
        }
    }

    func keyDown(_ code: Int32) {
        guard code >= 0 else { return }
        let uCode = UInt32(code)
        queue.async {
            self.pending.append(PendingEvent(payload: .button(code: uCode, pressed: true), delayAfter: 0.025))
            self.wakeIfDisconnectedLocked()
            self.flushIfReady()
        }
    }

    func keyUp(_ code: Int32) {
        guard code >= 0 else { return }
        let uCode = UInt32(code)
        queue.async {
            self.pending.append(PendingEvent(payload: .button(code: uCode, pressed: false), delayAfter: 0.015))
            self.wakeIfDisconnectedLocked()
            self.flushIfReady()
        }
    }

    func press(_ code: Int32) {
        guard code >= 0 else { return }
        let uCode = UInt32(code)
        queue.async {
            self.pending.append(PendingEvent(payload: .button(code: uCode, pressed: true), delayAfter: 0.035))
            self.pending.append(PendingEvent(payload: .button(code: uCode, pressed: false), delayAfter: 0.015))
            self.wakeIfDisconnectedLocked()
            self.flushIfReady()
        }
    }

    func longPress(_ code: Int32, duration: TimeInterval = 1.1) {
        guard code >= 0 else { return }
        let uCode = UInt32(code)
        queue.async {
            self.pending.append(PendingEvent(payload: .button(code: uCode, pressed: true), delayAfter: max(0.6, duration)))
            self.pending.append(PendingEvent(payload: .button(code: uCode, pressed: false), delayAfter: 0.02))
            self.wakeIfDisconnectedLocked()
            self.flushIfReady()
        }
    }

    /// Отправляет клавишу клавиатуры (`KeyboardSignal`, Linux input-event code: Backspace=14, Enter=28).
    func sendKeyboardKey(_ keyCode: Int32) {
        queue.async {
            self.pending.append(PendingEvent(payload: .keyboardSignal(keyCode: keyCode, pressed: true), delayAfter: 0.03))
            self.pending.append(PendingEvent(payload: .keyboardSignal(keyCode: keyCode, pressed: false), delayAfter: 0.02))
            self.wakeIfDisconnectedLocked()
            self.flushIfReady()
        }
    }

    /// Отправляет произвольную UTF-8 строку (русский, английский, цифры, символы) через `KeyboardSymbols`.
    func typeSymbols(_ text: String) {
        guard !text.isEmpty else { return }
        queue.async {
            self.pending.append(PendingEvent(payload: .keyboardSymbols(text: text), delayAfter: 0.04))
            self.wakeIfDisconnectedLocked()
            self.flushIfReady()
        }
    }

    func launchApp(packageName: String, signal: UInt32 = 1) {
        guard !packageName.isEmpty else { return }
        queue.async {
            self.pending.append(PendingEvent(payload: .launchApp(signal: signal, packageName: packageName), delayAfter: 0.04))
            self.wakeIfDisconnectedLocked()
            self.flushIfReady()
        }
    }

    /// Переключает режим контроллера на ТВ (крестовина / жесты / трекпад / аэромышь),
    /// чтобы StarOS показывал или скрывал курсор мыши.
    func switchControllerMode(_ mode: ControllerMode) {
        queue.async {
            self.desiredControllerMode = mode
            self.wakeIfDisconnectedLocked()
            guard self.transportReady, self.connection != nil else { return }
            let msg = Self.encodeSwitchControllerMode(mode)
            self.sendImmediateDatagramLocked(protobuf: msg)
        }
    }

    /// Мгновенная отправка дельты курсора мыши (`MouseOffset`, field 4) без задержек очереди кнопок.
    func sendMouseOffset(dx: Float, dy: Float) {
        guard dx.isFinite, dy.isFinite, (dx != 0 || dy != 0) else { return }
        queue.async {
            guard self.transportReady, self.connection != nil else { return }
            let msg = Self.encodeMouseOffset(dx: dx, dy: dy)
            self.sendImmediateDatagramLocked(protobuf: msg)
        }
    }

    /// Вертикальная прокрутка (`MouseVerticalScroll`, field 6).
    func sendMouseVerticalScroll(_ offset: Float) {
        guard offset.isFinite, offset != 0 else { return }
        queue.async {
            guard self.transportReady, self.connection != nil else { return }
            let msg = Self.encodeMouseVerticalScroll(offset)
            self.sendImmediateDatagramLocked(protobuf: msg)
        }
    }

    /// Горизонтальная прокрутка (`MouseHorizontalScroll`, field 7).
    func sendMouseHorizontalScroll(_ offset: Float) {
        guard offset.isFinite, offset != 0 else { return }
        queue.async {
            guard self.transportReady, self.connection != nil else { return }
            let msg = Self.encodeMouseHorizontalScroll(offset)
            self.sendImmediateDatagramLocked(protobuf: msg)
        }
    }

    func stop() {
        queue.async {
            self.session = nil
            self.reconnectAttempt = 0
            self.teardownLocked(preservePending: false)
        }
    }

    private func wakeIfDisconnectedLocked() {
        guard !transportReady,
              connection == nil,
              reconnectWorkItem == nil,
              session != nil else { return }
        reconnectAttempt = 0
        restartLocked(preservePending: true)
    }

    private func stopPingTimerLocked() {
        pingTimer?.setEventHandler {}
        pingTimer?.cancel()
        pingTimer = nil
    }

    private func teardownLocked(preservePending: Bool) {
        generation += 1
        stopPingTimerLocked()
        introRetryWorkItem?.cancel()
        introRetryWorkItem = nil
        introTimeoutWorkItem?.cancel()
        introTimeoutWorkItem = nil
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        delayWorkItem?.cancel()
        delayWorkItem = nil
        connection?.cancel()
        connection = nil
        transportReady = false
        introAcked = false
        setReady(false)
        setHandshakeConfirmed(false)
        sendInFlight = false
        if !preservePending {
            pending.removeAll()
        }
        hosts.removeAll()
        hostIndex = 0
    }

    private func restartLocked(preservePending: Bool) {
        teardownLocked(preservePending: preservePending)
        guard let session else { return }
        key = Self.deriveKey(session.aesKey)
        guard key != nil else { return }

        staticIV = Self.deriveUUIDIV(session.sessionId)
        guard staticIV != nil else { return }

        hosts = Array(session.ipv4)
        hostIndex = 0
        order = 0
        lastServerOrder = -1
        openNext()
    }

    private func setReady(_ value: Bool) {
        transportReady = value
        DispatchQueue.main.async {
            if self.ready != value { self.ready = value }
        }
    }

    private func setHandshakeConfirmed(_ value: Bool) {
        DispatchQueue.main.async {
            if self.handshakeConfirmed != value { self.handshakeConfirmed = value }
        }
    }

    private func openNext() {
        guard let session,
              session.port > 0,
              session.port <= UInt(UInt16.max),
              let port = NWEndpoint.Port(rawValue: UInt16(session.port)),
              hostIndex < hosts.count else {
            setReady(false)
            scheduleReconnectOrNotifyLocked()
            return
        }

        let host = hosts[hostIndex]
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: port,
            using: .udp
        )
        connection = conn
        generation += 1
        let currentGeneration = generation
        var isReady = false

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self else { return }
            self.queue.async {
                guard currentGeneration == self.generation, self.connection === conn else { return }
                switch state {
                case .ready:
                    isReady = true
                    self.reconnectAttempt = 0
                    self.setReady(true)
                    if let conn { self.receiveLoop(conn, generation: currentGeneration) }
                    self.sendIntroductionLocked(sessionId: session.sessionId, generation: currentGeneration)
                    self.startPingTimerLocked(generation: currentGeneration)
                    self.flushIfReady()
                case .failed:
                    self.advance()
                default:
                    break
                }
            }
        }
        conn.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, currentGeneration == self.generation, !isReady else { return }
            self.advance()
        }
    }

    private func advance() {
        stopPingTimerLocked()
        introRetryWorkItem?.cancel()
        introRetryWorkItem = nil
        introTimeoutWorkItem?.cancel()
        introTimeoutWorkItem = nil
        connection?.cancel()
        connection = nil
        setReady(false)
        setHandshakeConfirmed(false)
        sendInFlight = false
        hostIndex += 1
        openNext()
    }

    private func handleDisconnectLocked(requeue item: PendingEvent? = nil) {
        generation += 1
        stopPingTimerLocked()
        introRetryWorkItem?.cancel()
        introRetryWorkItem = nil
        introTimeoutWorkItem?.cancel()
        introTimeoutWorkItem = nil
        delayWorkItem?.cancel()
        delayWorkItem = nil
        connection?.cancel()
        connection = nil
        setReady(false)
        setHandshakeConfirmed(false)
        sendInFlight = false

        if let item {
            pending.insert(item, at: 0)
            if pending.count > 40 {
                pending.removeLast(pending.count - 40)
            }
        }

        guard session != nil else { return }

        if hostIndex + 1 < hosts.count {
            hostIndex += 1
            openNext()
        } else {
            scheduleReconnectOrNotifyLocked()
        }
    }

    private func scheduleReconnectOrNotifyLocked() {
        guard session != nil else { return }

        if reconnectAttempt < maxReconnectAttempts {
            reconnectAttempt += 1
            let delay = Double(reconnectAttempt) * 0.8

            reconnectWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self,
                      self.session != nil,
                      !self.transportReady,
                      self.connection == nil else { return }
                self.reconnectWorkItem = nil
                self.restartLocked(preservePending: true)
            }
            reconnectWorkItem = work
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            pending.removeAll()
            let callback = onReconnectNeeded
            DispatchQueue.main.async { callback?() }
        }
    }

    // MARK: - Handshake (Introduction) & Keepalive (Ping 500ms)

    private func sendIntroductionLocked(sessionId: String, generation expectedGen: Int) {
        guard transportReady, expectedGen == generation else { return }
        let msg = Self.encodeIntroduction(
            sessionId: sessionId,
            gamepadName: Self.clientName,
            apiVersion: Self.gamepadApiVersion
        )
        sendImmediateDatagramLocked(protobuf: msg)

        // Если UDP-пакет Introduction потерялся и ТВ не ответил за 400 мс — повторяем один раз.
        introRetryWorkItem?.cancel()
        let retry = DispatchWorkItem { [weak self] in
            guard let self,
                  expectedGen == self.generation,
                  self.transportReady,
                  !self.introAcked,
                  let sid = self.session?.sessionId else { return }
            let retryMsg = Self.encodeIntroduction(
                sessionId: sid,
                gamepadName: Self.clientName,
                apiVersion: Self.gamepadApiVersion
            )
            self.sendImmediateDatagramLocked(protobuf: retryMsg)
        }
        introRetryWorkItem = retry
        queue.asyncAfter(deadline: .now() + 0.4, execute: retry)

        // Если ТВ не подтвердил сессию за 1.8 с — sessionId устарел, запрашиваем новую сессию.
        introTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self,
                  expectedGen == self.generation,
                  self.transportReady,
                  !self.introAcked,
                  self.session != nil else { return }
            self.teardownLocked(preservePending: false)
            let callback = self.onReconnectNeeded
            DispatchQueue.main.async { callback?() }
        }
        introTimeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + 1.8, execute: timeout)
    }

    private func startPingTimerLocked(generation expectedGen: Int) {
        stopPingTimerLocked()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self,
                  expectedGen == self.generation,
                  self.transportReady,
                  self.connection != nil else { return }
            let nowMs = UInt64(Date().timeIntervalSince1970 * 1000.0)
            let ping = Self.encodePing(timeMs: nowMs)
            self.sendImmediateDatagramLocked(protobuf: ping)
        }
        pingTimer = timer
        timer.resume()
    }

    private func buildPacketLocked(protobuf: Data) -> Data? {
        guard let key, let iv = staticIV else { return nil }
        order &+= 1
        let plaintext = Data(Self.be32(order)) + protobuf
        return Self.aesCBCCrypt(plaintext, key: key, iv: iv, operation: CCOperation(kCCEncrypt))
    }

    private func sendImmediateDatagramLocked(protobuf: Data) {
        guard transportReady, let connection else { return }
        guard let packet = buildPacketLocked(protobuf: protobuf) else { return }
        connection.send(content: packet, completion: .contentProcessed { _ in })
    }

    // MARK: - Receive & Decrypt TV Responses (`Message.Device`)

    private func receiveLoop(_ conn: NWConnection, generation: Int) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self else { return }
            self.queue.async {
                guard generation == self.generation, self.connection === conn else { return }
                if let data, !data.isEmpty {
                    self.handleIncomingDatagramLocked(data)
                }
                if error != nil {
                    self.handleDisconnectLocked()
                    return
                }
                self.receiveLoop(conn, generation: generation)
            }
        }
    }

    private func handleIncomingDatagramLocked(_ data: Data) {
        guard let key, let iv = staticIV,
              let plain = Self.aesCBCDecrypt(data, key: key, iv: iv),
              plain.count >= 4 else { return }

        let tvOrder = Int32(bitPattern:
            (UInt32(plain[0]) << 24) |
            (UInt32(plain[1]) << 16) |
            (UInt32(plain[2]) << 8) |
            UInt32(plain[3])
        )
        if tvOrder > lastServerOrder {
            lastServerOrder = tvOrder
        }
        let body = plain.subdata(in: 4..<plain.count)
        let fieldNum = Self.firstProtobufFieldNumber(body)
        // Поле 16 в Message.Device = Connection (подтверждение Introduction), поле 15 = Pong.
        if fieldNum == 16 || !introAcked {
            let wasAcked = introAcked
            introAcked = true
            introRetryWorkItem?.cancel()
            introRetryWorkItem = nil
            introTimeoutWorkItem?.cancel()
            introTimeoutWorkItem = nil
            setHandshakeConfirmed(true)
            if !wasAcked && desiredControllerMode != .circleDPad {
                let modeMsg = Self.encodeSwitchControllerMode(desiredControllerMode)
                sendImmediateDatagramLocked(protobuf: modeMsg)
            }
        }
    }

    private static func firstProtobufFieldNumber(_ data: Data) -> UInt64? {
        guard !data.isEmpty else { return nil }
        var tag: UInt64 = 0
        var shift: UInt64 = 0
        for byte in data {
            tag |= UInt64(byte & 0x7f) << shift
            if (byte & 0x80) == 0 {
                return tag >> 3
            }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    // MARK: - Outbound Command Queue

    private func flushIfReady() {
        guard transportReady, !sendInFlight, !pending.isEmpty,
              let connection else { return }

        let item = pending.removeFirst()
        let message = Self.encodePayload(item.payload)

        guard let packet = buildPacketLocked(protobuf: message) else {
            pending.removeAll()
            return
        }

        sendInFlight = true
        let currentGeneration = generation
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.queue.async {
                guard currentGeneration == self.generation else { return }
                if error != nil {
                    self.sendInFlight = false
                    self.handleDisconnectLocked(requeue: item)
                } else if item.delayAfter > 0 {
                    self.delayWorkItem?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, currentGeneration == self.generation else { return }
                        self.delayWorkItem = nil
                        self.sendInFlight = false
                        self.flushIfReady()
                    }
                    self.delayWorkItem = work
                    self.queue.asyncAfter(deadline: .now() + item.delayAfter, execute: work)
                } else {
                    self.sendInFlight = false
                    self.flushIfReady()
                }
            }
        })
    }

    // MARK: - Protobuf3 Encoders (`ru.sberdevices.gamepad.proto.Message.Gamepad`)

    private static func encodePayload(_ payload: OutboundPayload) -> Data {
        switch payload {
        case .introduction(let sessionId):
            return encodeIntroduction(sessionId: sessionId, gamepadName: clientName, apiVersion: gamepadApiVersion)
        case .button(let code, let pressed):
            return encodeButton(code: code, pressed: pressed)
        case .keyboardSignal(let keyCode, let pressed):
            return encodeKeyboardSignal(keyCode: keyCode, pressed: pressed)
        case .keyboardSymbols(let text):
            return encodeKeyboardSymbols(text: text)
        case .launchApp(let signal, let packageName):
            return encodeLaunchApp(signal: signal, packageName: packageName)
        }
    }

    /// `Message.Gamepad { button = 1 (code = 1 uint32, pressed = 2 bool) }` (proto3).
    private static func encodeButton(code: UInt32, pressed: Bool) -> Data {
        var inner = Data()
        if code != 0 {
            inner.append(0x08)
            inner.append(contentsOf: varint(UInt64(code)))
        }
        if pressed {
            inner.append(contentsOf: [0x10, 0x01])
        }
        return lengthDelimitedField(1, inner)
    }

    /// `Message.Gamepad { introduction = 21 { sessionId = 1, gamepadName = 2, apiVersion = 3 } }`.
    private static func encodeIntroduction(sessionId: String, gamepadName: String, apiVersion: String) -> Data {
        var inner = Data()
        if !sessionId.isEmpty { inner.append(stringField(1, sessionId)) }
        if !gamepadName.isEmpty { inner.append(stringField(2, gamepadName)) }
        if !apiVersion.isEmpty { inner.append(stringField(3, apiVersion)) }
        return lengthDelimitedField(21, inner)
    }

    /// `Message.Gamepad { ping = 15 { time = 1 uint64 } }`.
    private static func encodePing(timeMs: UInt64) -> Data {
        var inner = Data()
        if timeMs != 0 {
            inner.append(0x08)
            inner.append(contentsOf: varint(timeMs))
        }
        return lengthDelimitedField(15, inner)
    }

    /// `Message.Gamepad { keyboardSignal = 5 { keyCode = 1 int32, pressed = 2 bool } }`.
    private static func encodeKeyboardSignal(keyCode: Int32, pressed: Bool) -> Data {
        var inner = Data()
        if keyCode != 0 {
            inner.append(0x08)
            inner.append(contentsOf: varint(UInt64(bitPattern: Int64(keyCode))))
        }
        if pressed {
            inner.append(contentsOf: [0x10, 0x01])
        }
        return lengthDelimitedField(5, inner)
    }

    /// `Message.Gamepad { keyboardSymbols = 8 { text = 1 string } }`.
    private static func encodeKeyboardSymbols(text: String) -> Data {
        var inner = Data()
        if !text.isEmpty {
            inner.append(stringField(1, text))
        }
        return lengthDelimitedField(8, inner)
    }

    /// `Message.Gamepad { launchApp = 17 { signal = 1 uint32, packageName = 2 string } }`.
    private static func encodeLaunchApp(signal: UInt32, packageName: String) -> Data {
        var inner = Data()
        if signal != 0 {
            inner.append(0x08)
            inner.append(contentsOf: varint(UInt64(signal)))
        }
        if !packageName.isEmpty {
            inner.append(stringField(2, packageName))
        }
        return lengthDelimitedField(17, inner)
    }

    /// `Message.Gamepad { mouseOffset = 4 { dX = 1 float, dY = 2 float } }`.
    private static func encodeMouseOffset(dx: Float, dy: Float) -> Data {
        var inner = Data()
        if dx != 0 { inner.append(floatField(1, dx)) }
        if dy != 0 { inner.append(floatField(2, dy)) }
        return lengthDelimitedField(4, inner)
    }

    /// `Message.Gamepad { mouseVerticalScroll = 6 { offset = 1 float } }`.
    private static func encodeMouseVerticalScroll(_ offset: Float) -> Data {
        var inner = Data()
        if offset != 0 { inner.append(floatField(1, offset)) }
        return lengthDelimitedField(6, inner)
    }

    /// `Message.Gamepad { mouseHorizontalScroll = 7 { offset = 1 float } }`.
    private static func encodeMouseHorizontalScroll(_ offset: Float) -> Data {
        var inner = Data()
        if offset != 0 { inner.append(floatField(1, offset)) }
        return lengthDelimitedField(7, inner)
    }

    /// `Message.Gamepad { switchControllerMode = 22 { controllerMode = 1 enum } }`.
    private static func encodeSwitchControllerMode(_ mode: ControllerMode) -> Data {
        var inner = Data()
        if mode.rawValue != 0 {
            inner.append(0x08)
            inner.append(contentsOf: varint(UInt64(mode.rawValue)))
        }
        return lengthDelimitedField(22, inner)
    }

    private static func floatField(_ number: UInt64, _ value: Float) -> Data {
        var data = Data(varint((number << 3) | 5))
        var le = value.bitPattern.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        return data
    }

    private static func stringField(_ number: UInt64, _ value: String) -> Data {
        lengthDelimitedField(number, Data(value.utf8))
    }

    private static func lengthDelimitedField(_ number: UInt64, _ bytes: Data) -> Data {
        var data = Data(varint((number << 3) | 2))
        data.append(contentsOf: varint(UInt64(bytes.count)))
        data.append(bytes)
        return data
    }

    private static func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var output: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            output.append(byte)
        } while value != 0
        return output
    }

    private static func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]
    }

    // MARK: - Key / IV / Crypto

    private static func deriveUUIDIV(_ sessionId: String) -> Data? {
        guard let uuid = UUID(uuidString: sessionId) else { return nil }
        var raw = uuid.uuid
        let full = withUnsafeBytes(of: &raw) { Data($0) }
        return full.count == kCCBlockSizeAES128 ? full : nil
    }

    private static func decodeBase64Flexible(_ string: String) -> Data? {
        var cleaned = string
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !cleaned.isEmpty else { return nil }
        let rem = cleaned.count % 4
        if rem != 0 {
            cleaned.append(String(repeating: "=", count: 4 - rem))
        }
        return Data(base64Encoded: cleaned)
    }

    private static func decodeHexFlexible(_ string: String) -> Data? {
        var cleaned = string
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        if cleaned.hasPrefix("0x") || cleaned.hasPrefix("0X") {
            cleaned.removeFirst(2)
        }
        cleaned = cleaned
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
        guard !cleaned.isEmpty, cleaned.count % 2 == 0 else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private static func deriveKey(_ string: String) -> Data? {
        let validLengths = [16, 24, 32]
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = decodeBase64Flexible(trimmed) {
            if validLengths.contains(data.count) { return data }
            if let inner = String(data: data, encoding: .utf8),
               let hexData = decodeHexFlexible(inner),
               validLengths.contains(hexData.count) {
                return hexData
            }
        }
        if let hexData = decodeHexFlexible(trimmed), validLengths.contains(hexData.count) {
            return hexData
        }
        let utf8Data = Data(trimmed.utf8)
        return validLengths.contains(utf8Data.count) ? utf8Data : nil
    }

    private static func aesCBCDecrypt(_ data: Data, key: Data, iv: Data) -> Data? {
        aesCBCCrypt(data, key: key, iv: iv, operation: CCOperation(kCCDecrypt))
    }

    private static func aesCBCCrypt(_ data: Data, key: Data, iv: Data, operation: CCOperation) -> Data? {
        guard iv.count == kCCBlockSizeAES128 else { return nil }
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let capacity = output.count
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            outputBytes.baseAddress, capacity, &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.removeSubrange(moved..<output.count)
        return output
    }
}
