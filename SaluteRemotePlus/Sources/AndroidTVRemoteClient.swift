import Foundation
import Network
import Security
import CryptoKit

// MARK: - Криптографическое удостоверение клиента (RSA-2048 + X.509 v3) в Keychain

struct RSAPublicComponents {
    let modulus: Data   // Без ведущего знакового 0x00
    let exponent: Data  // Без ведущего знакового 0x00
}

enum ATVClientIdentityStore {
    private static let keyTag = "com.andrey.saluteremoteplus.atv.clientkey.v1"
    private static let certLabel = "SaluteRemotePlus AndroidTV Client Cert"

    static func loadOrCreateIdentity() -> (identity: SecIdentity, publicComponents: RSAPublicComponents)? {
        guard let privateKey = loadOrCreatePrivateKey(),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let pubDER = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              let components = parsePKCS1RSAPublicKey(pubDER) else {
            return nil
        }

        if let existing = findStoredIdentity(matchingPublicKeyDER: pubDER) {
            return (existing, components)
        }

        guard let certDER = buildSelfSignedX509Certificate(privateKey: privateKey, publicKeyPKCS1DER: pubDER),
              let certificate = SecCertificateCreateWithData(nil, certDER as CFData) else {
            return nil
        }

        // Сохраняем сертификат в Keychain, чтобы iOS сопоставила его с приватным ключом в SecIdentity
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certLabel
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: certLabel,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            return nil
        }

        guard let identity = findStoredIdentity(matchingPublicKeyDER: pubDER) else {
            return nil
        }
        return (identity, components)
    }

    static func loadOrCreatePrivateKey() -> SecKey? {
        let tagData = keyTag.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let item {
            return (item as! SecKey)
        }

        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tagData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
        ]
        var error: Unmanaged<CFError>?
        return SecKeyCreateRandomKey(attrs as CFDictionary, &error)
    }

    private static func findStoredIdentity(matchingPublicKeyDER targetPubDER: Data) -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let identities = result as? [SecIdentity] else {
            return nil
        }
        for identity in identities {
            var cert: SecCertificate?
            if SecIdentityCopyCertificate(identity, &cert) == errSecSuccess,
               let cert,
               let key = SecCertificateCopyKey(cert),
               let pub = SecKeyCopyExternalRepresentation(key, nil) as Data?,
               pub == targetPubDER {
                return identity
            }
        }
        return nil
    }

    static func extractPublicComponents(from certificate: SecCertificate) -> RSAPublicComponents? {
        guard let key = SecCertificateCopyKey(certificate),
              let pubDER = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return nil
        }
        return parsePKCS1RSAPublicKey(pubDER)
    }

    /// Парсит DER `SEQUENCE { INTEGER modulus, INTEGER exponent }` (PKCS#1 RSAPublicKey).
    static func parsePKCS1RSAPublicKey(_ der: Data) -> RSAPublicComponents? {
        let bytes = [UInt8](der)
        var idx = 0
        guard readTag(0x30, from: bytes, at: &idx) != nil else { return nil }
        guard let modRaw = readTag(0x02, from: bytes, at: &idx),
              let expRaw = readTag(0x02, from: bytes, at: &idx) else {
            return nil
        }
        return RSAPublicComponents(
            modulus: stripLeadingZero(modRaw),
            exponent: stripLeadingZero(expRaw)
        )
    }

    private static func stripLeadingZero(_ data: Data) -> Data {
        var d = data
        while d.count > 1 && d.first == 0x00 {
            d.removeFirst()
        }
        return d
    }

    private static func readTag(_ expectedTag: UInt8, from bytes: [UInt8], at idx: inout Int) -> Data? {
        guard idx < bytes.count, bytes[idx] == expectedTag else { return nil }
        idx += 1
        guard idx < bytes.count else { return nil }
        var length = 0
        let firstLen = bytes[idx]
        idx += 1
        if (firstLen & 0x80) == 0 {
            length = Int(firstLen)
        } else {
            let count = Int(firstLen & 0x7F)
            guard count > 0, count <= 4, idx + count <= bytes.count else { return nil }
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[idx])
                idx += 1
            }
        }
        guard idx + length <= bytes.count else { return nil }
        let content = Data(bytes[idx..<(idx + length)])
        if expectedTag != 0x30 {
            idx += length
        }
        return content
    }

    // MARK: - Минимальный ASN.1 DER X.509 v3 сертификат

    private static func buildSelfSignedX509Certificate(privateKey: SecKey, publicKeyPKCS1DER: Data) -> Data? {
        // Version [0] EXPLICIT INTEGER 2 (X.509 v3)
        let version = asn1Wrap(tag: 0xA0, content: asn1Integer(Data([0x02])))
        // Serial number (8 случайных байт, положительный)
        var serialBytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, serialBytes.count, &serialBytes)
        serialBytes[0] &= 0x7F
        if serialBytes[0] == 0 { serialBytes[0] = 0x01 }
        let serial = asn1Integer(Data(serialBytes))

        // sha256WithRSAEncryption: 1.2.840.113549.1.1.11
        let sha256WithRSA = asn1Sequence(
            asn1OID([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]) +
            asn1Null()
        )

        // Issuer / Subject: CN=SaluteRemotePlus
        let cnAttr = asn1Sequence(
            asn1OID([0x55, 0x04, 0x03]) +
            asn1Wrap(tag: 0x0C, content: Data("SaluteRemotePlus".utf8))
        )
        let rdn = asn1Wrap(tag: 0x31, content: cnAttr)
        let name = asn1Sequence(rdn)

        // Validity: 2024-01-01 to 2044-01-01 (UTCTime)
        let notBefore = asn1Wrap(tag: 0x17, content: Data("240101000000Z".utf8))
        let notAfter = asn1Wrap(tag: 0x17, content: Data("440101000000Z".utf8))
        let validity = asn1Sequence(notBefore + notAfter)

        // SubjectPublicKeyInfo: rsaEncryption (1.2.840.113549.1.1.1) + BIT STRING
        let rsaAlg = asn1Sequence(
            asn1OID([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]) +
            asn1Null()
        )
        let spki = asn1Sequence(rsaAlg + asn1BitString(publicKeyPKCS1DER))

        let tbsCertificate = asn1Sequence(
            version + serial + sha256WithRSA + name + validity + name + spki
        )

        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbsCertificate as CFData,
            &signError
        ) as Data? else {
            return nil
        }

        return asn1Sequence(tbsCertificate + sha256WithRSA + asn1BitString(signature))
    }

    private static func asn1Wrap(tag: UInt8, content: Data) -> Data {
        var out = Data([tag])
        let len = content.count
        if len < 128 {
            out.append(UInt8(len))
        } else {
            var lenBytes: [UInt8] = []
            var rem = len
            while rem > 0 {
                lenBytes.insert(UInt8(rem & 0xFF), at: 0)
                rem >>= 8
            }
            out.append(UInt8(0x80 | lenBytes.count))
            out.append(contentsOf: lenBytes)
        }
        out.append(content)
        return out
    }

    private static func asn1Sequence(_ content: Data) -> Data {
        asn1Wrap(tag: 0x30, content: content)
    }

    private static func asn1Integer(_ raw: Data) -> Data {
        var d = raw
        if let first = d.first, (first & 0x80) != 0 {
            d.insert(0x00, at: 0)
        }
        return asn1Wrap(tag: 0x02, content: d)
    }

    private static func asn1OID(_ bytes: [UInt8]) -> Data {
        asn1Wrap(tag: 0x06, content: Data(bytes))
    }

    private static func asn1Null() -> Data {
        Data([0x05, 0x00])
    }

    private static func asn1BitString(_ content: Data) -> Data {
        var d = Data([0x00])
        d.append(content)
        return asn1Wrap(tag: 0x03, content: d)
    }
}

// MARK: - Минимальный Protobuf Wire Encoder / Decoder (Android TV Remote v2)

private enum ATVProto {
    static func encodeVarint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        while v >= 0x80 {
            out.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    static func varintField(_ fieldNumber: Int, _ value: Int) -> Data {
        var out = encodeVarint(UInt64((fieldNumber << 3) | 0))
        out.append(encodeVarint(UInt64(bitPattern: Int64(value))))
        return out
    }

    static func bytesField(_ fieldNumber: Int, _ payload: Data) -> Data {
        var out = encodeVarint(UInt64((fieldNumber << 3) | 2))
        out.append(encodeVarint(UInt64(payload.count)))
        out.append(payload)
        return out
    }

    static func stringField(_ fieldNumber: Int, _ text: String) -> Data {
        bytesField(fieldNumber, Data(text.utf8))
    }

    static func frameMessage(_ payload: Data) -> Data {
        var out = encodeVarint(UInt64(payload.count))
        out.append(payload)
        return out
    }

    /// Декодирует varint, возвращая (значение, 0-based смещение после varint) либо nil, если байт недостаточно.
    static func decodeVarint(from data: Data, at offset: Int) -> (UInt64, Int)? {
        let base = data.startIndex
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var i = offset
        while i < data.count {
            let byte = data[base + i]
            result |= UInt64(byte & 0x7F) << shift
            i += 1
            if (byte & 0x80) == 0 {
                return (result, i)
            }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    struct Field {
        let number: Int
        let wireType: Int
        let varint: UInt64
        let bytes: Data
    }

    static func parseFields(_ data: Data) -> [Field] {
        let base = data.startIndex
        var fields: [Field] = []
        var idx = 0
        while idx < data.count {
            guard let (tag, afterTag) = decodeVarint(from: data, at: idx) else { break }
            idx = afterTag
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x07)
            switch wireType {
            case 0: // Varint
                guard let (val, nextIdx) = decodeVarint(from: data, at: idx) else { return fields }
                fields.append(Field(number: fieldNumber, wireType: 0, varint: val, bytes: Data()))
                idx = nextIdx
            case 1: // 64-bit
                guard idx + 8 <= data.count else { return fields }
                idx += 8
            case 2: // Length-delimited
                guard let (len, afterLen) = decodeVarint(from: data, at: idx) else { return fields }
                let end = afterLen + Int(len)
                guard end <= data.count else { return fields }
                let slice = Data(data[(base + afterLen)..<(base + end)])
                fields.append(Field(number: fieldNumber, wireType: 2, varint: 0, bytes: slice))
                idx = end
            case 5: // 32-bit
                guard idx + 4 <= data.count else { return fields }
                idx += 4
            default:
                return fields
            }
        }
        return fields
    }
}

// MARK: - Клиент Android TV Remote Protocol v2 (TLS 6467 сопряжение + TLS 6466 пульт)

@MainActor
final class AndroidTVRemoteClient: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isReady = false
    @Published private(set) var needsPin = false
    @Published private(set) var statusText = "Ожидание подключения"
    @Published private(set) var errorText: String?
    @Published private(set) var currentForegroundApp: String?

    var onPairingSucceeded: (() -> Void)?

    private var activeHost: String = ""
    private var activeRemotePort: Int = 6466
    private var activePairingPort: Int = 6467

    private var pairingConnection: NWConnection?
    private var remoteConnection: NWConnection?
    private var rxPairingBuffer = Data()
    private var rxRemoteBuffer = Data()

    private var clientIdentity: SecIdentity?
    private var clientPublicComponents: RSAPublicComponents?
    private var serverPublicComponents: RSAPublicComponents?
    private var isAttemptingFallbackToPairing = false

    private let networkQueue = DispatchQueue(label: "com.andrey.saluteremoteplus.atv.net", qos: .userInitiated)

    func connect(host: String, remotePort: Int = 6466, pairingPort: Int = 6467, alreadyPaired: Bool) {
        disconnect(silent: true)
        activeHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        activeRemotePort = remotePort > 0 ? remotePort : 6466
        activePairingPort = pairingPort > 0 ? pairingPort : 6467
        errorText = nil
        needsPin = false
        isAttemptingFallbackToPairing = false

        guard !activeHost.isEmpty else {
            errorText = "Укажите IP-адрес телевизора"
            return
        }

        if clientIdentity == nil {
            guard let bundle = ATVClientIdentityStore.loadOrCreateIdentity() else {
                errorText = "Не удалось создать TLS-ключ для Android TV"
                return
            }
            clientIdentity = bundle.identity
            clientPublicComponents = bundle.publicComponents
        }

        if alreadyPaired {
            openRemoteConnection()
        } else {
            openPairingConnection()
        }
    }

    func disconnect(silent: Bool = false) {
        pairingConnection?.stateUpdateHandler = nil
        pairingConnection?.cancel()
        pairingConnection = nil

        remoteConnection?.stateUpdateHandler = nil
        remoteConnection?.cancel()
        remoteConnection = nil

        rxPairingBuffer.removeAll(keepingCapacity: false)
        rxRemoteBuffer.removeAll(keepingCapacity: false)
        serverPublicComponents = nil
        isConnected = false
        isReady = false
        needsPin = false
        currentForegroundApp = nil
        if !silent {
            statusText = "Отключено"
        }
    }

    func cancelPairing() {
        needsPin = false
        disconnect(silent: false)
    }

    // MARK: - Фаза 1: Сопряжение (порт 6467)

    private func openPairingConnection() {
        guard let identity = clientIdentity,
              let port = NWEndpoint.Port(rawValue: UInt16(activePairingPort)) else {
            errorText = "Неверный порт сопряжения Android TV"
            return
        }

        statusText = "Сопряжение с \(activeHost):\(activePairingPort)…"
        errorText = nil
        rxPairingBuffer.removeAll()
        serverPublicComponents = nil

        let tlsOptions = makeTLSOptions(identity: identity) { [weak self] serverCert in
            guard let components = ATVClientIdentityStore.extractPublicComponents(from: serverCert) else { return }
            Task { @MainActor [weak self] in
                self?.serverPublicComponents = components
            }
        }

        let params = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        let conn = NWConnection(host: NWEndpoint.Host(activeHost), port: port, using: params)
        pairingConnection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.pairingConnection === conn else { return }
                switch state {
                case .ready:
                    self.statusText = "Запрос кода сопряжения…"
                    self.sendPairingRequest()
                    self.receivePairingLoop(conn)
                case .failed(let err):
                    self.errorText = "Не удалось подключиться к сопряжению (\(self.activeHost):\(self.activePairingPort)): \(err.localizedDescription)"
                    self.statusText = "Ошибка сопряжения"
                    self.needsPin = false
                case .waiting(let err):
                    self.statusText = "Ожидание ТВ (\(err.localizedDescription))…"
                default:
                    break
                }
            }
        }
        conn.start(queue: networkQueue)
    }

    private func sendPairingRequest() {
        var req = Data()
        req.append(ATVProto.stringField(1, "com.andrey.saluteremoteplus"))
        req.append(ATVProto.stringField(2, "Salute Remote+"))

        var msg = Data()
        msg.append(ATVProto.varintField(1, 2))   // protocol_version = 2
        msg.append(ATVProto.varintField(2, 200)) // STATUS_OK
        msg.append(ATVProto.bytesField(10, req)) // pairing_request
        sendFramed(msg, over: pairingConnection)
    }

    private func sendPairingOptions() {
        var encoding = Data()
        encoding.append(ATVProto.varintField(1, 3)) // ENCODING_TYPE_HEXADECIMAL
        encoding.append(ATVProto.varintField(2, 6)) // symbol_length = 6

        var opt = Data()
        opt.append(ATVProto.bytesField(1, encoding)) // input_encodings
        opt.append(ATVProto.varintField(3, 1))       // preferred_role = ROLE_TYPE_INPUT

        var msg = Data()
        msg.append(ATVProto.varintField(1, 2))
        msg.append(ATVProto.varintField(2, 200))
        msg.append(ATVProto.bytesField(20, opt)) // pairing_option
        sendFramed(msg, over: pairingConnection)
    }

    private func sendPairingConfiguration() {
        var encoding = Data()
        encoding.append(ATVProto.varintField(1, 3)) // ENCODING_TYPE_HEXADECIMAL
        encoding.append(ATVProto.varintField(2, 6)) // symbol_length = 6

        var cfg = Data()
        cfg.append(ATVProto.bytesField(1, encoding))
        cfg.append(ATVProto.varintField(2, 1)) // client_role = ROLE_TYPE_INPUT

        var msg = Data()
        msg.append(ATVProto.varintField(1, 2))
        msg.append(ATVProto.varintField(2, 200))
        msg.append(ATVProto.bytesField(30, cfg)) // pairing_configuration
        sendFramed(msg, over: pairingConnection)
    }

    func submitPairingPin(_ rawPin: String) {
        let cleaned = rawPin
            .uppercased()
            .filter { $0.isHexDigit }

        guard cleaned.count == 6, let pinBytes = hexToBytes(cleaned), pinBytes.count == 3 else {
            errorText = "Введите 6 символов кода (0–9, A–F) с экрана ТВ"
            return
        }
        guard let clientPub = clientPublicComponents, let serverPub = serverPublicComponents else {
            errorText = "Потерян TLS-контекст. Начните сопряжение заново."
            return
        }

        // SHA-256(clientModulus + clientExponent + serverModulus + serverExponent + pinBytes[1...2])
        var hasher = SHA256()
        hasher.update(data: clientPub.modulus)
        hasher.update(data: clientPub.exponent)
        hasher.update(data: serverPub.modulus)
        hasher.update(data: serverPub.exponent)
        hasher.update(data: pinBytes.subdata(in: 1..<3))
        let digest = Data(hasher.finalize())

        guard digest.first == pinBytes.first else {
            errorText = "Код не совпадает. Проверьте символы на экране телевизора."
            return
        }

        errorText = nil
        statusText = "Подтверждение сопряжения…"

        let secret = ATVProto.bytesField(1, digest)
        var msg = Data()
        msg.append(ATVProto.varintField(1, 2))
        msg.append(ATVProto.varintField(2, 200))
        msg.append(ATVProto.bytesField(40, secret)) // pairing_secret
        sendFramed(msg, over: pairingConnection)
    }

    private func receivePairingLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self, self.pairingConnection === conn else { return }
                if let data, !data.isEmpty {
                    self.rxPairingBuffer.append(data)
                    self.drainFramedMessages(from: &self.rxPairingBuffer) { payload in
                        self.handlePairingMessage(payload)
                    }
                }
                if let error {
                    if self.needsPin {
                        self.errorText = "Соединение сопряжения закрыто: \(error.localizedDescription)"
                    }
                    return
                }
                if !isComplete {
                    self.receivePairingLoop(conn)
                }
            }
        }
    }

    private func handlePairingMessage(_ payload: Data) {
        let fields = ATVProto.parseFields(payload)
        let status = fields.first(where: { $0.number == 2 })?.varint ?? 200
        if status != 200 {
            errorText = "Телевизор отклонил сопряжение (код \(status)). Попробуйте ещё раз."
            needsPin = false
            return
        }

        if fields.contains(where: { $0.number == 11 }) {
            // pairing_request_ack -> отправляем pairing_option
            sendPairingOptions()
        } else if fields.contains(where: { $0.number == 20 }) {
            // pairing_option от ТВ -> отправляем pairing_configuration
            sendPairingConfiguration()
        } else if fields.contains(where: { $0.number == 31 }) {
            // pairing_configuration_ack -> ТВ показывает 6-символьный HEX PIN
            needsPin = true
            errorText = nil
            statusText = "Введите 6-значный код с экрана ТВ"
        } else if fields.contains(where: { $0.number == 41 }) {
            // pairing_secret_ack -> Сопряжение завершено!
            needsPin = false
            errorText = nil
            statusText = "Сопряжение выполнено, открываем пульт…"
            pairingConnection?.cancel()
            pairingConnection = nil
            onPairingSucceeded?()
            openRemoteConnection()
        }
    }

    // MARK: - Фаза 2: Канал управления пультом (порт 6466)

    private func openRemoteConnection() {
        guard let identity = clientIdentity,
              let port = NWEndpoint.Port(rawValue: UInt16(activeRemotePort)) else {
            errorText = "Неверный порт управления Android TV"
            return
        }

        statusText = "Подключение к \(activeHost):\(activeRemotePort)…"
        errorText = nil
        rxRemoteBuffer.removeAll()
        isConnected = false
        isReady = false

        let tlsOptions = makeTLSOptions(identity: identity, onServerCert: nil)
        let params = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        let conn = NWConnection(host: NWEndpoint.Host(activeHost), port: port, using: params)
        remoteConnection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.remoteConnection === conn else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.statusText = "Открываем канал пульта…"
                    self.receiveRemoteLoop(conn)
                case .failed:
                    self.isConnected = false
                    self.isReady = false
                    // Если сертификат ещё не доверен на ТВ — автоматически переключаемся на сопряжение 6467
                    if !self.isAttemptingFallbackToPairing {
                        self.isAttemptingFallbackToPairing = true
                        self.openPairingConnection()
                    } else {
                        self.errorText = "Не удалось подключиться к \(self.activeHost):\(self.activeRemotePort)"
                        self.statusText = "Нет подключения"
                    }
                case .waiting(let err):
                    self.statusText = "Ожидание сети (\(err.localizedDescription))…"
                default:
                    break
                }
            }
        }
        conn.start(queue: networkQueue)
    }

    private func receiveRemoteLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self, self.remoteConnection === conn else { return }
                if let data, !data.isEmpty {
                    self.rxRemoteBuffer.append(data)
                    self.drainFramedMessages(from: &self.rxRemoteBuffer) { payload in
                        self.handleRemoteMessage(payload)
                    }
                }
                if error != nil || isComplete {
                    let wasReady = self.isReady
                    self.isConnected = false
                    self.isReady = false
                    if !wasReady && !self.isAttemptingFallbackToPairing {
                        self.isAttemptingFallbackToPairing = true
                        self.openPairingConnection()
                    } else if wasReady {
                        self.statusText = "Соединение с ТВ прервано"
                    }
                    return
                }
                self.receiveRemoteLoop(conn)
            }
        }
    }

    private func handleRemoteMessage(_ payload: Data) {
        let fields = ATVProto.parseFields(payload)

        // 1. remote_configure от ТВ -> отвечаем нашим remote_configure
        if fields.contains(where: { $0.number == 1 }) {
            sendRemoteConfigure()
        }

        // 2. remote_set_active от ТВ -> отвечаем нашим remote_set_active и пульт готов!
        if fields.contains(where: { $0.number == 2 }) {
            sendRemoteSetActive()
            isReady = true
            isConnected = true
            errorText = nil
            statusText = "Пульт готов"
        }

        // 8. remote_ping_request -> сразу отвечаем remote_ping_response (9)
        if let pingField = fields.first(where: { $0.number == 8 }) {
            let sub = ATVProto.parseFields(pingField.bytes)
            let val1 = Int(sub.first(where: { $0.number == 1 })?.varint ?? 0)
            let pong = ATVProto.bytesField(9, ATVProto.varintField(1, val1))
            sendFramed(pong, over: remoteConnection)
        }

        // 20. remote_ime_key_inject -> текущее открытое приложение
        if let imeField = fields.first(where: { $0.number == 20 }) {
            let sub = ATVProto.parseFields(imeField.bytes)
            if let appInfo = sub.first(where: { $0.number == 1 }) {
                let infoFields = ATVProto.parseFields(appInfo.bytes)
                if let pkg = infoFields.first(where: { $0.number == 4 })?.bytes,
                   let str = String(data: pkg, encoding: .utf8), !str.isEmpty {
                    currentForegroundApp = str
                }
            }
        }
    }

    private func sendRemoteConfigure() {
        var devInfo = Data()
        devInfo.append(ATVProto.stringField(1, "iPhone"))
        devInfo.append(ATVProto.stringField(2, "Apple"))
        devInfo.append(ATVProto.varintField(3, 1))
        devInfo.append(ATVProto.stringField(4, "1"))
        devInfo.append(ATVProto.stringField(5, "com.andrey.saluteremoteplus"))
        devInfo.append(ATVProto.stringField(6, "2.4.0"))

        var cfg = Data()
        cfg.append(ATVProto.varintField(1, 622))
        cfg.append(ATVProto.bytesField(2, devInfo))

        let msg = ATVProto.bytesField(1, cfg)
        sendFramed(msg, over: remoteConnection)
    }

    private func sendRemoteSetActive() {
        let active = ATVProto.varintField(1, 622)
        let msg = ATVProto.bytesField(2, active)
        sendFramed(msg, over: remoteConnection)
    }

    // MARK: - Отправка команд пульта

    /// direction: 1 = START_LONG, 2 = END_LONG, 3 = SHORT
    func sendKeyCode(_ keyCode: Int, direction: Int = 3) {
        guard isReady else { return }
        var keyInject = Data()
        keyInject.append(ATVProto.varintField(1, keyCode))
        keyInject.append(ATVProto.varintField(2, direction))
        let msg = ATVProto.bytesField(10, keyInject)
        sendFramed(msg, over: remoteConnection)
    }

    func sendCommand(_ command: RemoteCommand) {
        sendKeyCode(command.androidKeyCode, direction: 3)
    }

    func sendCommandDown(_ command: RemoteCommand) {
        sendKeyCode(command.androidKeyCode, direction: 1)
    }

    func sendCommandUp(_ command: RemoteCommand) {
        sendKeyCode(command.androidKeyCode, direction: 2)
    }

    func sendAppLink(_ link: String) {
        guard isReady, !link.isEmpty else { return }
        let inner = ATVProto.stringField(1, link)
        let msg = ATVProto.bytesField(90, inner)
        sendFramed(msg, over: remoteConnection)
    }

    func sendText(_ text: String, submit: Bool) {
        guard isReady, !text.isEmpty else { return }
        // RemoteImeBatchEdit (field 21): edit_info (field 3) -> RemoteEditInfo { insert=1, text_field_status=2 { start=1, end=2, value=3 } }
        var imeObj = Data()
        imeObj.append(ATVProto.varintField(1, 0))
        imeObj.append(ATVProto.varintField(2, text.count))
        imeObj.append(ATVProto.stringField(3, text))

        var editInfo = Data()
        editInfo.append(ATVProto.varintField(1, 1))
        editInfo.append(ATVProto.bytesField(2, imeObj))

        var batch = Data()
        batch.append(ATVProto.varintField(1, 1))
        batch.append(ATVProto.varintField(2, 0))
        batch.append(ATVProto.bytesField(3, editInfo))

        let msg = ATVProto.bytesField(21, batch)
        sendFramed(msg, over: remoteConnection)

        if submit {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                self?.sendKeyCode(66, direction: 3) // KEYCODE_ENTER
            }
        }
    }

    // MARK: - TLS и транспортные утилиты

    private func makeTLSOptions(
        identity: SecIdentity,
        onServerCert: ((SecCertificate) -> Void)?
    ) -> NWProtocolTLS.Options {
        let tlsOptions = NWProtocolTLS.Options()
        if let secIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)
        }
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, secTrust, complete in
                if let onServerCert {
                    let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
                    if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                       let leaf = chain.first {
                        onServerCert(leaf)
                    }
                }
                complete(true)
            },
            networkQueue
        )
        return tlsOptions
    }

    private func sendFramed(_ payload: Data, over connection: NWConnection?) {
        guard let connection else { return }
        let framed = ATVProto.frameMessage(payload)
        connection.send(content: framed, completion: .contentProcessed { _ in })
    }

    private func drainFramedMessages(from buffer: inout Data, handler: (Data) -> Void) {
        while !buffer.isEmpty {
            guard let (length, headerEnd) = ATVProto.decodeVarint(from: buffer, at: 0) else {
                break
            }
            let totalNeeded = headerEnd + Int(length)
            guard buffer.count >= totalNeeded else {
                break
            }
            let base = buffer.startIndex
            let payload = Data(buffer[(base + headerEnd)..<(base + totalNeeded)])
            buffer = Data(buffer.dropFirst(totalNeeded))
            handler(payload)
        }
    }

    private func hexToBytes(_ hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var out = Data(capacity: hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
            out.append(byte)
            idx = next
        }
        return out
    }
}
