import SwiftUI
import UIKit

enum CenterPadMode: String, CaseIterable, Identifiable {
    case dpad
    case gestures
    case airMouse
    case trackpad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dpad: return "Кнопки"
        case .gestures: return "Жесты"
        case .airMouse: return "Аэромышь"
        case .trackpad: return "Курсор"
        }
    }

    /// Иконки в круглой кнопке переключения режима справа сверху (как на референсах)
    var symbol: String {
        switch self {
        case .dpad: return "appletvremote.gen2"
        case .gestures: return "arrow.up.and.down.and.arrow.left.and.right"
        case .airMouse: return "gyroscope"
        case .trackpad: return "scribble.variable"
        }
    }

    var wireMode: GamepadWire.ControllerMode {
        switch self {
        case .dpad: return .circleDPad
        case .gestures: return .touchpad
        case .trackpad: return .mouseTrackpad
        case .airMouse: return .airMousePointer
        }
    }
}

enum TextSheetMode: String, CaseIterable, Identifiable {
    case globalSearch
    case keyboardInput

    var id: String { rawValue }

    var title: String {
        switch self {
        case .globalSearch: return "Поиск по ТВ"
        case .keyboardInput: return "Ввод текста"
        }
    }
}

enum AppSection {
    case home
    case tvRemote
    case kenwood
    case servers
}

private enum SuperAppCardTheme {
    case sber
    case kenwood
    case server
}

struct ContentView: View {
    @StateObject private var remote = UniversalTVRemoteManager()
    @StateObject private var kenwood = KenwoodRemoteManager()
    @StateObject private var serverManager = ServerManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var section: AppSection = .home

    var body: some View {
        ZStack {
            NativeDarkBackdrop()

            switch section {
            case .home:
                SuperAppHomeView(
                    remote: remote,
                    kenwood: kenwood,
                    serverManager: serverManager,
                    onOpenTVRemote: {
                        Haptics.medium()
                        remote.resume()
                        withAnimation(NativeLiquidSpring.morph) {
                            section = .tvRemote
                        }
                    },
                    onOpenKenwood: {
                        Haptics.medium()
                        kenwood.start()
                        withAnimation(NativeLiquidSpring.morph) {
                            section = .kenwood
                        }
                    },
                    onOpenServers: {
                        Haptics.medium()
                        serverManager.startMonitoring()
                        withAnimation(NativeLiquidSpring.morph) {
                            section = .servers
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

            case .tvRemote:
                Group {
                    if remote.isShowingRemotePad {
                        RemotePadView(remote: remote) {
                            remote.pause()
                            withAnimation(NativeLiquidSpring.morph) {
                                section = .home
                            }
                        }
                    } else {
                        TVHubConnectionView(remote: remote, isPresentedAsSheet: false) {
                            remote.pause()
                            withAnimation(NativeLiquidSpring.morph) {
                                section = .home
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

            case .kenwood:
                KenwoodRemoteView(kenwood: kenwood) {
                    kenwood.stopScanning()
                    withAnimation(NativeLiquidSpring.morph) {
                        section = .home
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

            case .servers:
                ServerHubView(manager: serverManager) {
                    serverManager.stopNetworkScan()
                    withAnimation(NativeLiquidSpring.morph) {
                        section = .home
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(
            get: { remote.needsPin },
            set: { if !$0 && remote.needsPin { remote.cancelPin() } }
        )) {
            PinSheet(remote: remote)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                if section == .tvRemote {
                    remote.resume()
                } else if section == .servers {
                    serverManager.refreshNetworkRoute()
                }
            case .background:
                if section == .tvRemote {
                    remote.pause()
                }
                serverManager.stopNetworkScan()
                serverManager.lockIfRequired()
            default:
                break
            }
        }
    }
}

// MARK: - Главное первое меню супераппа (Пульт ТВ / Магнитола Kenwood / Серверы Dell и iRU)

struct SuperAppHomeView: View {
    @ObservedObject var remote: UniversalTVRemoteManager
    @ObservedObject var kenwood: KenwoodRemoteManager
    @ObservedObject var serverManager: ServerManager
    let onOpenTVRemote: () -> Void
    let onOpenKenwood: () -> Void
    let onOpenServers: () -> Void

    private var tvSubtitle: String {
        if remote.isShowingRemotePad {
            let state = remote.isChannelReady ? "Пульт готов" : remote.statusText
            return "\(remote.activeDeviceName) · \(remote.activePlatform.shortBadge) · \(state)"
        }
        if !remote.savedTVs.isEmpty {
            return "Телевизоров: \(remote.savedTVs.count) · Сбер Салют · Android TV · YaOS"
        }
        if !remote.discoveredTVs.isEmpty {
            return "Найдено ТВ: \(remote.discoveredTVs.count)"
        }
        return "Сбер Салют · Android TV / Google TV · YaOS"
    }

    private var tvBadgeText: String? {
        if remote.isShowingRemotePad && remote.isChannelReady {
            return remote.activePlatform.shortBadge
        }
        if !remote.savedTVs.isEmpty {
            return "\(remote.savedTVs.count) ТВ"
        }
        return nil
    }

    private var kenwoodSubtitle: String {
        if kenwood.isConnected {
            return "\(kenwood.connectedDeviceName ?? "Kenwood") · \(kenwood.currentSource.title) · VOL \(kenwood.volume)"
        }
        if !kenwood.discoveredDevices.isEmpty {
            return "Найдено устройств: \(kenwood.discoveredDevices.count)"
        }
        if let audioName = kenwood.connectedBluetoothAudioName {
            return "Bluetooth Audio: \(audioName)"
        }
        return "Плеер · 13-band EQ · DSP · DTA · Подсветка"
    }

    private var serversSubtitle: String {
        let count = serverManager.servers.count
        if count > 0 {
            let online = serverManager.onlineCount
            if online > 0 {
                return "Онлайн: \(online) из \(count) · \(serverManager.networkRoute.shortBadge)"
            }
            if serverManager.isMonitoring {
                return "Серверов: \(count) · \(serverManager.networkRoute.title)"
            }
            return "Сохранённых серверов: \(count) · Dell iDRAC / iRU BMC"
        }
        return "Панели Dell iDRAC и iRU BMC · LAN / Kerio VPN"
    }

    private var serversBadgeText: String? {
        guard serverManager.isMonitoring else {
            return serverManager.servers.isEmpty ? nil : "\(serverManager.servers.count)"
        }
        switch serverManager.networkRoute {
        case .vpnAndWiFi, .vpnOnly:
            return "VPN"
        case .localWiFi:
            return serverManager.onlineCount > 0 ? "Онлайн \(serverManager.onlineCount)" : "LAN"
        default:
            return nil
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                Spacer(minLength: 14)

                VStack(spacing: 12) {
                    RemoteAMonogramEmblem()
                        .frame(width: 78, height: 78)
                        .nativeLiquidGlass(
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                            interactive: true
                        )

                    Text("RemoteA")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Выберите раздел управления")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.56))
                }

                NativeGlassContainer(spacing: 14) {
                    VStack(spacing: 14) {
                        SuperAppMenuCard(
                            symbol: "tv.fill",
                            title: "Пульт ТВ",
                            subtitle: tvSubtitle,
                            badgeText: tvBadgeText,
                            badgeActive: remote.isShowingRemotePad && remote.isChannelReady,
                            accentIcon: true,
                            theme: .sber,
                            action: onOpenTVRemote
                        )

                        SuperAppMenuCard(
                            symbol: "car.fill",
                            title: "Магнитола KENWOOD",
                            subtitle: kenwoodSubtitle,
                            badgeText: kenwood.isConnected ? "Подключено" : nil,
                            badgeActive: kenwood.isConnected,
                            accentIcon: true,
                            theme: .kenwood,
                            action: onOpenKenwood
                        )

                        SuperAppMenuCard(
                            symbol: "server.rack",
                            title: "Серверы Dell / iRU",
                            subtitle: serversSubtitle,
                            badgeText: serversBadgeText,
                            badgeActive: serverManager.isMonitoring && serverManager.networkRoute.isReadyForLAN,
                            accentIcon: true,
                            theme: .server,
                            action: onOpenServers
                        )
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

/// Минималистичная эмблема RemoteA (перекликается с иконкой приложения: буква A, центральная кнопка и дуга сигнала).
private struct RemoteAMonogramEmblem: View {
    var body: some View {
        ZStack {
            // Тонкая дуга беспроводного сигнала над вершиной
            Circle()
                .trim(from: 0.67, to: 0.83)
                .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 48, height: 48)
                .offset(y: -4)

            // Чистый геометрический силуэт A
            Text("A")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .offset(y: 4)

            // Минималистичная круглая точка-кнопка в центре перекладины
            Circle()
                .fill(.white)
                .frame(width: 7, height: 7)
                .offset(y: 12)
        }
        .accessibilityHidden(true)
    }
}

private struct SuperAppMenuCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let badgeText: String?
    let badgeActive: Bool
    let accentIcon: Bool
    var theme: SuperAppCardTheme = .sber
    let action: () -> Void

    private var accentColor: Color {
        switch theme {
        case .sber: return SberPalette.brightGreen
        case .kenwood: return KenwoodPalette.crimson
        case .server: return ServerPalette.dellBlue
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentIcon ? .white : .white.opacity(0.65))
                    .frame(width: 54, height: 54)
                    .nativeLiquidGlass(
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                        tint: accentIcon ? accentColor.opacity(0.55) : nil,
                        interactive: false
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        if let badgeText {
                            Text(badgeText)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(badgeActive ? 0.98 : 0.78))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .nativeLiquidGlass(
                                    in: Capsule(),
                                    tint: badgeActive ? accentColor.opacity(0.52) : nil,
                                    interactive: false
                                )
                        }
                    }

                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(16)
            .nativeLiquidGlass(
                in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                interactive: true
            )
        }
        .buttonStyle(RemotePressStyle())
    }
}

// MARK: - Универсальный экран пульта ТВ (дизайн по референсу, без кнопок сервисов)

struct RemotePadView: View {
    @ObservedObject var remote: UniversalTVRemoteManager
    let onBackToMenu: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var padMorphNamespace
    @AppStorage("SaluteRemotePlus.padMode") private var storedPadModeRaw = CenterPadMode.dpad.rawValue
    @AppStorage("SaluteRemotePlus.hardwareVolumeEnabled") private var hardwareVolumeEnabled = true
    @State private var showTextSheet = false
    @State private var showTVHubSheet = false

    private var isHardwareVolumeActive: Bool {
        hardwareVolumeEnabled
            && scenePhase == .active
            && remote.voiceState == .idle
            && !showTextSheet
            && !showTVHubSheet
            && !remote.needsPin
    }

    private var padMode: CenterPadMode {
        let candidate = CenterPadMode(rawValue: storedPadModeRaw) ?? .dpad
        return remote.availablePadModes.contains(candidate) ? candidate : .dpad
    }

    private func selectPadMode(_ next: CenterPadMode) {
        guard remote.availablePadModes.contains(next), next != padMode else { return }
        Haptics.medium()
        withAnimation(NativeLiquidSpring.morph) {
            storedPadModeRaw = next.rawValue
        }
        remote.setControllerMode(next.wireMode)
    }

    private func cyclePadMode() {
        let modes = remote.availablePadModes
        guard modes.count > 1 else { return }
        if let idx = modes.firstIndex(of: padMode) {
            selectPadMode(modes[(idx + 1) % modes.count])
        } else {
            selectPadMode(modes[0])
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let w = proxy.size.width
            let compact = h < 700
            let gridSpacing: CGFloat = 10
            let cellHeight: CGFloat = min(max(h * 0.072, 50), 62)

            VStack(spacing: compact ? 12 : 16) {
                // 1. Верхняя панель Liquid Glass: [Питание] [Имя ТВ ⌄]     [Режим] [Закрыть]
                NativeGlassContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        CircularPowerButton(
                            isActive: remote.isChannelReady,
                            onDown: { remote.sendDown(.power) },
                            onUp: { remote.sendUp(.power) }
                        )

                        Menu {
                            if !remote.savedTVs.isEmpty {
                                Section("Мои телевизоры") {
                                    ForEach(remote.savedTVs) { profile in
                                        Button {
                                            Haptics.tap()
                                            remote.switchToProfile(profile)
                                        } label: {
                                            if remote.activeProfile?.id == profile.id {
                                                Label("\(profile.name) (\(profile.platform.shortBadge))", systemImage: "checkmark")
                                            } else {
                                                Label("\(profile.name) (\(profile.platform.shortBadge))", systemImage: profile.platform.symbol)
                                            }
                                        }
                                    }
                                }
                            }

                            if !remote.isChannelReady {
                                Button {
                                    Haptics.tap()
                                    remote.reconnectActiveTV()
                                } label: {
                                    Label("Переподключить", systemImage: "arrow.clockwise")
                                }
                            }

                            if remote.activePlatform.supportsFindRemote {
                                Button {
                                    Haptics.tap()
                                    remote.findRemote()
                                } label: {
                                    Label("Найти физический пульт", systemImage: "dot.radiowaves.left.and.right")
                                }
                            }

                            Button {
                                Haptics.tap()
                                hardwareVolumeEnabled.toggle()
                            } label: {
                                Label(
                                    "Кнопки громкости iPhone",
                                    systemImage: hardwareVolumeEnabled ? "checkmark.circle.fill" : "circle"
                                )
                            }

                            Divider()

                            Button {
                                Haptics.tap()
                                showTVHubSheet = true
                            } label: {
                                Label("Все телевизоры / Добавить ТВ…", systemImage: "plus.circle")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(remote.activeDeviceName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .nativeLiquidGlass(in: Capsule(), interactive: true)
                        }

                        Spacer(minLength: 4)

                        // Кнопка переключения режима (тап — следующий режим, удержание — меню выбора)
                        Menu {
                            ForEach(remote.availablePadModes) { mode in
                                Button {
                                    selectPadMode(mode)
                                } label: {
                                    if mode == padMode {
                                        Label(mode.title, systemImage: "checkmark")
                                    } else {
                                        Label(mode.title, systemImage: mode.symbol)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: padMode.symbol)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                                .nativeSymbolReplaceTransition()
                                .frame(width: 44, height: 44)
                                .nativeLiquidGlass(in: Circle(), interactive: true)
                        } primaryAction: {
                            cyclePadMode()
                        }
                        .accessibilityLabel("Режим пульта: \(padMode.title)")

                        // Кнопка закрытия виртуального пульта (возврат в главное меню)
                        Button {
                            Haptics.tap()
                            onBackToMenu()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .nativeLiquidGlass(in: Circle(), interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())
                        .accessibilityLabel("Закрыть виртуальный пульт")
                    }
                }

                // 2. Строка поиска (без кнопок запуска сервисов) + компактный статус платформы
                NativeGlassContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap()
                            showTextSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Поиск")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 18)
                            .frame(height: 44)
                            .nativeLiquidGlass(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())

                        Spacer()

                        Button {
                            Haptics.tap()
                            if !remote.isChannelReady {
                                remote.reconnectActiveTV()
                            } else {
                                showTVHubSheet = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(remote.isChannelReady ? remote.activePlatform.accentColor : Color.orange)
                                    .frame(width: 7, height: 7)
                                Text(remote.isChannelReady ? remote.activePlatform.shortBadge : remote.statusText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.84))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 13)
                            .frame(height: 36)
                            .nativeLiquidGlass(
                                in: Capsule(),
                                tint: remote.isChannelReady ? remote.activePlatform.accentColor.opacity(0.22) : Color.orange.opacity(0.22),
                                interactive: true
                            )
                        }
                        .buttonStyle(RemotePressStyle())
                    }
                }

                // 3. Центральная область управления с нативным Liquid Glass морфингом режимов
                NativeGlassContainer(spacing: 16) {
                    ZStack {
                        switch padMode {
                        case .dpad:
                            ConcentricDPadRingView(
                                diameter: min(w - 64, max(h * 0.34, 224), 278),
                                onDown: { remote.sendDown($0) },
                                onUp: { remote.sendUp($0) }
                            )
                            .nativeGlassID("centerPad", in: padMorphNamespace)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))

                        case .gestures:
                            TouchpadSurfaceView(
                                onCommand: { remote.send($0) },
                                onDown: { remote.sendDown($0) },
                                onUp: { remote.sendUp($0) }
                            )
                            .nativeGlassID("centerPad", in: padMorphNamespace)
                            .transition(.scale(scale: 0.94).combined(with: .opacity))

                        case .airMouse:
                            AirMouseSurfaceView(
                                onMove: { dx, dy in remote.sendMouseOffset(dx: dx, dy: dy) },
                                onVerticalScroll: { remote.sendMouseVerticalScroll($0) },
                                onHorizontalScroll: { remote.sendMouseHorizontalScroll($0) },
                                onClickDown: { remote.sendDown(.mouseClick) },
                                onClickUp: { remote.sendUp(.mouseClick) }
                            )
                            .nativeGlassID("centerPad", in: padMorphNamespace)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))

                        case .trackpad:
                            TrackpadSurfaceView(
                                onMove: { dx, dy in remote.sendMouseOffset(dx: dx, dy: dy) },
                                onVerticalScroll: { remote.sendMouseVerticalScroll($0) },
                                onHorizontalScroll: { remote.sendMouseHorizontalScroll($0) },
                                onClick: { remote.send(.mouseClick) },
                                onClickDown: { remote.sendDown(.mouseClick) },
                                onClickUp: { remote.sendUp(.mouseClick) }
                            )
                            .nativeGlassID("centerPad", in: padMorphNamespace)
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(NativeLiquidSpring.morph, value: padMode)
                }

                // 4. Нижний блок кнопок 3×3 в нативном Liquid Glass (высокий «Назад», Ассистент, VOL+, VOL-, Домой, TV, Настройки, Mute)
                NativeGlassContainer(spacing: gridSpacing) {
                    HStack(spacing: gridSpacing) {
                        // Колонка 1: Высокая «Назад» (2 строки) + «Без звука» (1 строка)
                        VStack(spacing: gridSpacing) {
                            MinimalRemoteKeyButton(
                                height: cellHeight * 2 + gridSpacing,
                                accessibilityTitle: "Назад"
                            ) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 20, weight: .medium))
                            } action: {
                                send(.back)
                            }

                            MinimalRemoteKeyButton(
                                height: cellHeight,
                                accessibilityTitle: "Отключить звук"
                            ) {
                                Image(systemName: "speaker.slash")
                                    .font(.system(size: 20, weight: .regular))
                            } action: {
                                send(.mute)
                            }
                        }

                        // Колонка 2: Виртуальный ассистент + VOL + + VOL -
                        VStack(spacing: gridSpacing) {
                            MinimalRemoteKeyButton(
                                height: cellHeight,
                                highlighted: remote.voiceState != .idle,
                                highlightTint: remote.activePlatform.accentColor,
                                accessibilityTitle: "Виртуальный ассистент (\(remote.activePlatform.voiceTitle))"
                            ) {
                                AssistantGlyph(
                                    platform: remote.activePlatform,
                                    isListening: remote.voiceState != .idle
                                )
                            } action: {
                                Haptics.tap()
                                remote.toggleVoice()
                            }

                            MinimalHoldRemoteKeyButton(
                                height: cellHeight,
                                title: "VOL +",
                                onDown: { remote.sendDown(.volumeUp) },
                                onUp: { remote.sendUp(.volumeUp) }
                            )

                            MinimalHoldRemoteKeyButton(
                                height: cellHeight,
                                title: "VOL -",
                                onDown: { remote.sendDown(.volumeDown) },
                                onUp: { remote.sendUp(.volumeDown) }
                            )
                        }

                        // Колонка 3: Домой + TV + Настройки
                        VStack(spacing: gridSpacing) {
                            MinimalRemoteKeyButton(
                                height: cellHeight,
                                accessibilityTitle: "Домашний экран"
                            ) {
                                Image(systemName: "house")
                                    .font(.system(size: 20, weight: .regular))
                            } action: {
                                send(.home)
                            }

                            MinimalRemoteKeyButton(
                                height: cellHeight,
                                accessibilityTitle: "Телеканалы / Вход (удержание — Пауза/Плей)",
                                onLongPress: {
                                    Haptics.medium()
                                    remote.send(.playPause)
                                }
                            ) {
                                Text("TV")
                                    .font(.system(size: 17, weight: .semibold))
                            } action: {
                                send(.source)
                            }

                            MinimalRemoteKeyButton(
                                height: cellHeight,
                                accessibilityTitle: "Настройки"
                            ) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 20, weight: .regular))
                            } action: {
                                send(.settings)
                            }
                        }
                    }
                }

                // Ненавязчивая строка ошибки / уведомления (только если есть)
                if let msg = remote.errorText ?? remote.effectiveNotice {
                    Text(msg)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(remote.errorText != nil ? SberPalette.coral : Color.white.opacity(0.50))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, compact ? 10 : 14)
            .padding(.bottom, compact ? 12 : 18)
            .frame(width: w, height: h)
        }
        .onAppear {
            remote.setControllerMode(padMode.wireMode)
        }
        .onChange(of: remote.isChannelReady) { ready in
            if ready {
                remote.setControllerMode(padMode.wireMode)
            }
        }
        .onChange(of: remote.activePlatform) { _ in
            if let current = CenterPadMode(rawValue: storedPadModeRaw),
               !remote.availablePadModes.contains(current) {
                storedPadModeRaw = CenterPadMode.dpad.rawValue
            }
        }
        .sheet(isPresented: $showTextSheet) {
            TextInputSheet(remote: remote)
        }
        .sheet(isPresented: $showTVHubSheet) {
            TVHubConnectionView(remote: remote, isPresentedAsSheet: true) {
                showTVHubSheet = false
            }
        }
        .onHardwareVolumeButtons(
            isActive: isHardwareVolumeActive,
            onVolumeUp: { send(.volumeUp) },
            onVolumeDown: { send(.volumeDown) }
        )
    }

    private func send(_ command: RemoteCommand) {
        Haptics.tap()
        remote.send(command)
    }
}

// MARK: - Круглая кнопка питания слева сверху (как на референсе)

private struct CircularPowerButton: View {
    let isActive: Bool
    let onDown: () -> Void
    let onUp: () -> Void

    @GestureState private var gesturePressed = false
    @State private var isPressed = false
    @State private var isHolding = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: "power")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(isHolding ? .white : (isActive ? Color.black : Color.white))
            .frame(width: 44, height: 44)
            .nativeLiquidGlass(
                in: Circle(),
                tint: isHolding ? SberPalette.coral.opacity(0.88) : (isActive ? Color.white.opacity(0.92) : nil),
                interactive: true
            )
            .scaleEffect(isPressed ? 0.90 : 1.0)
            .animation(NativeLiquidSpring.press, value: isPressed)
            .animation(NativeLiquidSpring.press, value: isHolding)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($gesturePressed) { _, state, _ in
                        state = true
                    }
            )
        .onChange(of: gesturePressed) { active in
            if active { beginPress() } else { endPress() }
        }
        .onDisappear { endPress() }
        .accessibilityLabel("Включить или выключить телевизор")
    }

    private func beginPress() {
        guard !isPressed else { return }
        isPressed = true
        isHolding = false
        Haptics.tap()
        onDown()

        holdTask?.cancel()
        holdTask = Task {
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isPressed else { return }
                isHolding = true
                Haptics.heavy()
            }
        }
    }

    private func endPress() {
        holdTask?.cancel()
        holdTask = nil
        guard isPressed else { return }
        isPressed = false
        isHolding = false
        onUp()
    }
}

// MARK: - Концентрический круглый D-Pad (точный референс IMG_0141)

private struct ConcentricDPadRingView: View {
    let diameter: CGFloat
    let onDown: (RemoteCommand) -> Void
    let onUp: (RemoteCommand) -> Void

    @GestureState private var touchActive = false
    @State private var activeCommand: RemoteCommand?

    private var innerDiameter: CGFloat {
        diameter * 0.43
    }

    var body: some View {
        ZStack {
            // Подсветка нажатого сектора кольца
            if let active = activeCommand, active != .ok {
                dpadSectorHighlight(for: active)
            }

            // 4 белые стрелки на кольце
            VStack {
                Image(systemName: "chevron.up")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(activeCommand == .up ? Color.white : Color.white.opacity(0.90))
                    .scaleEffect(activeCommand == .up ? 1.14 : 1.0)
                    .padding(.top, diameter * 0.085)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(activeCommand == .down ? Color.white : Color.white.opacity(0.90))
                    .scaleEffect(activeCommand == .down ? 1.14 : 1.0)
                    .padding(.bottom, diameter * 0.085)
            }
            .animation(NativeLiquidSpring.press, value: activeCommand)

            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(activeCommand == .left ? Color.white : Color.white.opacity(0.90))
                    .scaleEffect(activeCommand == .left ? 1.14 : 1.0)
                    .padding(.leading, diameter * 0.085)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(activeCommand == .right ? Color.white : Color.white.opacity(0.90))
                    .scaleEffect(activeCommand == .right ? 1.14 : 1.0)
                    .padding(.trailing, diameter * 0.085)
            }
            .animation(NativeLiquidSpring.press, value: activeCommand)

            // Центральная кнопка OK в нативном Liquid Glass
            Text("OK")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: innerDiameter, height: innerDiameter)
                .nativeLiquidGlass(
                    in: Circle(),
                    tint: activeCommand == .ok ? Color.white.opacity(0.24) : Color.black.opacity(0.45),
                    interactive: true
                )
                .scaleEffect(activeCommand == .ok ? 0.92 : 1.0)
                .animation(NativeLiquidSpring.press, value: activeCommand == .ok)
        }
        .frame(width: diameter, height: diameter)
        .nativeLiquidGlass(in: Circle(), interactive: true)
        .scaleEffect(activeCommand != nil && activeCommand != .ok ? 0.985 : 1.0)
        .animation(NativeLiquidSpring.press, value: activeCommand)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($touchActive) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    if activeCommand == nil {
                        let cmd = resolveCommand(at: value.startLocation)
                        activeCommand = cmd
                        Haptics.tap()
                        onDown(cmd)
                    }
                }
                .onEnded { _ in
                    releaseActive()
                }
        )
        .onChange(of: touchActive) { active in
            if !active {
                releaseActive()
            }
        }
        .onDisappear {
            releaseActive()
        }
    }

    private func resolveCommand(at point: CGPoint) -> RemoteCommand {
        let center = CGPoint(x: diameter * 0.5, y: diameter * 0.5)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = hypot(dx, dy)
        if dist <= innerDiameter * 0.54 {
            return .ok
        }
        if abs(dx) >= abs(dy) {
            return dx > 0 ? .right : .left
        } else {
            return dy > 0 ? .down : .up
        }
    }

    private func releaseActive() {
        guard let cmd = activeCommand else { return }
        activeCommand = nil
        onUp(cmd)
    }

    @ViewBuilder
    private func dpadSectorHighlight(for command: RemoteCommand) -> some View {
        let offsetDist = diameter * 0.32
        let offset: CGSize = {
            switch command {
            case .up: return CGSize(width: 0, height: -offsetDist)
            case .down: return CGSize(width: 0, height: offsetDist)
            case .left: return CGSize(width: -offsetDist, height: 0)
            case .right: return CGSize(width: offsetDist, height: 0)
            default: return .zero
            }
        }()

        Circle()
            .fill(Color.white.opacity(0.11))
            .frame(width: diameter * 0.34, height: diameter * 0.34)
            .blur(radius: 10)
            .offset(offset)
            .allowsHitTesting(false)
    }
}

// MARK: - Минималистичные матовые кнопки нижней сетки 3×3

private struct MinimalRemoteKeyButton<LabelContent: View>: View {
    let height: CGFloat
    var highlighted: Bool = false
    var highlightTint: Color = SberPalette.brightGreen
    var accessibilityTitle: String = ""
    var onLongPress: (() -> Void)? = nil
    @ViewBuilder let label: () -> LabelContent
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
            label()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .nativeLiquidGlass(
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                    tint: highlighted ? highlightTint.opacity(0.52) : nil,
                    interactive: true
                )
        }
        .buttonStyle(RemotePressStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55)
                .onEnded { _ in
                    onLongPress?()
                }
        )
        .accessibilityLabel(accessibilityTitle)
    }
}

private struct MinimalHoldRemoteKeyButton: View {
    let height: CGFloat
    let title: String
    let onDown: () -> Void
    let onUp: () -> Void

    @GestureState private var gesturePressed = false
    @State private var isPressed = false

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .nativeLiquidGlass(
                in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                tint: isPressed ? Color.white.opacity(0.20) : nil,
                interactive: true
            )
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .animation(NativeLiquidSpring.press, value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($gesturePressed) { _, state, _ in
                        state = true
                    }
            )
            .onChange(of: gesturePressed) { active in
                if active {
                    guard !isPressed else { return }
                    isPressed = true
                    Haptics.tap()
                    onDown()
                } else {
                    guard isPressed else { return }
                    isPressed = false
                    onUp()
                }
            }
            .onDisappear {
                if isPressed {
                    isPressed = false
                    onUp()
                }
            }
            .accessibilityLabel(title)
    }
}

private struct AssistantGlyph: View {
    let platform: TVPlatform
    let isListening: Bool

    var body: some View {
        if isListening {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
        } else {
            switch platform {
            case .sberSalute:
                Image(systemName: "hurricane")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            case .androidTV:
                Image(systemName: "mic.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
            case .yaOS:
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Сенсорная панель жестов (точный референс IMG_0137)

enum TouchpadGesture {
    case tapOK
    case swipeUp
    case swipeDown
    case swipeLeft
    case swipeRight
    case circleHome
    case chevronBack

    var command: RemoteCommand {
        switch self {
        case .tapOK: return .ok
        case .swipeUp: return .up
        case .swipeDown: return .down
        case .swipeLeft: return .left
        case .swipeRight: return .right
        case .circleHome: return .home
        case .chevronBack: return .back
        }
    }

    var symbol: String {
        switch self {
        case .tapOK: return "checkmark.circle.fill"
        case .swipeUp: return "chevron.up"
        case .swipeDown: return "chevron.down"
        case .swipeLeft: return "chevron.left"
        case .swipeRight: return "chevron.right"
        case .circleHome: return "house.fill"
        case .chevronBack: return "arrow.uturn.backward"
        }
    }

    var label: String {
        switch self {
        case .tapOK: return "OK"
        case .swipeUp: return "Вверх"
        case .swipeDown: return "Вниз"
        case .swipeLeft: return "Влево"
        case .swipeRight: return "Вправо"
        case .circleHome: return "Домой"
        case .chevronBack: return "Назад"
        }
    }
}

enum TouchpadGestureRecognizer {
    static func recognize(_ points: [CGPoint]) -> TouchpadGesture? {
        guard let start = points.first, let end = points.last else { return nil }

        let totalLength = pathLength(points)
        let chord = distance(start, end)

        if totalLength < 20 && chord < 16 {
            return .tapOK
        }

        if isCircle(points, totalLength: totalLength, chord: chord) {
            return .circleHome
        }

        if isBackChevron(points, totalLength: totalLength) {
            return .chevronBack
        }

        guard chord >= 26 else { return nil }
        let dx = end.x - start.x
        let dy = end.y - start.y
        if abs(dx) >= abs(dy) {
            return dx > 0 ? .swipeRight : .swipeLeft
        } else {
            return dy > 0 ? .swipeDown : .swipeUp
        }
    }

    private static func isCircle(_ points: [CGPoint], totalLength: CGFloat, chord: CGFloat) -> Bool {
        guard points.count >= 8, totalLength >= 100 else { return false }

        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity
        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }

        let bw = maxX - minX
        let bh = maxY - minY
        guard bw >= 36, bh >= 36 else { return false }
        let maxDim = max(bw, bh)
        let minDim = min(bw, bh)
        guard minDim / maxDim >= 0.42 else { return false }

        let center = CGPoint(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5)
        var radii: [CGFloat] = []
        radii.reserveCapacity(points.count)
        var totalAngle: CGFloat = 0

        var prevVec: CGPoint?
        for p in points {
            let vx = p.x - center.x
            let vy = p.y - center.y
            let r = hypot(vx, vy)
            radii.append(r)
            guard r >= 6 else { continue }
            if let prev = prevVec {
                let cross = prev.x * vy - prev.y * vx
                let dot = prev.x * vx + prev.y * vy
                totalAngle += atan2(cross, dot)
            }
            prevVec = CGPoint(x: vx, y: vy)
        }

        let absAngle = abs(totalAngle)
        guard absAngle >= 4.2 else { return false }
        guard chord <= maxDim * 0.80 || absAngle >= 5.2 else { return false }

        let avgR = radii.reduce(0, +) / CGFloat(max(radii.count, 1))
        guard avgR >= 18 else { return false }
        let perimeterHits = radii.filter { $0 >= avgR * 0.30 }.count
        return Double(perimeterHits) / Double(radii.count) >= 0.72
    }

    private static func isBackChevron(_ points: [CGPoint], totalLength: CGFloat) -> Bool {
        guard points.count >= 3, totalLength >= 60,
              let start = points.first, let end = points.last else { return false }

        var apexIndex = 0
        var minX = points[0].x
        for i in 1..<points.count {
            if points[i].x < minX {
                minX = points[i].x
                apexIndex = i
            }
        }

        guard apexIndex > 0, apexIndex < points.count - 1 else { return false }
        let apex = points[apexIndex]

        let dx1 = apex.x - start.x
        let dy1 = apex.y - start.y
        guard dx1 <= -24, dy1 >= 10 else { return false }

        let dx2 = end.x - apex.x
        let dy2 = end.y - apex.y
        guard dx2 >= 24, dy2 >= 10 else { return false }

        guard (end.y - start.y) >= 32 else { return false }

        let leg1Len = pathLength(Array(points[0...apexIndex]))
        let leg2Len = pathLength(Array(points[apexIndex..<points.count]))
        let chord1 = hypot(dx1, dy1)
        let chord2 = hypot(dx2, dy2)
        guard leg1Len >= 26, leg2Len >= 26 else { return false }
        guard leg1Len / max(chord1, 1) <= 1.45, leg2Len / max(chord2, 1) <= 1.45 else { return false }

        return true
    }

    static func recognizeHold(_ points: [CGPoint]) -> TouchpadGesture? {
        guard let start = points.first, let end = points.last else { return nil }
        let totalLength = pathLength(points)
        let chord = distance(start, end)

        if totalLength < 20 && chord < 18 {
            return .tapOK
        }

        guard chord >= 34, totalLength / max(chord, 1) <= 1.35 else { return nil }
        let dx = end.x - start.x
        let dy = end.y - start.y
        if abs(dx) >= abs(dy) {
            return dx > 0 ? .swipeRight : .swipeLeft
        } else {
            return dy > 0 ? .swipeDown : .swipeUp
        }
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var sum: CGFloat = 0
        for i in 1..<points.count {
            sum += distance(points[i - 1], points[i])
        }
        return sum
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }
}

struct TouchpadSurfaceView: View {
    let onCommand: (RemoteCommand) -> Void
    let onDown: (RemoteCommand) -> Void
    let onUp: (RemoteCommand) -> Void

    @GestureState private var touchActive = false
    @State private var trail: [CGPoint] = []
    @State private var dwellAnchor: CGPoint?
    @State private var dwellTask: Task<Void, Never>?
    @State private var activeHold: TouchpadGesture?
    @State private var holdConsumedGesture = false
    @State private var gestureEndedNormally = false
    @State private var feedback: TouchpadGesture?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Крупные приглушённые стрелки по 4 сторонам
            VStack {
                Image(systemName: "chevron.up")
                    .font(.system(size: 32, weight: .ultraLight))
                    .padding(.top, 26)
                Spacer()
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 32, weight: .ultraLight))
                        .padding(.leading, 22)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 32, weight: .ultraLight))
                        .padding(.trailing, 22)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 32, weight: .ultraLight))
                    .padding(.bottom, 26)
            }
            .foregroundStyle(Color.white.opacity(0.24))
            .allowsHitTesting(false)

            if let hold = activeHold {
                VStack(spacing: 6) {
                    Image(systemName: hold.symbol)
                        .font(.system(size: 28, weight: .bold))
                    Text("\(hold.label) · удержание")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .nativeLiquidGlass(
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                    tint: Color.white.opacity(0.18)
                )
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            } else if let feedback {
                VStack(spacing: 6) {
                    Image(systemName: feedback.symbol)
                        .font(.system(size: 28, weight: .bold))
                    Text(feedback.label)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .nativeLiquidGlass(
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                    tint: Color.white.opacity(0.14)
                )
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            } else if trail.isEmpty {
                Text("Смахивайте для\nперехода по пунктам\nменю")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.36))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 54)
                    .allowsHitTesting(false)
            }

            if trail.count >= 2 && activeHold == nil {
                Path { path in
                    path.move(to: trail[0])
                    for point in trail.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    Color.white.opacity(0.45),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nativeLiquidGlass(
            in: RoundedRectangle(cornerRadius: 32, style: .continuous),
            interactive: true
        )
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($touchActive) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    if activeHold != nil || holdConsumedGesture { return }

                    let isFirst = trail.isEmpty
                    if isFirst {
                        gestureEndedNormally = false
                        holdConsumedGesture = false
                        trail.append(value.startLocation)
                        dwellAnchor = value.startLocation
                        scheduleDwellHold(delayNs: 380_000_000)
                    }

                    if let last = trail.last, hypot(value.location.x - last.x, value.location.y - last.y) >= 3 {
                        trail.append(value.location)
                    }

                    if let anchor = dwellAnchor,
                       hypot(value.location.x - anchor.x, value.location.y - anchor.y) >= 10 {
                        dwellAnchor = value.location
                        let totalDist = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
                        let delayNs: UInt64 = totalDist >= 34 ? 260_000_000 : 380_000_000
                        scheduleDwellHold(delayNs: delayNs)
                    }
                }
                .onEnded { value in
                    gestureEndedNormally = true
                    dwellTask?.cancel()
                    dwellTask = nil
                    dwellAnchor = nil

                    if holdConsumedGesture || activeHold != nil {
                        holdConsumedGesture = false
                        trail = []
                        releaseActiveHold()
                        return
                    }

                    if trail.isEmpty {
                        trail = [value.startLocation, value.location]
                    } else {
                        trail.append(value.location)
                    }
                    let captured = trail
                    trail = []

                    if let gesture = TouchpadGestureRecognizer.recognize(captured) {
                        if gesture == .circleHome || gesture == .chevronBack {
                            Haptics.medium()
                        } else {
                            Haptics.tap()
                        }
                        onCommand(gesture.command)
                        showFeedback(gesture)
                    }
                }
        )
        .onChange(of: touchActive) { active in
            if !active {
                dwellTask?.cancel()
                dwellTask = nil
                releaseActiveHold()
                DispatchQueue.main.async {
                    if !touchActive && !gestureEndedNormally {
                        dwellAnchor = nil
                        holdConsumedGesture = false
                        trail = []
                    }
                }
            }
        }
        .onDisappear {
            dwellTask?.cancel()
            dwellTask = nil
            dwellAnchor = nil
            holdConsumedGesture = false
            trail = []
            releaseActiveHold()
        }
    }

    private func scheduleDwellHold(delayNs: UInt64) {
        dwellTask?.cancel()
        dwellTask = Task {
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard activeHold == nil, !holdConsumedGesture, !trail.isEmpty else { return }
                if let holdGesture = TouchpadGestureRecognizer.recognizeHold(trail) {
                    holdConsumedGesture = true
                    feedbackTask?.cancel()
                    feedback = nil
                    Haptics.medium()
                    withAnimation(NativeLiquidSpring.press) {
                        activeHold = holdGesture
                    }
                    onDown(holdGesture.command)
                }
            }
        }
    }

    private func releaseActiveHold() {
        guard let hold = activeHold else { return }
        withAnimation(NativeLiquidSpring.release) {
            activeHold = nil
        }
        onUp(hold.command)
    }

    private func showFeedback(_ gesture: TouchpadGesture) {
        feedbackTask?.cancel()
        withAnimation(NativeLiquidSpring.press) {
            feedback = gesture
        }
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(NativeLiquidSpring.release) {
                    feedback = nil
                }
            }
        }
    }
}

// MARK: - Компактная панель ввода текста и поиска (референс IMG_0140)

struct TextInputSheet: View {
    @ObservedObject var remote: UniversalTVRemoteManager
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NativeGlassContainer(spacing: 10) {
            VStack(spacing: 14) {
                // Главная строка ввода с кнопками ▲ и ▼ справа в нативном Liquid Glass
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Поиск или ввод текста…", text: $text)
                            .focused($focused)
                            .submitLabel(.search)
                            .foregroundStyle(.white)
                            .onSubmit {
                                runSearch()
                            }

                        if !text.isEmpty {
                            Button {
                                text = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .nativeLiquidGlass(
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                        interactive: true
                    )

                    Button {
                        Haptics.tap()
                        remote.send(.up)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .nativeLiquidGlass(
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                                interactive: true
                            )
                    }
                    .buttonStyle(RemotePressStyle())
                    .accessibilityLabel("Вверх")

                    Button {
                        Haptics.tap()
                        remote.send(.down)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .nativeLiquidGlass(
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                                interactive: true
                            )
                    }
                    .buttonStyle(RemotePressStyle())
                    .accessibilityLabel("Вниз")
                }

                // Быстрые действия: Найти / Ввести / YouTube / Стереть / Enter
                HStack(spacing: 8) {
                    Button {
                        runSearch()
                    } label: {
                        Label("Найти", systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(trimmedText.isEmpty ? .white.opacity(0.4) : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .nativeLiquidGlass(
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                tint: trimmedText.isEmpty ? nil : Color.white.opacity(0.92),
                                interactive: !trimmedText.isEmpty
                            )
                    }
                    .buttonStyle(RemotePressStyle())
                    .disabled(trimmedText.isEmpty)

                    Button {
                        sendText(submit: true)
                    } label: {
                        Text("Ввести")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(text.isEmpty ? 0.4 : 0.95))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .nativeLiquidGlass(
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                interactive: !text.isEmpty
                            )
                    }
                    .buttonStyle(RemotePressStyle())
                    .disabled(text.isEmpty)

                    Button {
                        Haptics.tap()
                        remote.youtubeSearch(trimmedText)
                        dismiss()
                    } label: {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(trimmedText.isEmpty ? 0.35 : 0.92))
                            .frame(width: 48, height: 44)
                            .nativeLiquidGlass(
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                interactive: !trimmedText.isEmpty
                            )
                    }
                    .buttonStyle(RemotePressStyle())
                    .disabled(trimmedText.isEmpty)
                    .accessibilityLabel("Искать на YouTube")

                    Button {
                        Haptics.tap()
                        remote.sendKey(KeyMap.backspace)
                    } label: {
                        Image(systemName: "delete.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 48, height: 44)
                            .nativeLiquidGlass(
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                interactive: true
                            )
                    }
                    .buttonStyle(RemotePressStyle())
                    .accessibilityLabel("Стереть")

                    Button {
                        Haptics.tap()
                        remote.sendKey(KeyMap.enter)
                    } label: {
                        Image(systemName: "return")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 48, height: 44)
                            .nativeLiquidGlass(
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                interactive: true
                            )
                    }
                    .buttonStyle(RemotePressStyle())
                    .accessibilityLabel("Enter")
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
        .nativeGlassSheetContainerBackground()
        .preferredColorScheme(.dark)
        .modifier(CompactSearchSheetDetentModifier())
        .onAppear {
            focused = true
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runSearch() {
        guard !trimmedText.isEmpty else { return }
        Haptics.medium()
        remote.tvSearch(trimmedText)
        text = ""
        dismiss()
    }

    private func sendText(submit: Bool) {
        guard !text.isEmpty else { return }
        Haptics.tap()
        remote.typeText(text, submit: submit)
        text = ""
        dismiss()
    }
}

private struct CompactSearchSheetDetentModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.height(175), .medium])
                .nativePresentationSheet()
        } else {
            content
        }
    }
}

struct RemotePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
                .animation(NativeLiquidSpring.press, value: configuration.isPressed)
        } else {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
                .opacity(configuration.isPressed ? 0.86 : 1.0)
                .animation(NativeLiquidSpring.press, value: configuration.isPressed)
        }
        #else
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .animation(NativeLiquidSpring.press, value: configuration.isPressed)
        #endif
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func light() { tap() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
}

// MARK: - Унифицированный ввод PIN-кода (Сбер Салют 4 цифры / Android TV & YaOS 6 HEX-символов)

struct PinSheet: View {
    @ObservedObject var remote: UniversalTVRemoteManager
    @FocusState private var focused: Bool

    var body: some View {
        NativeGlassContainer(spacing: 14) {
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(remote.activePlatform.accentColor)
                    .frame(width: 74, height: 74)
                    .nativeLiquidGlass(
                        in: Circle(),
                        tint: remote.activePlatform.accentColor.opacity(0.26),
                        interactive: false
                    )
                    .padding(.top, 28)

                Text("Код с экрана ТВ")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(
                    remote.pinIsHex
                        ? "Введите 6-символьный код (0–9, A–F) с экрана \(remote.pinTargetName)"
                        : "Введите код, который показан на телевизоре \(remote.pinTargetName)"
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)

                TextField(remote.pinIsHex ? "A1B2C3" : "0000", text: $remote.pin)
                    .keyboardType(remote.pinIsHex ? .asciiCapable : .numberPad)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding()
                    .nativeLiquidGlass(
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                        interactive: true
                    )

                if let error = remote.errorText {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(SberPalette.coral)
                        .multilineTextAlignment(.center)
                }

                Button {
                    remote.confirmPIN()
                    Haptics.tap()
                } label: {
                    Text("Подключить")
                        .font(.headline)
                        .foregroundStyle(remote.pin.isEmpty ? .white.opacity(0.45) : .black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .nativeLiquidGlass(
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                            tint: remote.pin.isEmpty ? nil : Color.white.opacity(0.92),
                            interactive: !remote.pin.isEmpty
                        )
                }
                .buttonStyle(RemotePressStyle())
                .disabled(remote.pin.isEmpty)

                Button("Отмена") {
                    remote.cancelPin()
                }
                .foregroundStyle(.white.opacity(0.68))

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .nativeGlassSheetContainerBackground()
        .preferredColorScheme(.dark)
        .nativePresentationSheet()
        .onAppear { focused = true }
    }
}
