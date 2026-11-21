import Foundation
import SwiftUI

/// Полная реализация бинарного протокола JVCKENWOOD OpenLink (из KENWOOD Remote 2.0.5):
/// CRC-16/ARC (0xA001), byte-stuffing (0x7E ... 0x7C, escape 0x7D), адресация,
/// команды пульта, источников, тюнера, DSP/EQ, фейдера/баланса, DTA, кроссовера и подсветки.
enum KenwoodOpenLink {
    // MARK: - UUID сервисов из JK_BTOpenLinkCom
    static let openLinkServiceUUID = "DBA8F580-2D22-11E6-9569-0002A5D5C51B"
    static let tccServiceUUID      = "16F92DC0-2EEB-11E6-B342-0002A5D5C51B"
    static let altServiceUUID      = "0347ACC0-2EEB-11E6-B4AA-0002A5D5C51B"

    static let supportedEAProtocols: [String] = [
        "com.jvckenwood.openlink",
        "com.jvckenwood.car.openlink",
        "com.jvckenwood.openlink.1",
        "com.jvckenwood.openlink.2",
        "com.jvckenwood.remote",
        "com.jvckenwood.remoteapp",
        "com.jvckenwood.kenwoodremote",
        "com.jvckenwood.kwdremote",
        "com.jvckenwood.jvcremote",
        "com.jvckenwood.car.remote",
        "com.jvckenwood.car.remotecontrol",
        "com.jvckenwood.remotecontrol",
        "com.jvckenwood.jkts.openlink",
        "com.jvckenwood.jkts.kwdremoteapp",
        "com.jvckenwood.jkts.kwdremoteapp.openlink",
        "com.jvckenwood.jkts.jvcremoteapp",
        "com.jvckenwood.jsmc",
        "com.jvckenwood.jkmc",
        "com.jvckenwood.kmc",
        "com.jvckenwood.musicplay",
        "com.jvckenwood.tcc",
        "com.jvckenwood.car.tcc",
        "com.jvckenwood.car.app",
        "com.jvckenwood.car.link",
        "com.jvckenwood.car.audio",
        "com.jvckenwood.car.protocol",
        "com.jvckenwood.protocol",
        "com.jvckenwood.protocol.openlink",
        "com.jvckenwood.protocol.remote",
        "com.jvckenwood.app",
        "com.jvckenwood.link",
        "com.jvckenwood.audio",
        "com.jvckenwood.iap",
        "com.jvckenwood.iap2",
        "com.jvckenwood.portal",
        "jp.jvckenwood.openlink",
        "jp.jvckenwood.car.openlink",
        "jp.jvckenwood.remote",
        "jp.jvckenwood.car.remote",
        "jp.co.jvckenwood.openlink",
        "jp.co.jvckenwood.car.openlink",
        "jp.co.jvckenwood.remote",
        "jp.co.jvckenwood.remoteapp",
        "jp.co.jvckenwood.kenwoodremote",
        "jp.co.jvckenwood.car.remote",
        "com.kenwood.openlink",
        "com.kenwood.car.openlink",
        "com.kenwood.remote",
        "com.kenwood.remoteapp",
        "com.kenwood.car.remote",
        "com.kenwood.link",
        "com.kenwood.app",
        "com.kenwood.audio",
        "com.kenwood.krc",
        "jp.co.kenwood.openlink",
        "jp.co.kenwood.remote",
        "jp.co.kenwood.car.remote",
        "jp.co.kenwood.app",
        "com.jvc.openlink",
        "com.jvc.remote",
        "com.jvc.car.remote",
        "com.jvc.link",
        "jp.co.jvc.openlink",
        "jp.co.jvc.remote"
    ]

    private static let supportedEAProtocolsLowercased: Set<String> = Set(
        supportedEAProtocols.map { $0.lowercased() }
    )

    static func matchesSupportedProtocol(_ protocolString: String) -> Bool {
        supportedEAProtocolsLowercased.contains(protocolString.lowercased())
    }

    static func isKenwoodLikeName(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "kenwood", "jvc", "kmm", "kdc", "dpx", "dmx",
            "ddx", "dnx", "kw-", "kd-", "xr-", "excelon", "openlink"
        ]
        return markers.contains(where: { lower.contains($0) })
    }

    // MARK: - Границы кадра и escape-байты
    static let frameStart: UInt8 = 0x7E
    static let frameEnd: UInt8   = 0x7C
    static let escapeByte: UInt8 = 0x7D

    static let headerLength: UInt8   = 0x0B
    static let protocolVersion: UInt8 = 0x01
    static let sourceAddressApp: UInt8 = 0xA4

    // MARK: - Адреса узлов магнитолы (ControlParameter.addr_*)
    enum Address {
        static let main: UInt8  = 0x50
        static let tuner: UInt8 = 0x16
        static let bt: UInt8    = 0x4C
        static let usb: UInt8   = 0x57
        static let cd: UInt8    = 0x81
        static let ipod: UInt8  = 0x9C
        static let aoa: UInt8   = 0x9D
        static let sd: UInt8    = 0xBB
        static let aux: UInt8   = 0xE5
    }

    // MARK: - Категории команд (ControlParameter)
    enum Category {
        static let keyCode: UInt8       = 0x11
        static let keyCodeNotify: UInt8 = 0x12
        static let requestCmd: UInt8    = 0x3B
        static let requestRadio: UInt8  = 0x3C
        static let requestSetting: UInt8 = 0x3D
        static let bluetoothData: UInt8 = 0x4A
        static let sendCmd: UInt8       = 0x5B
        static let sendRadio: UInt8     = 0x5C
        static let sendSetting: UInt8   = 0x5D
        static let notifyRadio: UInt8   = 0x8C
    }

    // MARK: - Типы полезной нагрузки (JK_BTOpenLinkCom.plType_*)
    enum PayloadType {
        static let general: UInt8 = 0x00
        static let ack: UInt8     = 0x01
        static let reqCmd: UInt8  = 0x02
        static let rpyCmd: UInt8  = 0x03
        static let notify: UInt8  = 0x04
        static let update: UInt8  = 0x05
        static let key: UInt8     = 0x06
    }

    // MARK: - Уведомления от магнитолы (addr=0x50, ntfy_man_*)
    enum MainNotify {
        static let sourceChanged: UInt8   = 0x01
        static let presetEQChanged: UInt8 = 0x02
        static let volumeChanged: UInt8   = 0x04
        static let titleInfo: UInt8       = 0x05
        static let artistInfo: UInt8      = 0x06
        static let albumInfo: UInt8       = 0x07
        static let fileInfo: UInt8        = 0x08
        static let dirInfo: UInt8         = 0x09
        static let radioFreqInfo: UInt8   = 0x0A
        static let radioStationInfo: UInt8 = 0x0B
        static let muteChanged: UInt8     = 0x0C
        static let radioTitleInfo: UInt8  = 0x0D
        static let radioArtistInfo: UInt8 = 0x0E
        static let radioAlbumInfo: UInt8  = 0x0F
        static let btAudioDevice: UInt8   = 0x12
        static let firmwareVersion: UInt8 = 0x13
    }

    // MARK: - Команды аудио/DSP/подсветки (addr=0x50, cat=0x3D)
    enum SettingCmd {
        static let getEQCapability: UInt8 = 0x01
        static let getCustomEQ: UInt8     = 0x04
        static let setCustomEQ: UInt8     = 0x05
        static let getHPFLPF: UInt8       = 0x08
        static let setHPFLPF: UInt8       = 0x09
        static let getFadBal: UInt8       = 0x0B
        static let setFadBal: UInt8       = 0x0C
        static let getPresetEQList: UInt8 = 0x0D
        static let getPresetEQ: UInt8     = 0x0E
        static let setPresetEQ: UInt8     = 0x0F
        static let getColorVersion: UInt8 = 0x10
        static let setPresetColor: UInt8  = 0x11
        static let getCurColor: UInt8     = 0x12
        static let getPresetRGB: UInt8    = 0x14
        static let getBassExt: UInt8      = 0x40
        static let setBassExt: UInt8      = 0x41
        static let getSWPhase: UInt8      = 0x43
        static let setSWPhase: UInt8      = 0x44
        static let getSWLevel: UInt8      = 0x46
        static let setSWLevel: UInt8      = 0x47
        static let getBassBoost: UInt8    = 0x49
        static let setBassBoost: UInt8    = 0x4A
        static let getLoudness: UInt8     = 0x4C
        static let setLoudness: UInt8     = 0x4D
        static let getSWSet: UInt8        = 0x4E
        static let setSWSet: UInt8        = 0x4F
        static let getSpkSize: UInt8      = 0x50
        static let setSpkOption: UInt8    = 0x55
        static let getXover: UInt8        = 0x58
        static let setXover: UInt8        = 0x59
        static let getDTA: UInt8          = 0x5D
        static let setDTA: UInt8          = 0x5E
        static let getCarType: UInt8      = 0x61
        static let setCarType: UInt8      = 0x62
    }

    // MARK: - Таблица CRC-16/ARC (полином 0xA001, идентична JK_BTOpenLinkCom.CRC16_Table)
    private static let crc16Table: [UInt16] = {
        var table = [UInt16](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt16(i)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
            table[i] = crc
        }
        return table
    }()

    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0x0000
        for b in bytes {
            let idx = Int((crc ^ UInt16(b)) & 0xFF)
            crc = (crc >> 8) ^ crc16Table[idx]
        }
        return crc
    }

    /// Byte-stuffing из JK_BTOpenLinkCom.ByteStuffing:
    /// 0x7C -> 0x7D 0x5C, 0x7D -> 0x7D 0x5D, 0x7E -> 0x7D 0x5E
    static func byteStuff(_ raw: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(raw.count + 8)
        for b in raw {
            switch b {
            case 0x7C:
                out.append(escapeByte)
                out.append(0x5C)
            case 0x7D:
                out.append(escapeByte)
                out.append(0x5D)
            case 0x7E:
                out.append(escapeByte)
                out.append(0x5E)
            default:
                out.append(b)
            }
        }
        return out
    }

    /// Byte-unstuffing из JK_BTOpenLinkCom.ByteUnstuffing
    static func byteUnstuff(_ stuffed: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(stuffed.count)
        var i = 0
        while i < stuffed.count {
            let b = stuffed[i]
            if b == escapeByte, i + 1 < stuffed.count {
                let next = stuffed[i + 1]
                switch next {
                case 0x5C: out.append(0x7C)
                case 0x5D: out.append(0x7D)
                case 0x5E: out.append(0x7E)
                default: out.append(next)
                }
                i += 2
            } else {
                out.append(b)
                i += 1
            }
        }
        return out
    }

    /// Собирает готовый проводной кадр OpenLink: [0x7E] + stuffed(header + payload + CRC16_BE) + [0x7C]
    static func buildFrame(
        destAddr: UInt8,
        category: UInt8,
        command: UInt8,
        seqNum: UInt8,
        payloadType: UInt8 = PayloadType.general,
        payload: [UInt8] = []
    ) -> Data {
        var body: [UInt8] = [
            headerLength,
            protocolVersion,
            sourceAddressApp,
            destAddr,
            category,
            command,
            seqNum,
            payloadType,
            0x01,
            UInt8((payload.count >> 8) & 0xFF),
            UInt8(payload.count & 0xFF)
        ]
        body.append(contentsOf: payload)
        let crc = crc16(body)
        body.append(UInt8((crc >> 8) & 0xFF))
        body.append(UInt8(crc & 0xFF))

        var frame: [UInt8] = [frameStart]
        frame.append(contentsOf: byteStuff(body))
        frame.append(frameEnd)
        return Data(frame)
    }

    /// Собирает ответный ACK-кадр на входящий пакет магнитолы (из DataProcessTask + ConstructMsg)
    static func buildAckFrame(for packet: OpenLinkPacket) -> Data {
        var body: [UInt8] = [
            headerLength,
            protocolVersion,
            packet.sourceAddr,
            packet.destAddr,
            packet.category,
            packet.command,
            packet.seqNum,
            PayloadType.ack,
            0x01,
            0x00,
            0x01,
            0x00
        ]
        let crc = crc16(body)
        body.append(UInt8((crc >> 8) & 0xFF))
        body.append(UInt8(crc & 0xFF))

        var frame: [UInt8] = [frameStart]
        frame.append(contentsOf: byteStuff(body))
        frame.append(frameEnd)
        return Data(frame)
    }

    /// Разбирает неэкранированный буфер между 0x7E и 0x7C
    static func parseFrameContent(_ stuffedBytes: [UInt8]) -> OpenLinkPacket? {
        let raw = byteUnstuff(stuffedBytes)
        guard raw.count >= 13 else { return nil }
        guard raw[0] == headerLength else { return nil }

        let payloadLen = (Int(raw[9]) << 8) | Int(raw[10])
        guard raw.count >= 11 + payloadLen + 2 else { return nil }

        let dataWithoutCRC = Array(raw[0..<(11 + payloadLen)])
        let expectedCRC = crc16(dataWithoutCRC)
        let receivedCRC = (UInt16(raw[11 + payloadLen]) << 8) | UInt16(raw[11 + payloadLen + 1])
        guard expectedCRC == receivedCRC else { return nil }

        let payload = payloadLen > 0 ? Array(raw[11..<(11 + payloadLen)]) : []
        return OpenLinkPacket(
            sourceAddr: raw[2],
            destAddr: raw[3],
            category: raw[4],
            command: raw[5],
            seqNum: raw[6],
            payloadType: raw[7],
            payload: payload
        )
    }
}

struct OpenLinkPacket {
    let sourceAddr: UInt8
    let destAddr: UInt8
    let category: UInt8
    let command: UInt8
    let seqNum: UInt8
    let payloadType: UInt8
    let payload: [UInt8]
}

// MARK: - Источники сигнала Kenwood (Constants$SRC_CAT & SRC_TYPE)

enum KenwoodSource: String, CaseIterable, Identifiable {
    case btAudio
    case fm
    case am
    case dab
    case frontUSB
    case rearUSB
    case cd
    case aux
    case hdmi
    case standby

    var id: String { rawValue }

    var title: String {
        switch self {
        case .btAudio: return "BT Audio"
        case .fm: return "FM"
        case .am: return "AM"
        case .dab: return "DAB+"
        case .frontUSB: return "USB 1"
        case .rearUSB: return "USB 2"
        case .cd: return "CD"
        case .aux: return "AUX"
        case .hdmi: return "HDMI"
        case .standby: return "Standby"
        }
    }

    var symbol: String {
        switch self {
        case .btAudio: return "antenna.radiowaves.left.and.right"
        case .fm, .am, .dab: return "radio.fill"
        case .frontUSB, .rearUSB: return "externaldrive.fill"
        case .cd: return "opticaldisc"
        case .aux: return "cable.connector"
        case .hdmi: return "tv.fill"
        case .standby: return "power"
        }
    }

    var srcCategoryByte: UInt8 {
        switch self {
        case .cd: return 1
        case .aux: return 2
        case .fm, .am, .dab: return 3
        case .frontUSB: return 4
        case .rearUSB: return 5
        case .btAudio: return 8
        case .standby: return 13
        case .hdmi: return 14
        }
    }

    var srcTypeByte: UInt8 {
        switch self {
        case .am: return 11
        case .fm: return 12
        case .dab: return 15
        case .frontUSB: return 17
        case .rearUSB: return 21
        case .cd: return 35
        case .btAudio: return 39
        case .aux: return 47
        case .standby: return 84
        case .hdmi: return 85
        }
    }

    var mediaControlAddress: UInt8 {
        switch self {
        case .btAudio: return KenwoodOpenLink.Address.bt
        case .fm, .am, .dab: return KenwoodOpenLink.Address.tuner
        case .frontUSB, .rearUSB: return KenwoodOpenLink.Address.usb
        case .cd: return KenwoodOpenLink.Address.cd
        default: return KenwoodOpenLink.Address.main
        }
    }

    var isRadio: Bool {
        self == .fm || self == .am || self == .dab
    }

    static func from(category: UInt8, type: UInt8) -> KenwoodSource? {
        if let exact = allCases.first(where: { $0.srcTypeByte == type }) {
            return exact
        }
        return allCases.first(where: { $0.srcCategoryByte == category })
    }
}

// MARK: - Коды кнопок пульта Kenwood (ControlParameter.remo_* и remo_mm_*)

enum KenwoodRemoconKey {
    case play, up, down, left, right, enter, back, source, att, audio
    case volUp, volDown, fm, am, direct, menu, topMenu, twoZone
    case digit(Int)

    func code(multimedia: Bool) -> UInt8 {
        if multimedia {
            switch self {
            case .volUp: return 0x01
            case .volDown: return 0x02
            case .source: return 0x03
            case .att: return 0x04
            case .up: return 0x05
            case .left: return 0x06
            case .play: return 0x07
            case .right: return 0x08
            case .down: return 0x09
            case .direct: return 0x0A
            case .enter: return 0x16
            case .fm: return 0x18
            case .am: return 0x1A
            case .twoZone: return 0x1B
            case .topMenu: return 0x40
            case .menu: return 0x41
            case .back: return 0x42
            case .audio: return 0x0D
            case .digit(let n):
                switch n {
                case 1: return 0x0B
                case 2: return 0x0C
                case 3: return 0x0D
                case 4: return 0x0E
                case 5: return 0x0F
                case 6: return 0x10
                case 7: return 0x11
                case 8: return 0x12
                case 9: return 0x13
                default: return 0x15
                }
            }
        } else {
            switch self {
            case .play: return 0x01
            case .right: return 0x03
            case .left: return 0x04
            case .up: return 0x05
            case .down: return 0x06
            case .volDown: return 0x07
            case .volUp: return 0x08
            case .source: return 0x09
            case .back: return 0x0A
            case .enter: return 0x0B
            case .att: return 0x0C
            case .audio: return 0x0D
            case .am: return 0x0E
            case .fm: return 0x0F
            case .direct: return 0x1A
            case .menu: return 0x41
            case .topMenu: return 0x40
            case .twoZone: return 0x1B
            case .digit(let n):
                switch n {
                case 1...9: return UInt8(0x0F + n)
                default: return 0x19
                }
            }
        }
    }
}

// MARK: - Пресеты эквалайзера (EQPresetActivity)

enum KenwoodEQPreset: Int, CaseIterable, Identifiable {
    case natural = 0
    case rock = 1
    case pops = 2
    case easy = 3
    case top40 = 4
    case jazz = 5
    case powerful = 6
    case flat = 7
    case driveEQ = 8
    case user = 9

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .natural: return "NATURAL"
        case .rock: return "ROCK"
        case .pops: return "POPS"
        case .easy: return "EASY"
        case .top40: return "TOP40"
        case .jazz: return "JAZZ"
        case .powerful: return "POWERFUL"
        case .flat: return "FLAT"
        case .driveEQ: return "DRIVE EQ"
        case .user: return "USER"
        }
    }

    /// Характерная 13-полосная кривая (-9...+9 dB) для визуального предпросмотра и записи в User EQ
    var defaultCurve: [Int] {
        switch self {
        case .natural:  return [1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 1]
        case .rock:     return [5, 4, 3, 1, -1, -2, -1, 1, 2, 4, 5, 5, 4]
        case .pops:     return [-1, 1, 3, 4, 3, 1, 0, 1, 2, 3, 2, 1, 0]
        case .easy:     return [2, 2, 1, 0, 0, 1, 2, 2, 1, 0, -1, -1, 0]
        case .top40:    return [4, 4, 2, 0, -1, 0, 1, 2, 3, 4, 4, 3, 2]
        case .jazz:     return [3, 2, 1, 2, 0, -1, 0, 1, 2, 3, 3, 2, 2]
        case .powerful: return [6, 5, 4, 2, 0, 0, 1, 2, 3, 4, 5, 5, 4]
        case .flat:     return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .driveEQ:  return [4, 3, 2, 1, 0, 1, 2, 2, 3, 3, 2, 1, 0]
        case .user:     return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
    }
}

// MARK: - Пресеты подсветки Kenwood (24 цвета ColorPresetActivity)

struct KenwoodColorPreset: Identifiable, Equatable {
    let id: Int
    let name: String
    let r: Int // 0...31
    let g: Int // 0...31
    let b: Int // 0...31

    var swiftUIColor: Color {
        Color(
            red: Double(r) / 31.0,
            green: Double(g) / 31.0,
            blue: Double(b) / 31.0
        )
    }

    static let presets: [KenwoodColorPreset] = [
        .init(id: 0,  name: "Variable Scan", r: 6,  g: 26, b: 14),
        .init(id: 1,  name: "Белый",         r: 31, g: 31, b: 31),
        .init(id: 2,  name: "Красный",       r: 31, g: 2,  b: 2),
        .init(id: 3,  name: "Рубин",         r: 31, g: 0,  b: 8),
        .init(id: 4,  name: "Оранжевый",     r: 31, g: 12, b: 0),
        .init(id: 5,  name: "Янтарь",        r: 31, g: 18, b: 0),
        .init(id: 6,  name: "Жёлтый",        r: 31, g: 28, b: 0),
        .init(id: 7,  name: "Лайм",          r: 18, g: 31, b: 0),
        .init(id: 8,  name: "Сбер Зелёный",  r: 6,  g: 27, b: 11),
        .init(id: 9,  name: "Изумруд",       r: 0,  g: 31, b: 14),
        .init(id: 10, name: "Мята",          r: 0,  g: 31, b: 24),
        .init(id: 11, name: "Циан",          r: 0,  g: 26, b: 31),
        .init(id: 12, name: "Небесный",      r: 0,  g: 16, b: 31),
        .init(id: 13, name: "Синий",         r: 0,  g: 6,  b: 31),
        .init(id: 14, name: "Кобальт",       r: 6,  g: 4,  b: 31),
        .init(id: 15, name: "Индиго",        r: 14, g: 2,  b: 31),
        .init(id: 16, name: "Фиолетовый",    r: 22, g: 0,  b: 31),
        .init(id: 17, name: "Маджента",      r: 31, g: 0,  b: 24),
        .init(id: 18, name: "Розовый",       r: 31, g: 8,  b: 18),
        .init(id: 19, name: "Коралл",        r: 31, g: 10, b: 8),
        .init(id: 20, name: "Тёплый белый",  r: 31, g: 26, b: 18),
        .init(id: 21, name: "Лёд",           r: 18, g: 28, b: 31),
        .init(id: 22, name: "Ультрамарин",   r: 2,  g: 10, b: 28),
        .init(id: 23, name: "Пользователь",  r: 16, g: 31, b: 12)
    ]
}

// MARK: - Параметры DSP, Time Alignment и Кроссовера

enum KenwoodListeningPosition: Int, CaseIterable, Identifiable {
    case all = 0
    case frontAll = 1
    case frontLeft = 2
    case frontRight = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all: return "Весь салон"
        case .frontAll: return "Передние"
        case .frontLeft: return "Водитель (L)"
        case .frontRight: return "Пассажир (R)"
        }
    }
}

enum KenwoodCarType: Int, CaseIterable, Identifiable {
    case off = 0
    case compact = 1
    case fullSize = 2
    case wagon = 3
    case minivan = 4
    case suv = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: return "Не выбран"
        case .compact: return "Хэтчбек"
        case .fullSize: return "Седан"
        case .wagon: return "Универсал"
        case .minivan: return "Минивэн"
        case .suv: return "Кроссовер / SUV"
        }
    }
}

struct KenwoodDiscoveredDevice: Identifiable, Equatable {
    enum Transport: String {
        case mfiBluetooth = "Bluetooth / USB (MFi)"
        case ble = "Bluetooth LE"
    }

    let id: String
    let name: String
    let transport: Transport
    let detail: String
    let protocolString: String?
}
