import Foundation
import SwiftUI
import ExternalAccessory
import CoreBluetooth

/// Менеджер подключения и управления автомагнитолой Kenwood по протоколу JVCKENWOOD OpenLink.
/// Поддерживает два нативных транспорта iOS 15–27:
/// 1) Apple MFi ExternalAccessory (`EASession` поверх Bluetooth iAP2 / USB Lightning / USB-C)
/// 2) CoreBluetooth BLE (`CBCentralManager` / `CBPeripheral`) для BLE-совместимых ресиверов и адаптеров.
@MainActor
final class KenwoodRemoteManager: NSObject, ObservableObject {
    // MARK: - Состояние подключения
    @Published private(set) var discoveredDevices: [KenwoodDiscoveredDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var activeTransportLabel: String?
    @Published private(set) var statusText = "Подключите iPhone к магнитоле Kenwood по Bluetooth или USB"
    @Published private(set) var bluetoothStateText: String?

    // MARK: - Живое состояние магнитолы
    @Published var currentSource: KenwoodSource = .btAudio
    @Published var volume: Int = 15 // 0...35
    @Published var isMuted: Bool = false
    @Published var isPlaying: Bool = true
    @Published var repeatMode: Int = 0 // 0=Off, 1=One, 2=All
    @Published var randomEnabled: Bool = false
    @Published var multimediaRemocon: Bool = false

    @Published var trackTitle: String = "Нет активного трека"
    @Published var trackArtist: String = "Подключите магнитолу Kenwood"
    @Published var trackAlbum: String = ""
    @Published var tunerFrequency: String = "101.2 MHz"
    @Published var tunerStation: String = "FM1"
    @Published var activeTunerPreset: Int = 1
    @Published var firmwareVersion: String?

    // MARK: - Аудио DSP (Эквалайзер, Фейдер/Баланс, Сабвуфер, Эффекты, DTA, Кроссовер)
    static let eqBandLabels: [String] = [
        "62.5", "100", "160", "250", "400", "630", "1k", "1.6k", "2.5k", "4k", "6.3k", "10k", "16k"
    ]
    static let crossoverFrequencies: [Int] = [0, 30, 40, 50, 60, 70, 80, 90, 100, 120, 150, 180, 220, 250]
    static let crossoverSlopes: [Int] = [6, 12, 18, 24]

    @Published var selectedEQPreset: KenwoodEQPreset = .natural
    @Published var eqBands: [Int] = KenwoodEQPreset.natural.defaultCurve // 13 полос, -9...+9 dB
    @Published var balance: Int = 0 // -15 (L) ... +15 (R)
    @Published var fader: Int = 0   // -15 (R) ... +15 (F)

    @Published var subwooferEnabled: Bool = true
    @Published var subwooferLevel: Int = 0 // -15 ... +10
    @Published var subwooferPhaseReversed: Bool = false
    @Published var bassBoost: Int = 0 // 0 ... 5
    @Published var bassExtend: Bool = false
    @Published var loudness: Int = 0 // 0=Off, 1=Low, 2=High

    @Published var listeningPosition: KenwoodListeningPosition = .all
    @Published var dtaDistancesCm: [Int] = [120, 120, 150, 150, 180] // FL, FR, RL, RR, SW (0...610 см)
    @Published var frontHPFIndex: Int = 6 // 80 Hz
    @Published var rearHPFIndex: Int = 6  // 80 Hz
    @Published var subLPFIndex: Int = 6   // 80 Hz
    @Published var xoverSlopeIndex: Int = 1 // 12 dB/oct
    @Published var carType: KenwoodCarType = .fullSize

    // MARK: - Подсветка (Illumination)
    @Published var selectedColorPresetId: Int = 2 // Фирменный Kenwood Red по умолчанию
    @Published var customRed: Int = 31  // 0...31
    @Published var customGreen: Int = 2 // 0...31
    @Published var customBlue: Int = 2  // 0...31

    // MARK: - Внутренние транспорты и буферы
    private var eaSession: EASession?
    private var eaAccessories: [String: EAAccessory] = [:]

    private var centralManager: CBCentralManager?
    private var blePeripherals: [String: CBPeripheral] = [:]
    private var activeBLEPeripheral: CBPeripheral?
    private var bleWriteCharacteristic: CBCharacteristic?

    private var txSeqNum: UInt8 = 1
    private var rxAccumulator: [UInt8] = []
    private var inFrame = false
    private var isStarted = false

    override init() {
        super.init()
    }

    func start() {
        guard !isStarted else {
            refreshDevices()
            return
        }
        isStarted = true

        // Подписываемся на MFi ExternalAccessory (Bluetooth iAP2 / USB)
        EAAccessoryManager.shared().registerForLocalNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEAAccessoryConnected(_:)),
            name: .EAAccessoryDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEAAccessoryDisconnected(_:)),
            name: .EAAccessoryDidDisconnect,
            object: nil
        )

        // Запускаем CoreBluetooth для BLE-устройств
        centralManager = CBCentralManager(delegate: self, queue: .main)
        refreshDevices()
    }

    func stopScanning() {
        isScanning = false
        centralManager?.stopScan()
    }

    func refreshDevices() {
        scanExternalAccessories()
        startBLEScan()
    }

    /// Открывает системный iOS-диалог сопряжения Bluetooth-аксессуара MFi (если магнитола ещё не подключена).
    func showSystemBluetoothPicker() {
        EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: nil) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDevices()
            }
        }
    }

    // MARK: - Подключение и отключение

    func connect(to device: KenwoodDiscoveredDevice) {
        disconnect(silent: true)

        switch device.transport {
        case .mfiBluetooth:
            guard let accessory = eaAccessories[device.id] else {
                statusText = "Устройство больше не доступно. Проверьте Bluetooth."
                return
            }
            let proto = device.protocolString
                ?? accessory.protocolStrings.first(where: { KenwoodOpenLink.supportedEAProtocols.contains($0) })
                ?? accessory.protocolStrings.first

            guard let protocolString = proto else {
                statusText = "Магнитола не открыла канал OpenLink"
                return
            }
            openEASession(accessory: accessory, protocolString: protocolString)

        case .ble:
            guard let peripheral = blePeripherals[device.id], let central = centralManager else {
                statusText = "BLE-устройство недоступно"
                return
            }
            stopScanning()
            statusText = "Подключение к \(device.name)…"
            activeBLEPeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    func disconnect(silent: Bool = false) {
        closeEASession()

        if let peripheral = activeBLEPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        activeBLEPeripheral = nil
        bleWriteCharacteristic = nil

        isConnected = false
        connectedDeviceName = nil
        activeTransportLabel = nil
        rxAccumulator.removeAll()
        inFrame = false

        if !silent {
            statusText = "Отключено от магнитолы"
        }
    }

    // MARK: - Handshake OpenLink (3B 01 -> 5B 02 -> 3B 30 -> 3B 12 -> 3B 36)

    private func performOpenLinkHandshake() {
        // 1. Запрос возможностей ресивера (req_OL_REC_Feature)
        sendPacket(addr: KenwoodOpenLink.Address.main, cat: KenwoodOpenLink.Category.requestCmd, cmd: 0x01)
        // 2. Передача возможностей приложения (req_OL_DEV_Feature: [0x00, 0x00, 0x01, 0x01])
        sendPacket(addr: KenwoodOpenLink.Address.main, cat: KenwoodOpenLink.Category.sendCmd, cmd: 0x02, payload: [0x00, 0x00, 0x01, 0x01])
        // 3. Запрос списка источников (req_ol_src_itm)
        sendPacket(addr: KenwoodOpenLink.Address.main, cat: KenwoodOpenLink.Category.requestCmd, cmd: 0x30)
        // 4. Запрос текущего источника и громкости (req_ol_src_stat_info)
        sendPacket(addr: KenwoodOpenLink.Address.main, cat: KenwoodOpenLink.Category.requestCmd, cmd: 0x12)
        // 5. Запрос версии пульта (req_ol_remocon_ver)
        sendPacket(addr: KenwoodOpenLink.Address.main, cat: KenwoodOpenLink.Category.requestCmd, cmd: 0x36)
        // 6. Запрос текущих настроек звука и подсветки
        sendPacket(addr: KenwoodOpenLink.Address.main, cat: KenwoodOpenLink.Category.requestSetting, cmd: KenwoodOpenLink.SettingCmd.getPresetEQ)
        sendPacket(addr: KenwoodOpenLink.Address.main, cat: KenwoodOpenLink.Category.requestSetting, cmd: KenwoodOpenLink.SettingCmd.getFadBal)
        sendPacket(addr: KenwoodOpenLink.Address.main, cat: KenwoodOpenLink.Category.requestSetting, cmd: KenwoodOpenLink.SettingCmd.getCurColor)
    }

    // MARK: - Высокоуровневые команды управления магнитолой

    func selectSource(_ source: KenwoodSource) {
        currentSource = source
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.keyCode,
            cmd: 0x01,
            payload: [source.srcCategoryByte, source.srcTypeByte]
        )
    }

    func cycleSource() {
        let cycle: [KenwoodSource] = [.btAudio, .fm, .am, .frontUSB, .cd, .aux]
        if let idx = cycle.firstIndex(of: currentSource) {
            currentSource = cycle[(idx + 1) % cycle.count]
        } else {
            currentSource = .btAudio
        }
        sendRemoconKey(.source)
    }

    func volumeUp() {
        volume = min(35, volume + 1)
        isMuted = false
        sendRemoconKey(.volUp)
    }

    func volumeDown() {
        volume = max(0, volume - 1)
        sendRemoconKey(.volDown)
    }

    func setVolume(_ level: Int) {
        let clamped = min(max(level, 0), 35)
        volume = clamped
        isMuted = (clamped == 0)
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.keyCode,
            cmd: 0x02,
            payload: [UInt8(clamped)]
        )
    }

    func toggleMute() {
        isMuted.toggle()
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.keyCode,
            cmd: 0x03,
            payload: [isMuted ? 0x01 : 0x00]
        )
    }

    func sendRemoconKey(_ key: KenwoodRemoconKey) {
        let code = key.code(multimedia: multimediaRemocon)
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.keyCode,
            cmd: 0x05,
            payload: [code]
        )
    }

    // MARK: - Воспроизведение (BT / USB / CD / Тюнер)

    func playPause() {
        isPlaying.toggle()
        if currentSource == .btAudio {
            sendPacket(addr: KenwoodOpenLink.Address.bt, cat: KenwoodOpenLink.Category.bluetoothData, cmd: 0x50, payload: [isPlaying ? 0x80 : 0x82])
        } else if currentSource.isRadio {
            toggleMute()
        } else {
            let addr = currentSource.mediaControlAddress
            sendPacket(addr: addr, cat: KenwoodOpenLink.Category.keyCode, cmd: isPlaying ? 0x80 : 0x82)
        }
    }

    func stopPlayback() {
        isPlaying = false
        if currentSource == .btAudio {
            sendPacket(addr: KenwoodOpenLink.Address.bt, cat: KenwoodOpenLink.Category.bluetoothData, cmd: 0x50, payload: [0x81])
        } else {
            sendPacket(addr: currentSource.mediaControlAddress, cat: KenwoodOpenLink.Category.keyCode, cmd: 0x81)
        }
    }

    func nextTrack() {
        if currentSource.isRadio {
            tunerSeekUp()
        } else if currentSource == .btAudio {
            sendPacket(addr: KenwoodOpenLink.Address.bt, cat: KenwoodOpenLink.Category.bluetoothData, cmd: 0x50, payload: [0x90])
        } else {
            sendPacket(addr: currentSource.mediaControlAddress, cat: KenwoodOpenLink.Category.keyCode, cmd: 0x90)
        }
    }

    func previousTrack() {
        if currentSource.isRadio {
            tunerSeekDown()
        } else if currentSource == .btAudio {
            sendPacket(addr: KenwoodOpenLink.Address.bt, cat: KenwoodOpenLink.Category.bluetoothData, cmd: 0x50, payload: [0x91])
        } else {
            sendPacket(addr: currentSource.mediaControlAddress, cat: KenwoodOpenLink.Category.keyCode, cmd: 0x91)
        }
    }

    func fastForward(active: Bool) {
        let addr = currentSource.mediaControlAddress
        if currentSource == .btAudio {
            sendPacket(addr: KenwoodOpenLink.Address.bt, cat: KenwoodOpenLink.Category.bluetoothData, cmd: 0x50, payload: [active ? 0x92 : 0x00])
        } else if !currentSource.isRadio {
            sendPacket(addr: addr, cat: KenwoodOpenLink.Category.keyCode, cmd: active ? 0x92 : 0x00)
        }
    }

    func rewind(active: Bool) {
        let addr = currentSource.mediaControlAddress
        if currentSource == .btAudio {
            sendPacket(addr: KenwoodOpenLink.Address.bt, cat: KenwoodOpenLink.Category.bluetoothData, cmd: 0x50, payload: [active ? 0x93 : 0x00])
        } else if !currentSource.isRadio {
            sendPacket(addr: addr, cat: KenwoodOpenLink.Category.keyCode, cmd: active ? 0x93 : 0x00)
        }
    }

    func folderUp() {
        guard !currentSource.isRadio else {
            tunerNextPreset()
            return
        }
        sendPacket(addr: currentSource.mediaControlAddress, cat: KenwoodOpenLink.Category.keyCode, cmd: 0xA2)
    }

    func folderDown() {
        guard !currentSource.isRadio else {
            tunerPreviousPreset()
            return
        }
        sendPacket(addr: currentSource.mediaControlAddress, cat: KenwoodOpenLink.Category.keyCode, cmd: 0xA3)
    }

    func cycleRepeat() {
        repeatMode = (repeatMode + 1) % 3
        if currentSource == .btAudio {
            sendPacket(addr: KenwoodOpenLink.Address.bt, cat: KenwoodOpenLink.Category.bluetoothData, cmd: 0x5E, payload: [0x01, UInt8(repeatMode)])
        } else {
            sendPacket(addr: currentSource.mediaControlAddress, cat: KenwoodOpenLink.Category.keyCode, cmd: 0xB7, payload: [UInt8(repeatMode)])
        }
    }

    func toggleRandom() {
        randomEnabled.toggle()
        if currentSource == .btAudio {
            sendPacket(addr: KenwoodOpenLink.Address.bt, cat: KenwoodOpenLink.Category.bluetoothData, cmd: 0x5E, payload: [0x02, randomEnabled ? 0x01 : 0x00])
        } else {
            sendPacket(addr: currentSource.mediaControlAddress, cat: KenwoodOpenLink.Category.keyCode, cmd: 0xB8, payload: [randomEnabled ? 0x01 : 0x00])
        }
    }

    // MARK: - Тюнер FM / AM / DAB

    func tunerFreqUp() {
        sendPacket(addr: KenwoodOpenLink.Address.tuner, cat: KenwoodOpenLink.Category.keyCodeNotify, cmd: 0x10)
    }

    func tunerFreqDown() {
        sendPacket(addr: KenwoodOpenLink.Address.tuner, cat: KenwoodOpenLink.Category.keyCodeNotify, cmd: 0x11)
    }

    func tunerSeekUp() {
        sendPacket(addr: KenwoodOpenLink.Address.tuner, cat: KenwoodOpenLink.Category.keyCodeNotify, cmd: 0x15)
    }

    func tunerSeekDown() {
        sendPacket(addr: KenwoodOpenLink.Address.tuner, cat: KenwoodOpenLink.Category.keyCodeNotify, cmd: 0x16)
    }

    func tunerSelectPreset(_ number: Int) {
        activeTunerPreset = number
        sendPacket(addr: KenwoodOpenLink.Address.tuner, cat: KenwoodOpenLink.Category.keyCodeNotify, cmd: 0x20, payload: [UInt8(number)])
    }

    func tunerSavePreset(_ number: Int) {
        activeTunerPreset = number
        sendPacket(addr: KenwoodOpenLink.Address.tuner, cat: KenwoodOpenLink.Category.keyCodeNotify, cmd: 0x25, payload: [UInt8(number)])
    }

    func tunerNextPreset() {
        activeTunerPreset = activeTunerPreset >= 6 ? 1 : activeTunerPreset + 1
        sendPacket(addr: KenwoodOpenLink.Address.tuner, cat: KenwoodOpenLink.Category.keyCodeNotify, cmd: 0x21)
    }

    func tunerPreviousPreset() {
        activeTunerPreset = activeTunerPreset <= 1 ? 6 : activeTunerPreset - 1
        sendPacket(addr: KenwoodOpenLink.Address.tuner, cat: KenwoodOpenLink.Category.keyCodeNotify, cmd: 0x22)
    }

    // MARK: - Аудио DSP: Эквалайзер, Фейдер/Баланс, Сабвуфер, Эффекты, DTA, Кроссовер

    func selectEQPreset(_ preset: KenwoodEQPreset) {
        selectedEQPreset = preset
        if preset != .user {
            eqBands = preset.defaultCurve
        }
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setPresetEQ,
            payload: [UInt8(preset.rawValue)]
        )
    }

    func updateEQBand(index: Int, value: Int) {
        guard eqBands.indices.contains(index) else { return }
        let clamped = min(max(value, -9), 9)
        eqBands[index] = clamped
        selectedEQPreset = .user
        // Кодирование полос: смещение +9 (0..18) для каждой из 13 полос
        var payload: [UInt8] = [UInt8(eqBands.count)]
        payload.append(contentsOf: eqBands.map { UInt8(clamping: $0 + 9) })
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setCustomEQ,
            payload: payload
        )
    }

    func resetEQFlat() {
        eqBands = Array(repeating: 0, count: 13)
        selectedEQPreset = .flat
        selectEQPreset(.flat)
    }

    func updateFaderBalance(fader newFader: Int, balance newBalance: Int) {
        fader = min(max(newFader, -15), 15)
        balance = min(max(newBalance, -15), 15)
        let fByte = UInt8(clamping: fader + 15)
        let bByte = UInt8(clamping: balance + 15)
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setFadBal,
            payload: [fByte, bByte]
        )
    }

    func setSubwooferEnabled(_ enabled: Bool) {
        subwooferEnabled = enabled
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setSWSet,
            payload: [enabled ? 0x01 : 0x00]
        )
    }

    func setSubwooferLevel(_ level: Int) {
        subwooferLevel = min(max(level, -15), 10)
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setSWLevel,
            payload: [UInt8(clamping: subwooferLevel + 15)]
        )
    }

    func setSubwooferPhase(reversed: Bool) {
        subwooferPhaseReversed = reversed
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setSWPhase,
            payload: [reversed ? 0x01 : 0x00]
        )
    }

    func setBassBoost(_ level: Int) {
        bassBoost = min(max(level, 0), 5)
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setBassBoost,
            payload: [UInt8(bassBoost)]
        )
    }

    func setBassExtend(_ enabled: Bool) {
        bassExtend = enabled
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setBassExt,
            payload: [enabled ? 0x01 : 0x00]
        )
    }

    func setLoudness(_ level: Int) {
        loudness = min(max(level, 0), 2)
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setLoudness,
            payload: [UInt8(loudness)]
        )
    }

    func setListeningPosition(_ pos: KenwoodListeningPosition) {
        listeningPosition = pos
        sendDTA()
    }

    func updateDTADistance(channel: Int, cm: Int) {
        guard dtaDistancesCm.indices.contains(channel) else { return }
        dtaDistancesCm[channel] = min(max(cm, 0), 610)
        sendDTA()
    }

    private func sendDTA() {
        var payload: [UInt8] = [UInt8(listeningPosition.rawValue)]
        for cm in dtaDistancesCm {
            payload.append(UInt8((cm >> 8) & 0xFF))
            payload.append(UInt8(cm & 0xFF))
        }
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setDTA,
            payload: payload
        )
    }

    func updateCrossover(frontHPF: Int, rearHPF: Int, subLPF: Int, slopeIdx: Int) {
        frontHPFIndex = min(max(frontHPF, 0), Self.crossoverFrequencies.count - 1)
        rearHPFIndex = min(max(rearHPF, 0), Self.crossoverFrequencies.count - 1)
        subLPFIndex = min(max(subLPF, 0), Self.crossoverFrequencies.count - 1)
        xoverSlopeIndex = min(max(slopeIdx, 0), Self.crossoverSlopes.count - 1)

        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setXover,
            payload: [UInt8(frontHPFIndex), UInt8(rearHPFIndex), UInt8(subLPFIndex), UInt8(xoverSlopeIndex)]
        )
    }

    func setCarType(_ type: KenwoodCarType) {
        carType = type
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setCarType,
            payload: [UInt8(type.rawValue)]
        )
    }

    // MARK: - Подсветка и сервисные функции

    func selectColorPreset(_ preset: KenwoodColorPreset) {
        selectedColorPresetId = preset.id
        customRed = preset.r
        customGreen = preset.g
        customBlue = preset.b
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setPresetColor,
            payload: [UInt8(preset.id), UInt8(preset.r), UInt8(preset.g), UInt8(preset.b)]
        )
    }

    func applyCustomRGB(r: Int, g: Int, b: Int) {
        customRed = min(max(r, 0), 31)
        customGreen = min(max(g, 0), 31)
        customBlue = min(max(b, 0), 31)
        selectedColorPresetId = 23
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestSetting,
            cmd: KenwoodOpenLink.SettingCmd.setPresetColor,
            payload: [23, UInt8(customRed), UInt8(customGreen), UInt8(customBlue)]
        )
    }

    func syncClockAndDate() {
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let hour = UInt8(comps.hour ?? 0)
        let minute = UInt8(comps.minute ?? 0)
        let second = UInt8(comps.second ?? 0)
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestCmd,
            cmd: 0x35,
            payload: [hour, minute, second, 0x00]
        )
        let year = UInt16(comps.year ?? 2026)
        let month = UInt8(comps.month ?? 1)
        let day = UInt8(comps.day ?? 1)
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestCmd,
            cmd: 0x37,
            payload: [UInt8((year >> 8) & 0xFF), UInt8(year & 0xFF), month, day]
        )
        statusText = isConnected ? "Часы и дата синхронизированы с магнитолой" : "Команда синхронизации подготовлена"
    }

    func switchBTAudioDevice() {
        sendPacket(
            addr: KenwoodOpenLink.Address.main,
            cat: KenwoodOpenLink.Category.requestCmd,
            cmd: 0x33,
            payload: [0x01]
        )
    }

    // MARK: - Низкоуровневая отправка и приём кадров OpenLink

    private func nextSeq() -> UInt8 {
        let s = txSeqNum
        txSeqNum = txSeqNum == 255 ? 1 : txSeqNum + 1
        return s
    }

    private func sendPacket(
        addr: UInt8,
        cat: UInt8,
        cmd: UInt8,
        payloadType: UInt8 = KenwoodOpenLink.PayloadType.general,
        payload: [UInt8] = []
    ) {
        let frame = KenwoodOpenLink.buildFrame(
            destAddr: addr,
            category: cat,
            command: cmd,
            seqNum: nextSeq(),
            payloadType: payloadType,
            payload: payload
        )
        writeRawData(frame)
    }

    private func writeRawData(_ data: Data) {
        // 1. MFi ExternalAccessory OutputStream
        if let outStream = eaSession?.outputStream, outStream.hasSpaceAvailable {
            data.withUnsafeBytes { rawBuf in
                if let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress {
                    _ = outStream.write(ptr, maxLength: data.count)
                }
            }
            return
        }

        // 2. CoreBluetooth BLE Characteristic
        if let peripheral = activeBLEPeripheral, let char = bleWriteCharacteristic {
            let writeType: CBCharacteristicWriteType = char.properties.contains(.writeWithoutResponse)
                ? .withoutResponse
                : .withResponse
            let mtu = max(peripheral.maximumWriteValueLength(for: writeType), 20)
            var offset = 0
            while offset < data.count {
                let end = min(offset + mtu, data.count)
                let chunk = data.subdata(in: offset..<end)
                peripheral.writeValue(chunk, for: char, type: writeType)
                offset = end
            }
        }
    }

    private func handleIncomingBytes(_ bytes: [UInt8]) {
        for b in bytes {
            if b == KenwoodOpenLink.frameStart {
                rxAccumulator.removeAll(keepingCapacity: true)
                inFrame = true
            } else if b == KenwoodOpenLink.frameEnd, inFrame {
                inFrame = false
                if let packet = KenwoodOpenLink.parseFrameContent(rxAccumulator) {
                    processIncomingPacket(packet)
                }
                rxAccumulator.removeAll(keepingCapacity: true)
            } else if inFrame {
                if rxAccumulator.count < 2048 {
                    rxAccumulator.append(b)
                } else {
                    inFrame = false
                    rxAccumulator.removeAll(keepingCapacity: true)
                }
            }
        }
    }

    private func processIncomingPacket(_ packet: OpenLinkPacket) {
        // На любой не-ACK пакет сразу отвечаем ACK (как в DataProcessTask)
        if packet.payloadType != KenwoodOpenLink.PayloadType.ack {
            let ack = KenwoodOpenLink.buildAckFrame(for: packet)
            writeRawData(ack)
        } else {
            return
        }

        guard packet.sourceAddr == KenwoodOpenLink.Address.main || packet.destAddr == KenwoodOpenLink.sourceAddressApp else {
            return
        }

        let payload = packet.payload
        switch packet.command {
        case KenwoodOpenLink.MainNotify.sourceChanged:
            if payload.count >= 2, let src = KenwoodSource.from(category: payload[0], type: payload[1]) {
                currentSource = src
            }
        case KenwoodOpenLink.MainNotify.volumeChanged:
            if let v = payload.first {
                volume = min(max(Int(v), 0), 35)
            }
        case KenwoodOpenLink.MainNotify.muteChanged:
            if let m = payload.first {
                isMuted = (m != 0)
            }
        case KenwoodOpenLink.MainNotify.presetEQChanged:
            if let idx = payload.first, let preset = KenwoodEQPreset(rawValue: Int(idx)) {
                selectedEQPreset = preset
            }
        case KenwoodOpenLink.MainNotify.titleInfo, KenwoodOpenLink.MainNotify.radioTitleInfo:
            if let text = decodeOpenLinkString(payload), !text.isEmpty {
                trackTitle = text
            }
        case KenwoodOpenLink.MainNotify.artistInfo, KenwoodOpenLink.MainNotify.radioArtistInfo:
            if let text = decodeOpenLinkString(payload), !text.isEmpty {
                trackArtist = text
            }
        case KenwoodOpenLink.MainNotify.albumInfo, KenwoodOpenLink.MainNotify.radioAlbumInfo:
            if let text = decodeOpenLinkString(payload) {
                trackAlbum = text
            }
        case KenwoodOpenLink.MainNotify.radioFreqInfo:
            if let text = decodeOpenLinkString(payload), !text.isEmpty {
                tunerFrequency = text
            } else if payload.count >= 2 {
                let rawFreq = (Int(payload[0]) << 8) | Int(payload[1])
                if rawFreq >= 7000 && rawFreq <= 11000 {
                    tunerFrequency = String(format: "%.1f MHz", Double(rawFreq) / 100.0)
                } else if rawFreq > 500 {
                    tunerFrequency = "\(rawFreq) kHz"
                }
            }
        case KenwoodOpenLink.MainNotify.radioStationInfo:
            if let text = decodeOpenLinkString(payload), !text.isEmpty {
                tunerStation = text
            }
        case KenwoodOpenLink.MainNotify.firmwareVersion:
            if let text = decodeOpenLinkString(payload), !text.isEmpty {
                firmwareVersion = text
            }
        default:
            break
        }
    }

    private func decodeOpenLinkString(_ bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty else { return nil }
        let trimmed = bytes.filter { $0 != 0 }
        return String(bytes: trimmed, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - MFi ExternalAccessory (Bluetooth iAP2 / USB)

    private func scanExternalAccessories() {
        eaAccessories.removeAll()
        let connected = EAAccessoryManager.shared().connectedAccessories
        for acc in connected {
            let matchingProto = acc.protocolStrings.first(where: { KenwoodOpenLink.supportedEAProtocols.contains($0) })
            let nameLower = "\(acc.name) \(acc.manufacturer)".lowercased()
            let isKenwoodBrand = nameLower.contains("kenwood") || nameLower.contains("jvc") || nameLower.contains("kmm") || nameLower.contains("kdc") || nameLower.contains("dpx") || nameLower.contains("dmx") || nameLower.contains("ddx") || nameLower.contains("dnx")

            guard matchingProto != nil || isKenwoodBrand else { continue }
            let id = "ea-\(acc.connectionID)"
            eaAccessories[id] = acc

            let item = KenwoodDiscoveredDevice(
                id: id,
                name: acc.name.isEmpty ? "KENWOOD Receiver" : acc.name,
                transport: .mfiBluetooth,
                detail: acc.modelNumber.isEmpty ? "MFi OpenLink" : acc.modelNumber,
                protocolString: matchingProto ?? acc.protocolStrings.first
            )
            upsertDiscovered(item)

            // Автоподключение, если ещё не подключены
            if !isConnected, let proto = matchingProto {
                openEASession(accessory: acc, protocolString: proto)
            }
        }
    }

    @objc private func handleEAAccessoryConnected(_ notification: Notification) {
        scanExternalAccessories()
    }

    @objc private func handleEAAccessoryDisconnected(_ notification: Notification) {
        if let acc = notification.userInfo?[EAAccessoryKey] as? EAAccessory,
           eaSession?.accessory?.connectionID == acc.connectionID {
            disconnect()
        }
        scanExternalAccessories()
    }

    private func openEASession(accessory: EAAccessory, protocolString: String) {
        closeEASession()
        guard let session = EASession(accessory: accessory, forProtocol: protocolString) else {
            statusText = "Не удалось открыть MFi-сессию с \(accessory.name)"
            return
        }
        eaSession = session

        session.inputStream?.delegate = self
        session.inputStream?.schedule(in: .main, forMode: .common)
        session.inputStream?.open()

        session.outputStream?.delegate = self
        session.outputStream?.schedule(in: .main, forMode: .common)
        session.outputStream?.open()

        isConnected = true
        connectedDeviceName = accessory.name.isEmpty ? "KENWOOD" : accessory.name
        activeTransportLabel = "MFi Bluetooth / USB"
        statusText = "Подключено к \(connectedDeviceName ?? "KENWOOD")"
        performOpenLinkHandshake()
    }

    private func closeEASession() {
        eaSession?.inputStream?.close()
        eaSession?.inputStream?.remove(from: .main, forMode: .common)
        eaSession?.inputStream?.delegate = nil

        eaSession?.outputStream?.close()
        eaSession?.outputStream?.remove(from: .main, forMode: .common)
        eaSession?.outputStream?.delegate = nil

        eaSession = nil
    }

    // MARK: - CoreBluetooth BLE Scan

    private func startBLEScan() {
        guard let central = centralManager, central.state == .poweredOn else { return }
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            self?.stopScanning()
        }
    }

    private func upsertDiscovered(_ device: KenwoodDiscoveredDevice) {
        if let idx = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[idx] = device
        } else {
            discoveredDevices.append(device)
        }
    }
}

// MARK: - StreamDelegate (ExternalAccessory Input/Output)

extension KenwoodRemoteManager: StreamDelegate {
    nonisolated func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch eventCode {
            case .hasBytesAvailable:
                guard let input = aStream as? InputStream else { return }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while input.hasBytesAvailable {
                    let count = input.read(&buffer, maxLength: buffer.count)
                    if count > 0 {
                        self.handleIncomingBytes(Array(buffer[0..<count]))
                    } else {
                        break
                    }
                }
            case .errorOccurred, .endEncountered:
                self.disconnect()
            default:
                break
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate & CBPeripheralDelegate (BLE)

extension KenwoodRemoteManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch central.state {
            case .poweredOn:
                self.bluetoothStateText = nil
                self.startBLEScan()
            case .poweredOff:
                self.bluetoothStateText = "Включите Bluetooth на iPhone"
                self.isScanning = false
            case .unauthorized:
                self.bluetoothStateText = "Разрешите доступ к Bluetooth в настройках iOS"
                self.isScanning = false
            default:
                self.bluetoothStateText = nil
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let hasKenwoodUUID = serviceUUIDs.contains { uuid in
            let s = uuid.uuidString.uppercased()
            return s == KenwoodOpenLink.openLinkServiceUUID
                || s == KenwoodOpenLink.tccServiceUUID
                || s == KenwoodOpenLink.altServiceUUID
        }

        let lower = advName.lowercased()
        let matchesName = lower.contains("kenwood")
            || lower.contains("kmm")
            || lower.contains("kdc")
            || lower.contains("dpx")
            || lower.contains("dmx")
            || lower.contains("ddx")
            || lower.contains("dnx")
            || lower.contains("jvc")
            || lower.contains("openlink")

        guard hasKenwoodUUID || matchesName else { return }
        let id = "ble-\(peripheral.identifier.uuidString)"
        let displayName = advName.isEmpty ? "KENWOOD BLE" : advName

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.blePeripherals[id] = peripheral
            self.upsertDiscovered(
                KenwoodDiscoveredDevice(
                    id: id,
                    name: displayName,
                    transport: .ble,
                    detail: "RSSI \(RSSI.intValue) dBm",
                    protocolString: nil
                )
            )
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connectedDeviceName = peripheral.name ?? "KENWOOD BLE"
            self.activeTransportLabel = "Bluetooth LE"
            self.statusText = "Обнаружение сервисов \(self.connectedDeviceName ?? "KENWOOD")…"
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor [weak self] in
            self?.disconnect(silent: true)
            self?.statusText = "Не удалось подключиться по Bluetooth LE"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor [weak self] in
            self?.disconnect()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for char in chars {
                if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: char)
                }
                if self.bleWriteCharacteristic == nil && (char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse)) {
                    self.bleWriteCharacteristic = char
                }
            }
            if self.bleWriteCharacteristic != nil && !self.isConnected {
                self.isConnected = true
                self.statusText = "Подключено к \(self.connectedDeviceName ?? "KENWOOD")"
                self.performOpenLinkHandshake()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value, !value.isEmpty else { return }
        let bytes = Array(value)
        Task { @MainActor [weak self] in
            self?.handleIncomingBytes(bytes)
        }
    }
}
