import Foundation
import Network
import Security

/// Нативный клиент ADB по Wi-Fi (TCP порт 5555) для YaOS (Яндекс ТВ) и Android TV.
/// Реализует бинарный протокол ADB (`CNXN`, `AUTH` RSA-2048, `OPEN`, `OKAY`, `WRTE`, `CLSE`)
/// без внешних библиотек — работает сразу после включения отладки по сети на ТВ.
@MainActor
final class ADBTVRemoteClient: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isReady = false
    @Published private(set) var waitingForTVApproval = false
    @Published private(set) var statusText = "Ожидание подключения ADB"
    @Published private(set) var errorText: String?

    private enum Command: UInt32 {
        case cnxn = 0x4E584E43 // "CNXN"
        case auth = 0x48545541 // "AUTH"
        case open = 0x4E45504F // "OPEN"
        case okay = 0x59414B4F // "OKAY"
        case clse = 0x45534C43 // "CLSE"
        case wrte = 0x45545257 // "WRTE"
    }

    private let authToken: UInt32 = 1
    private let authSignature: UInt32 = 2
    private let authRSAPublicKey: UInt32 = 3

    private var connection: NWConnection?
    private var rxBuffer = Data()
    private var privateKey: SecKey?
    private var authSignatureSent = false
    private var nextLocalId: UInt32 = 1
    private var holdStartAt: [RemoteCommand: Date] = [:]

    private let networkQueue = DispatchQueue(label: "com.andrey.saluteremoteplus.adb.net", qos: .userInitiated)

    func connect(host: String, port: Int = 5555) {
        disconnect(silent: true)
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPort = port > 0 ? port : 5555

        guard !cleanHost.isEmpty, let nwPort = NWEndpoint.Port(rawValue: UInt16(resolvedPort)) else {
            errorText = "Укажите корректный IP-адрес ТВ"
            return
        }

        if privateKey == nil {
            privateKey = ATVClientIdentityStore.loadOrCreatePrivateKey()
        }

        statusText = "Подключение ADB к \(cleanHost):\(resolvedPort)…"
        errorText = nil
        authSignatureSent = false
        waitingForTVApproval = false

        let conn = NWConnection(host: NWEndpoint.Host(cleanHost), port: nwPort, using: .tcp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.connection === conn else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.statusText = "Авторизация ADB…"
                    self.sendCNXN()
                    self.receiveLoop(conn)
                case .failed(let err):
                    self.isConnected = false
                    self.isReady = false
                    self.waitingForTVApproval = false
                    self.errorText = "Не удалось подключиться по ADB (\(cleanHost):\(resolvedPort)): \(err.localizedDescription)"
                    self.statusText = "Ошибка ADB"
                case .waiting(let err):
                    self.statusText = "Ожидание ТВ (\(err.localizedDescription))…"
                default:
                    break
                }
            }
        }
        conn.start(queue: networkQueue)
    }

    func disconnect(silent: Bool = false) {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        rxBuffer.removeAll(keepingCapacity: false)
        holdStartAt.removeAll()
        isConnected = false
        isReady = false
        waitingForTVApproval = false
        if !silent {
            statusText = "Отключено"
        }
    }

    // MARK: - Команды пульта по ADB

    func sendCommand(_ command: RemoteCommand) {
        runShell("input keyevent \(command.androidKeyCode)")
    }

    func sendCommandDown(_ command: RemoteCommand) {
        holdStartAt[command] = Date()
    }

    func sendCommandUp(_ command: RemoteCommand) {
        let start = holdStartAt.removeValue(forKey: command)
        let duration = start.map { Date().timeIntervalSince($0) } ?? 0
        if duration >= 0.45 {
            runShell("input keyevent --longpress \(command.androidKeyCode)")
        } else {
            runShell("input keyevent \(command.androidKeyCode)")
        }
    }

    func sendKeyCode(_ keyCode: Int) {
        runShell("input keyevent \(keyCode)")
    }

    func sendText(_ text: String, submit: Bool) {
        guard !text.isEmpty else { return }
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: " ", with: "%s")
            .replacingOccurrences(of: "&", with: "\\&")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        let cmd = submit ? "input text \"\(escaped)\" && input keyevent 66" : "input text \"\(escaped)\""
        runShell(cmd)
    }

    func openDeepLink(_ link: String, packageName: String? = nil) {
        if link == "android.settings.SETTINGS" {
            runShell("am start -a android.settings.SETTINGS")
            return
        }
        let safeLink = link.replacingOccurrences(of: "\"", with: "")
        if let pkg = packageName, !pkg.isEmpty {
            runShell("monkey -p \(pkg) -c android.intent.category.LEANBACK_LAUNCHER 1 || am start -a android.intent.action.VIEW -d \"\(safeLink)\"")
        } else {
            runShell("am start -a android.intent.action.VIEW -d \"\(safeLink)\"")
        }
    }

    func runShell(_ command: String) {
        guard isReady, connection != nil else { return }
        let localId = nextLocalId
        nextLocalId &+= 1
        if nextLocalId == 0 { nextLocalId = 1 }
        var payload = Data("shell:\(command)".utf8)
        payload.append(0x00)
        sendPacket(command: .open, arg0: localId, arg1: 0, payload: payload)
    }

    // MARK: - ADB Handshake & Packet Framing

    private func sendCNXN() {
        var payload = Data("host::features=shell_v2,cmd".utf8)
        payload.append(0x00)
        sendPacket(command: .cnxn, arg0: 0x01000000, arg1: 262_144, payload: payload)
    }

    private func sendPacket(command: Command, arg0: UInt32, arg1: UInt32, payload: Data) {
        guard let connection else { return }
        var crc: UInt32 = 0
        for byte in payload {
            crc &+= UInt32(byte)
        }
        let magic = command.rawValue ^ 0xFFFF_FFFF

        var packet = Data(capacity: 24 + payload.count)
        appendLE(&packet, command.rawValue)
        appendLE(&packet, arg0)
        appendLE(&packet, arg1)
        appendLE(&packet, UInt32(payload.count))
        appendLE(&packet, crc)
        appendLE(&packet, magic)
        packet.append(payload)

        connection.send(content: packet, completion: .contentProcessed { _ in })
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self, self.connection === conn else { return }
                if let data, !data.isEmpty {
                    self.rxBuffer.append(data)
                    self.drainPackets()
                }
                if error != nil || isComplete {
                    self.isConnected = false
                    self.isReady = false
                    self.waitingForTVApproval = false
                    if self.errorText == nil {
                        self.statusText = "Соединение ADB закрыто"
                    }
                    return
                }
                self.receiveLoop(conn)
            }
        }
    }

    private func drainPackets() {
        while rxBuffer.count >= 24 {
            let cmd = readLE(rxBuffer, offset: 0)
            let arg0 = readLE(rxBuffer, offset: 4)
            let arg1 = readLE(rxBuffer, offset: 8)
            let dataLen = Int(readLE(rxBuffer, offset: 12))
            let total = 24 + dataLen
            guard rxBuffer.count >= total else { break }

            let base = rxBuffer.startIndex
            let payload = dataLen > 0 ? Data(rxBuffer[(base + 24)..<(base + total)]) : Data()
            rxBuffer = Data(rxBuffer.dropFirst(total))
            handlePacket(cmd: cmd, arg0: arg0, arg1: arg1, payload: payload)
        }
    }

    private func handlePacket(cmd: UInt32, arg0: UInt32, arg1: UInt32, payload: Data) {
        switch cmd {
        case Command.cnxn.rawValue:
            isReady = true
            isConnected = true
            waitingForTVApproval = false
            errorText = nil
            statusText = "Пульт готов (ADB)"

        case Command.auth.rawValue where arg0 == authToken:
            guard let privateKey else {
                errorText = "Нет RSA-ключа для авторизации ADB"
                return
            }
            if !authSignatureSent {
                authSignatureSent = true
                if let sig = signADBToken(payload, with: privateKey) {
                    sendPacket(command: .auth, arg0: authSignature, arg1: 0, payload: sig)
                } else {
                    sendADBPublicKey(privateKey: privateKey)
                }
            } else {
                sendADBPublicKey(privateKey: privateKey)
            }

        case Command.wrte.rawValue:
            // Подтверждаем приём вывода shell-команды
            sendPacket(command: .okay, arg0: arg1, arg1: arg0, payload: Data())

        case Command.clse.rawValue:
            sendPacket(command: .clse, arg0: arg1, arg1: arg0, payload: Data())

        default:
            break
        }
    }

    private func signADBToken(_ token: Data, with privateKey: SecKey) -> Data? {
        var err: Unmanaged<CFError>?
        return SecKeyCreateSignature(
            privateKey,
            .rsaSignatureDigestPKCS1v15SHA1,
            token as CFData,
            &err
        ) as Data?
    }

    private func sendADBPublicKey(privateKey: SecKey) {
        guard let pubKey = SecKeyCopyPublicKey(privateKey),
              let pubDER = SecKeyCopyExternalRepresentation(pubKey, nil) as Data?,
              let components = ATVClientIdentityStore.parsePKCS1RSAPublicKey(pubDER),
              let adbPubBlob = buildADBRSAPublicKeyBlob(modulus: components.modulus, exponent: components.exponent) else {
            errorText = "Не удалось сформировать публичный ключ ADB"
            return
        }

        let b64 = adbPubBlob.base64EncodedString()
        var payload = Data("\(b64) salute-remote-plus@iphone".utf8)
        payload.append(0x00)

        waitingForTVApproval = true
        statusText = "Подтвердите отладку на экране телевизора"
        sendPacket(command: .auth, arg0: authRSAPublicKey, arg1: 0, payload: payload)
    }

    /// Собирает 524-байтную структуру Android ADB `RSAPublicKey`:
    /// `uint32 len(64), uint32 n0inv, uint32 n[64], uint32 rr[64], uint32 exponent`.
    private func buildADBRSAPublicKeyBlob(modulus: Data, exponent: Data) -> Data? {
        guard modulus.count == 256 else { return nil }
        let modBytes = [UInt8](modulus)

        // n[0..63] — little-endian 32-битные слова
        var n = [UInt32](repeating: 0, count: 64)
        for i in 0..<64 {
            let base = 256 - (i + 1) * 4
            n[i] = (UInt32(modBytes[base]) << 24)
                | (UInt32(modBytes[base + 1]) << 16)
                | (UInt32(modBytes[base + 2]) << 8)
                | UInt32(modBytes[base + 3])
        }

        // n0inv = - (n[0]^-1 mod 2^32) mod 2^32 (метод Ньютона для нечётного n[0])
        let n0 = n[0]
        guard (n0 & 1) == 1 else { return nil }
        var inv: UInt32 = 1
        for _ in 0..<5 {
            inv = inv &* (2 &- n0 &* inv)
        }
        let n0inv = 0 &- inv

        // Вычисляем rr = R^2 mod N = 2^4096 mod N (65 слов для переноса)
        var rem = [UInt32](repeating: 0, count: 65)
        rem[0] = 1
        for _ in 0..<4096 {
            // rem = rem << 1
            var carry: UInt32 = 0
            for i in 0..<65 {
                let nextCarry = rem[i] >> 31
                rem[i] = (rem[i] << 1) | carry
                carry = nextCarry
            }
            // Если rem >= N, вычитаем N
            if isGreaterOrEqual(rem, n) {
                var borrow: UInt64 = 0
                for i in 0..<64 {
                    let a = UInt64(rem[i])
                    let b = UInt64(n[i]) + borrow
                    if a >= b {
                        rem[i] = UInt32(a - b)
                        borrow = 0
                    } else {
                        rem[i] = UInt32((1 << 32) + a - b)
                        borrow = 1
                    }
                }
                if borrow > 0 {
                    rem[64] &-= 1
                }
            }
        }

        // Exponent
        var expVal: UInt32 = 0
        for b in exponent {
            expVal = (expVal << 8) | UInt32(b)
        }

        var blob = Data(capacity: 524)
        appendLE(&blob, UInt32(64))
        appendLE(&blob, n0inv)
        for word in n { appendLE(&blob, word) }
        for i in 0..<64 { appendLE(&blob, rem[i]) }
        appendLE(&blob, expVal)
        return blob
    }

    private func isGreaterOrEqual(_ a: [UInt32], _ n: [UInt32]) -> Bool {
        if a[64] != 0 { return true }
        for i in stride(from: 63, through: 0, by: -1) {
            if a[i] != n[i] {
                return a[i] > n[i]
            }
        }
        return true
    }

    private func appendLE(_ data: inout Data, _ value: UInt32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private func readLE(_ data: Data, offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
    }
}
