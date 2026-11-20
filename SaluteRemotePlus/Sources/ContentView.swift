import SwiftUI
import UIKit

enum CenterPadMode: String, CaseIterable, Identifiable {
    case dpad
    case gestures
    case trackpad
    case airMouse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dpad: return "Кнопки"
        case .gestures: return "Жесты"
        case .trackpad: return "Курсор"
        case .airMouse: return "Аэро"
        }
    }

    var symbol: String {
        switch self {
        case .dpad: return "circle.grid.cross.fill"
        case .gestures: return "hand.draw.fill"
        case .trackpad: return "cursorarrow.motionlines"
        case .airMouse: return "gyroscope"
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
    case sberRemote
    case kenwood
}

struct ContentView: View {
    @StateObject private var remote = SberCastRemote()
    @StateObject private var kenwood = KenwoodRemoteManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var section: AppSection = .home

    var body: some View {
        ZStack {
            SberLiquidBackdrop()

            switch section {
            case .home:
                SuperAppHomeView(
                    remote: remote,
                    kenwood: kenwood,
                    onOpenSber: {
                        Haptics.medium()
                        withAnimation(.easeInOut(duration: 0.22)) {
                            section = .sberRemote
                        }
                    },
                    onOpenKenwood: {
                        Haptics.medium()
                        withAnimation(.easeInOut(duration: 0.22)) {
                            section = .kenwood
                        }
                    }
                )
                .transition(.opacity)

            case .sberRemote:
                Group {
                    if remote.connectedDevice != nil {
                        RemotePadView(remote: remote) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                section = .home
                            }
                        }
                    } else {
                        ConnectionView(remote: remote) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                section = .home
                            }
                        }
                    }
                }
                .transition(.opacity)

            case .kenwood:
                KenwoodRemoteView(kenwood: kenwood) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        section = .home
                    }
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(
            get: { remote.needsPin },
            set: { if !$0 && remote.needsPin { remote.cancelPin() } }
        )) {
            PinSheet(remote: remote)
        }
        .onAppear {
            remote.resume()
            kenwood.start()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                remote.resume()
            case .background:
                remote.pause()
            default:
                break
            }
        }
    }
}

// MARK: - Главное первое меню супераппа (Пульт Сбер / Магнитола Kenwood)

struct SuperAppHomeView: View {
    @ObservedObject var remote: SberCastRemote
    @ObservedObject var kenwood: KenwoodRemoteManager
    let onOpenSber: () -> Void
    let onOpenKenwood: () -> Void

    private var sberSubtitle: String {
        if let dev = remote.connectedDevice {
            return remote.wireReady ? "\(dev.name) · Пульт готов" : "\(dev.name) · Подключение…"
        }
        if !remote.devices.isEmpty {
            return "Найдено ТВ: \(remote.devices.count)"
        }
        return "Управление Салют ТВ · Курсор · Аэромышь"
    }

    private var sberReady: Bool {
        remote.connectedDevice != nil && remote.wireReady
    }

    private var kenwoodSubtitle: String {
        if kenwood.isConnected {
            return "\(kenwood.connectedDeviceName ?? "Kenwood") · \(kenwood.currentSource.title) · VOL \(kenwood.volume)"
        }
        if !kenwood.discoveredDevices.isEmpty {
            return "Найдено устройств: \(kenwood.discoveredDevices.count)"
        }
        return "Плеер · 13-band EQ · DSP · DTA · Подсветка"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 18)

            // Заголовок супераппа
            VStack(spacing: 10) {
                ZStack {
                    LiquidGlassCircle(highlighted: false, accent: true)
                        .frame(width: 84, height: 84)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 35, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("Salute Remote+")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(SberPalette.brandGradient)

                Text("Выберите устройство управления")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.60))
            }

            // Основные кнопки главного меню: Пульт Сбер + Магнитола Kenwood
            VStack(spacing: 16) {
                SuperAppMenuCard(
                    symbol: "tv.fill",
                    title: "Пульт Сбер",
                    subtitle: sberSubtitle,
                    badgeText: sberReady ? "Готов" : nil,
                    badgeActive: sberReady,
                    accentIcon: true,
                    action: onOpenSber
                )

                SuperAppMenuCard(
                    symbol: "car.fill",
                    title: "Магнитола KENWOOD",
                    subtitle: kenwoodSubtitle,
                    badgeText: kenwood.isConnected ? "Подключено" : nil,
                    badgeActive: kenwood.isConnected,
                    accentIcon: true,
                    kenwoodStyle: true,
                    action: onOpenKenwood
                )
            }

            Spacer(minLength: 28)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct SuperAppMenuCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let badgeText: String?
    let badgeActive: Bool
    let accentIcon: Bool
    var kenwoodStyle: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                ZStack {
                    if accentIcon {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(kenwoodStyle ? KenwoodPalette.accentButtonGradient : SberPalette.accentButtonGradient)
                            .opacity(0.90)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(kenwoodStyle ? KenwoodPalette.glassAccentBorder : SberPalette.glassAccentBorder, lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(SberPalette.glassBorderGradient, lineWidth: 1)
                            )
                    }
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(accentIcon ? .white : .white.opacity(0.65))
                }
                .frame(width: 54, height: 54)
                .shadow(color: accentIcon ? (kenwoodStyle ? KenwoodPalette.crimson : SberPalette.brightGreen).opacity(0.32) : .clear, radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        if let badgeText {
                            Text(badgeText)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(badgeActive ? (kenwoodStyle ? .white : SberPalette.bgTop) : .white.opacity(0.75))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(
                                            badgeActive
                                                ? AnyShapeStyle(kenwoodStyle ? KenwoodPalette.accentButtonGradient : SberPalette.brandGradient)
                                                : AnyShapeStyle(Color.white.opacity(0.12))
                                        )
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
                    .foregroundStyle(.white.opacity(0.40))
            }
            .padding(16)
            .background(
                Group {
                    if kenwoodStyle {
                        KenwoodGlassPanel(cornerRadius: 24)
                    } else {
                        LiquidGlassPanel(cornerRadius: 24)
                    }
                }
            )
        }
        .buttonStyle(RemotePressStyle())
    }
}

// MARK: - Экран подключения в стиле Сбер Liquid Glass

struct ConnectionView: View {
    @ObservedObject var remote: SberCastRemote
    let onBackToMenu: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Button {
                    Haptics.tap()
                    onBackToMenu()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                        Text("Меню")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(LiquidGlassPanel(cornerRadius: 18))
                }
                .buttonStyle(RemotePressStyle())
                Spacer()
            }

            Spacer(minLength: 6)

            VStack(spacing: 12) {
                ZStack {
                    LiquidGlassCircle(highlighted: false, accent: true)
                        .frame(width: 88, height: 88)
                    Image(systemName: "tv.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("Salute Remote+")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(SberPalette.brandGradient)

                Text("Умный пульт Салют ТВ по Wi‑Fi")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
            }

            StatusCard(remote: remote)

            if !remote.devices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Найденные телевизоры")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.70))
                        .padding(.leading, 4)

                    ForEach(remote.devices, id: \.id) { device in
                        Button {
                            remote.connect(device)
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(SberPalette.accentButtonGradient)
                                        .opacity(0.28)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .strokeBorder(SberPalette.glassAccentBorder, lineWidth: 1)
                                                .opacity(0.6)
                                        )
                                    Image(systemName: "tv")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(SberPalette.lime)
                                }
                                .frame(width: 44, height: 44)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.name)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(device.features?.contains(.gamepadService) == true ? "Пульт Салют доступен" : "Устройство найдено")
                                        .font(.caption)
                                        .foregroundStyle(SberPalette.teal.opacity(0.85))
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.42))
                            }
                            .padding(14)
                            .background(LiquidGlassPanel(cornerRadius: 22))
                        }
                        .buttonStyle(RemotePressStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

struct StatusCard: View {
    @ObservedObject var remote: SberCastRemote

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(remote.error == nil ? SberPalette.brightGreen : SberPalette.coral)
                .frame(width: 10, height: 10)
                .shadow(color: (remote.error == nil ? SberPalette.brightGreen : SberPalette.coral).opacity(0.75), radius: 5)

            Text(remote.error ?? remote.status)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)

            Spacer()

            if remote.devices.isEmpty {
                ProgressView()
                    .tint(SberPalette.brightGreen)
            }
        }
        .padding(15)
        .background(LiquidGlassPanel(cornerRadius: 20))
    }
}

// MARK: - Главный экран пульта (фиксированный, без прокрутки)

struct RemotePadView: View {
    @ObservedObject var remote: SberCastRemote
    let onBackToMenu: () -> Void
    @AppStorage("SaluteRemotePlus.padMode") private var storedPadModeRaw = CenterPadMode.dpad.rawValue
    @State private var showTextSheet = false
    @State private var initialTextSheetMode: TextSheetMode = .globalSearch

    private var padMode: CenterPadMode {
        CenterPadMode(rawValue: storedPadModeRaw) ?? .dpad
    }

    private func selectPadMode(_ next: CenterPadMode) {
        guard next != padMode else { return }
        Haptics.medium()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
            storedPadModeRaw = next.rawValue
        }
        remote.setControllerMode(next.wireMode)
    }

    private var channelColor: Color {
        if remote.session != nil && remote.wireReady { return SberPalette.brightGreen }
        return remote.error == nil ? Color.orange : SberPalette.coral
    }

    private var channelText: String {
        if remote.session == nil { return "Подключение канала…" }
        return remote.wireReady ? "Пульт готов" : "Открываем канал…"
    }

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let w = proxy.size.width
            let compact = h < 700
            let vSpacing: CGFloat = compact ? 7 : 10
            let rowHeight = min(max(h * 0.076, 46), 60)

            VStack(spacing: vSpacing) {
                // Верхняя панель устройства
                HStack(spacing: 8) {
                    Button {
                        Haptics.tap()
                        onBackToMenu()
                    } label: {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 38, height: 38)
                            .background(LiquidGlassCircle())
                    }
                    .buttonStyle(RemotePressStyle())
                    .accessibilityLabel("Главное меню")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(remote.connectedDevice?.name ?? "Салют ТВ")
                            .font(.system(size: compact ? 19 : 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(channelColor)
                                .frame(width: 7, height: 7)
                                .shadow(color: channelColor.opacity(0.8), radius: 4)
                            Text(channelText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(channelColor)
                        }
                    }

                    Spacer()

                    // Быстрый глобальный поиск по ТВ
                    Button {
                        Haptics.tap()
                        initialTextSheetMode = .globalSearch
                        showTextSheet = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(SberPalette.lime)
                            .frame(width: 38, height: 38)
                            .background(LiquidGlassCircle(highlighted: false, accent: false))
                    }
                    .buttonStyle(RemotePressStyle())
                    .accessibilityLabel("Глобальный поиск по ТВ")

                    if remote.session == nil {
                        Button {
                            Haptics.tap()
                            remote.reconnectChannel()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(SberPalette.brightGreen)
                                .frame(width: 38, height: 38)
                                .background(LiquidGlassCircle())
                        }
                        .buttonStyle(RemotePressStyle())
                        .accessibilityLabel("Переподключить канал")
                    }

                    Button {
                        Haptics.tap()
                        remote.forgetSavedDevice()
                    } label: {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 38, height: 38)
                            .background(LiquidGlassCircle())
                    }
                    .buttonStyle(RemotePressStyle())
                    .accessibilityLabel("Сменить телевизор")
                }

                // Ряд 1: Питание (нажатие / удержание), Настройки, Найти пульт
                HStack(spacing: 10) {
                    PowerRemoteButton(
                        height: rowHeight,
                        onDown: { remote.sendDown(.power) },
                        onUp: { remote.sendUp(.power) }
                    )
                    ActionRemoteButton(
                        symbol: "gearshape.fill",
                        title: "Настройки",
                        height: rowHeight
                    ) {
                        send(.settings)
                    }
                    ActionRemoteButton(
                        symbol: "dot.radiowaves.left.and.right",
                        title: "Найти пульт",
                        height: rowHeight
                    ) {
                        Haptics.tap()
                        remote.findRemote()
                    }
                }

                // Центр: Liquid Glass дека с 4 режимами (Кнопки / Жесты / Курсор / Аэромышь)
                ZStack {
                    LiquidGlassPanel(cornerRadius: 30)

                    VStack(spacing: compact ? 6 : 8) {
                        // Переключатель 4 режимов управления
                        HStack(spacing: 4) {
                            ForEach(CenterPadMode.allCases) { mode in
                                let selected = mode == padMode
                                Button {
                                    selectPadMode(mode)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: mode.symbol)
                                            .font(.system(size: compact ? 11 : 12, weight: .semibold))
                                        Text(mode.title)
                                            .font(.system(size: compact ? 10 : 11, weight: .semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .foregroundStyle(selected ? .white : .white.opacity(0.62))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: compact ? 30 : 32)
                                    .background(
                                        Group {
                                            if selected {
                                                Capsule()
                                                    .fill(SberPalette.accentButtonGradient)
                                                    .overlay(
                                                        Capsule().strokeBorder(SberPalette.glassAccentBorder, lineWidth: 1)
                                                    )
                                                    .shadow(color: SberPalette.brightGreen.opacity(0.35), radius: 6, y: 2)
                                            }
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.26))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1))
                        )
                        .padding(.horizontal, 10)
                        .padding(.top, 10)

                        // Рабочая поверхность выбранного режима
                        GeometryReader { deckGeo in
                            let deckH = deckGeo.size.height
                            let deckW = deckGeo.size.width
                            let dpadSpacing: CGFloat = compact ? 6 : 8
                            let dpadBtn = min(max(min((deckW - 56) / 3.25, (deckH - dpadSpacing * 2 - 14) / 3.18), 48), 72)
                            let okBtn = min(dpadBtn + 6, 78)

                            Group {
                                switch padMode {
                                case .dpad:
                                    VStack(spacing: dpadSpacing) {
                                        DPadCircleButton(
                                            symbol: "chevron.up",
                                            size: dpadBtn,
                                            onDown: { remote.sendDown(.up) },
                                            onUp: { remote.sendUp(.up) }
                                        )
                                        HStack(spacing: dpadSpacing) {
                                            DPadCircleButton(
                                                symbol: "chevron.left",
                                                size: dpadBtn,
                                                onDown: { remote.sendDown(.left) },
                                                onUp: { remote.sendUp(.left) }
                                            )
                                            DPadCircleButton(
                                                title: "OK",
                                                size: okBtn,
                                                accent: true,
                                                onDown: { remote.sendDown(.ok) },
                                                onUp: { remote.sendUp(.ok) }
                                            )
                                            DPadCircleButton(
                                                symbol: "chevron.right",
                                                size: dpadBtn,
                                                onDown: { remote.sendDown(.right) },
                                                onUp: { remote.sendUp(.right) }
                                            )
                                        }
                                        DPadCircleButton(
                                            symbol: "chevron.down",
                                            size: dpadBtn,
                                            onDown: { remote.sendDown(.down) },
                                            onUp: { remote.sendUp(.down) }
                                        )
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                case .gestures:
                                    TouchpadSurfaceView(
                                        onCommand: { command in
                                            remote.send(command)
                                        },
                                        onDown: { command in
                                            remote.sendDown(command)
                                        },
                                        onUp: { command in
                                            remote.sendUp(command)
                                        }
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .padding(.horizontal, 6)
                                    .padding(.bottom, 6)

                                case .trackpad:
                                    TrackpadSurfaceView(
                                        onMove: { dx, dy in
                                            remote.sendMouseOffset(dx: dx, dy: dy)
                                        },
                                        onVerticalScroll: { offset in
                                            remote.sendMouseVerticalScroll(offset)
                                        },
                                        onHorizontalScroll: { offset in
                                            remote.sendMouseHorizontalScroll(offset)
                                        },
                                        onClick: {
                                            remote.send(.mouseClick)
                                        },
                                        onClickDown: {
                                            remote.sendDown(.mouseClick)
                                        },
                                        onClickUp: {
                                            remote.sendUp(.mouseClick)
                                        }
                                    )

                                case .airMouse:
                                    AirMouseSurfaceView(
                                        onMove: { dx, dy in
                                            remote.sendMouseOffset(dx: dx, dy: dy)
                                        },
                                        onVerticalScroll: { offset in
                                            remote.sendMouseVerticalScroll(offset)
                                        },
                                        onClickDown: {
                                            remote.sendDown(.mouseClick)
                                        },
                                        onClickUp: {
                                            remote.sendUp(.mouseClick)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Ряд 2: Назад, Домой
                HStack(spacing: 10) {
                    ActionRemoteButton(
                        symbol: "arrow.uturn.backward",
                        title: "Назад",
                        height: rowHeight
                    ) {
                        send(.back)
                    }
                    ActionRemoteButton(
                        symbol: "house.fill",
                        title: "Домой",
                        height: rowHeight
                    ) {
                        send(.home)
                    }
                }

                // Ряд 3: Громкость −, Mute, Громкость +
                HStack(spacing: 10) {
                    ActionRemoteButton(
                        symbol: "speaker.wave.1.fill",
                        title: "VOL −",
                        height: rowHeight
                    ) {
                        send(.volumeDown)
                    }
                    ActionRemoteButton(
                        symbol: "speaker.slash.fill",
                        title: "MUTE",
                        height: rowHeight
                    ) {
                        send(.mute)
                    }
                    ActionRemoteButton(
                        symbol: "speaker.wave.3.fill",
                        title: "VOL +",
                        height: rowHeight
                    ) {
                        send(.volumeUp)
                    }
                }

                // Ряд 4: Пауза/Плей, Голос, Поиск / Ввод
                HStack(spacing: 10) {
                    ActionRemoteButton(
                        symbol: "playpause.fill",
                        title: "Пауза / Плей",
                        height: rowHeight
                    ) {
                        send(.playPause)
                    }
                    ActionRemoteButton(
                        symbol: remote.voiceState == .idle ? "mic.fill" : "stop.fill",
                        title: remote.voiceState == .idle ? "Голос" : (remote.voiceState == .starting ? "Запуск…" : "Слушаю…"),
                        height: rowHeight,
                        highlighted: remote.voiceState != .idle
                    ) {
                        Haptics.tap()
                        remote.toggleVoice()
                    }
                    ActionRemoteButton(
                        symbol: "keyboard",
                        title: "Поиск / Ввод",
                        height: rowHeight
                    ) {
                        Haptics.tap()
                        initialTextSheetMode = .globalSearch
                        showTextSheet = true
                    }
                }

                // Компактная строка статуса / подсказки без прокрутки и сдвигов
                Text(footerText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(remote.error != nil ? SberPalette.coral : Color.white.opacity(0.46))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(height: 15)
            }
            .padding(.horizontal, 16)
            .padding(.top, compact ? 6 : 10)
            .padding(.bottom, compact ? 6 : 10)
            .frame(width: w, height: h)
        }
        .onAppear {
            remote.setControllerMode(padMode.wireMode)
        }
        .onChange(of: remote.wireReady) { ready in
            if ready {
                remote.setControllerMode(padMode.wireMode)
            }
        }
        .sheet(isPresented: $showTextSheet) {
            TextInputSheet(remote: remote, initialMode: initialTextSheetMode)
        }
    }

    private var footerText: String {
        if let error = remote.error { return error }
        if let notice = remote.notice { return notice }
        switch padMode {
        case .dpad:
            return "Удерживайте стрелки, OK или «Питание» для долгого нажатия"
        case .gestures:
            return "Свайп + удержание · Удержание = долгий OK · ○ Домой · < Назад"
        case .trackpad:
            return "Водите пальцем для курсора · Полосы справа и снизу — прокрутка"
        case .airMouse:
            return "Наклоняйте телефон для курсора · Кнопка в центре — клик"
        }
    }

    private func send(_ command: RemoteCommand) {
        Haptics.tap()
        remote.send(command)
    }
}

// MARK: - Кнопка питания с поддержкой удержания (меню перезагрузки/выключения ТВ)

struct PowerRemoteButton: View {
    let height: CGFloat
    let onDown: () -> Void
    let onUp: () -> Void

    @GestureState private var gesturePressed = false
    @State private var isPressed = false
    @State private var isHoldingMenu = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "power")
                .font(.system(size: height > 52 ? 19 : 17, weight: .bold))
            Text(isHoldingMenu ? "Меню ТВ…" : "Питание")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isHoldingMenu ? .white : SberPalette.coral)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isHoldingMenu
                            ? SberPalette.coral.opacity(0.84)
                            : (isPressed ? SberPalette.coral.opacity(0.30) : SberPalette.coral.opacity(0.14))
                    )
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SberPalette.specularSheen)
                    .opacity(0.55)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            SberPalette.coral.opacity(isHoldingMenu ? 0.95 : 0.48),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: isHoldingMenu ? SberPalette.coral.opacity(0.35) : Color.black.opacity(0.25), radius: 8, y: 4)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .animation(.easeOut(duration: 0.15), value: isHoldingMenu)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($gesturePressed) { _, state, _ in
                    state = true
                }
        )
        .onChange(of: gesturePressed) { active in
            if active {
                beginPress()
            } else {
                endPress()
            }
        }
        .onDisappear {
            endPress()
        }
        .accessibilityLabel("Питание. Короткое нажатие — включить или выключить. Удержание — меню перезагрузки и выключения.")
    }

    private func beginPress() {
        guard !isPressed else { return }
        isPressed = true
        isHoldingMenu = false
        Haptics.tap()
        onDown()

        holdTask?.cancel()
        holdTask = Task {
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isPressed else { return }
                isHoldingMenu = true
                Haptics.heavy()
            }
        }
    }

    private func endPress() {
        holdTask?.cancel()
        holdTask = nil
        guard isPressed else { return }
        isPressed = false
        isHoldingMenu = false
        onUp()
    }
}

// MARK: - Сенсорная панель жестов

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

        // 1. Короткое нажатие (тап) → OK
        if totalLength < 20 && chord < 16 {
            return .tapOK
        }

        // 2. Круг (по часовой или против часовой) → Домой
        if isCircle(points, totalLength: totalLength, chord: chord) {
            return .circleHome
        }

        // 3. Жест «<» (верхний правый → левый центр → нижний правый) → Назад
        if isBackChevron(points, totalLength: totalLength) {
            return .chevronBack
        }

        // 4. Свайпы вверх / вниз / влево / вправо
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

    /// Распознаёт жест удержания, пока палец ещё на экране:
    /// неподвижное удержание → OK, прямой свайп с паузой в конце → соответствующая стрелка.
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
            // Тонкие подсказки направлений по краям сенсорной панели
            VStack {
                Image(systemName: "chevron.up")
                Spacer()
                HStack {
                    Image(systemName: "chevron.left")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                Spacer()
                Image(systemName: "chevron.down")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SberPalette.teal.opacity(0.26))
            .padding(14)

            // Индикатор активного удержания или вспышка распознанного жеста
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
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(SberPalette.accentButtonGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(SberPalette.glassAccentBorder, lineWidth: 1.4)
                        )
                )
                .shadow(color: SberPalette.brightGreen.opacity(0.42), radius: 12)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
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
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(SberPalette.accentButtonGradient)
                        .opacity(0.84)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                        )
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else if trail.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(SberPalette.brandGradient)
                        .opacity(0.72)
                    Text("Свайпы · Тап = OK · Удержание")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("○ Домой   ·   < Назад")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.30))
                }
            }

            // След пальца в фирменном градиенте Сбера
            if trail.count >= 2 && activeHold == nil {
                Path { path in
                    path.move(to: trail[0])
                    for point in trail.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [SberPalette.teal.opacity(0.4), SberPalette.brightGreen, SberPalette.lime],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: SberPalette.brightGreen.opacity(0.6), radius: 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
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
                    withAnimation(.easeOut(duration: 0.14)) {
                        activeHold = holdGesture
                    }
                    onDown(holdGesture.command)
                }
            }
        }
    }

    private func releaseActiveHold() {
        guard let hold = activeHold else { return }
        withAnimation(.easeOut(duration: 0.14)) {
            activeHold = nil
        }
        onUp(hold.command)
    }

    private func showFeedback(_ gesture: TouchpadGesture) {
        feedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.14)) {
            feedback = gesture
        }
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    feedback = nil
                }
            }
        }
    }
}

// MARK: - Кнопки пульта в стиле Сбер Liquid Glass

struct DPadCircleButton: View {
    var symbol: String?
    var title: String?
    let size: CGFloat
    var accent = false
    let onDown: () -> Void
    let onUp: () -> Void

    @GestureState private var gesturePressed = false
    @State private var isPressed = false
    @State private var isHolding = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
            } else {
                Text(title ?? "")
            }
        }
        .font(.system(size: title == nil ? 21 : 18, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(
            LiquidGlassCircle(
                highlighted: isHolding || (isPressed && !accent),
                accent: accent
            )
        )
        .overlay(
            Circle()
                .strokeBorder(
                    isHolding ? SberPalette.lime : Color.clear,
                    lineWidth: isHolding ? 2 : 0
                )
        )
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .animation(.easeOut(duration: 0.14), value: isHolding)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($gesturePressed) { _, state, _ in
                    state = true
                }
        )
        .onChange(of: gesturePressed) { active in
            if active {
                beginPress()
            } else {
                endPress()
            }
        }
        .onDisappear {
            endPress()
        }
    }

    private func beginPress() {
        guard !isPressed else { return }
        isPressed = true
        isHolding = false
        Haptics.tap()
        onDown()

        holdTask?.cancel()
        holdTask = Task {
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isPressed else { return }
                isHolding = true
                Haptics.medium()
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

struct ActionRemoteButton: View {
    let symbol: String
    let title: String
    let height: CGFloat
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: height > 52 ? 19 : 17, weight: .semibold))
                    .foregroundStyle(highlighted ? AnyShapeStyle(Color.white) : AnyShapeStyle(SberPalette.brandGradient))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(highlighted ? 1.0 : 0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(LiquidGlassPanel(cornerRadius: 18, highlighted: highlighted))
        }
        .buttonStyle(RemotePressStyle())
    }
}

struct RemotePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.84 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Глобальный поиск по ТВ и ввод с клавиатуры

struct TextInputSheet: View {
    @ObservedObject var remote: SberCastRemote
    let initialMode: TextSheetMode

    @Environment(\.dismiss) private var dismiss
    @State private var mode: TextSheetMode = .globalSearch
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            SberLiquidBackdrop()

            VStack(spacing: 16) {
                Capsule()
                    .fill(.white.opacity(0.24))
                    .frame(width: 40, height: 4)
                    .padding(.top, 10)

                Text(mode == .globalSearch ? "Глобальный поиск по ТВ" : "Ввод текста на ТВ")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                // Переключатель «Поиск по ТВ» / «Ввод текста»
                HStack(spacing: 4) {
                    ForEach(TextSheetMode.allCases) { tab in
                        let selected = tab == mode
                        Button {
                            Haptics.tap()
                            withAnimation(.easeInOut(duration: 0.18)) {
                                mode = tab
                            }
                        } label: {
                            Text(tab.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(selected ? .white : .white.opacity(0.62))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    Group {
                                        if selected {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(SberPalette.accentButtonGradient)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .strokeBorder(SberPalette.glassAccentBorder, lineWidth: 1)
                                                )
                                        }
                                    }
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(LiquidGlassPanel(cornerRadius: 15))

                Text(
                    mode == .globalSearch
                        ? "Отправляет запрос сразу в системный поиск Салют ТВ — открывать строку поиска на экране не нужно."
                        : "Сначала откройте поле ввода на ТВ (OK). Поддерживаются русский и английский."
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)

                // Поле ввода в стиле Liquid Glass
                HStack(spacing: 8) {
                    Image(systemName: mode == .globalSearch ? "magnifyingglass" : "keyboard")
                        .foregroundStyle(SberPalette.brightGreen)
                    TextField(
                        mode == .globalSearch ? "Фильм, сериал, приложение…" : "Что набрать на ТВ…",
                        text: $text
                    )
                    .focused($focused)
                    .submitLabel(mode == .globalSearch ? .search : .send)
                    .onSubmit {
                        if mode == .globalSearch {
                            runGlobalSearch()
                        } else {
                            sendText(submit: true)
                        }
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
                .padding(14)
                .background(LiquidGlassPanel(cornerRadius: 16))

                if mode == .globalSearch {
                    Button {
                        runGlobalSearch()
                    } label: {
                        Label("Найти на ТВ", systemImage: "magnifyingglass")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(SberPrimaryButtonStyle(disabled: trimmedText.isEmpty))
                    .disabled(trimmedText.isEmpty)

                    Button {
                        Haptics.tap()
                        remote.youtubeSearch(trimmedText)
                        dismiss()
                    } label: {
                        Label("Искать на YouTube", systemImage: "play.rectangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(SberGlassButtonStyle(disabled: trimmedText.isEmpty))
                    .disabled(trimmedText.isEmpty)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap()
                            remote.sendKey(KeyMap.backspace)
                        } label: {
                            Label("Стереть", systemImage: "delete.left")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(SberGlassButtonStyle())

                        Button {
                            Haptics.tap()
                            remote.sendKey(KeyMap.enter)
                        } label: {
                            Label("Enter", systemImage: "return")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(SberGlassButtonStyle())
                    }

                    Button {
                        sendText(submit: true)
                    } label: {
                        Text("Набрать и нажать Enter")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(SberPrimaryButtonStyle(disabled: text.isEmpty))
                    .disabled(text.isEmpty)

                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap()
                            remote.typeText(text, submit: false)
                        } label: {
                            Text("Только набрать")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(SberGlassButtonStyle(disabled: text.isEmpty))
                        .disabled(text.isEmpty)

                        Button {
                            runGlobalSearch()
                        } label: {
                            Label("Поиск ТВ", systemImage: "magnifyingglass")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(SberGlassButtonStyle(disabled: trimmedText.isEmpty))
                        .disabled(trimmedText.isEmpty)
                    }
                }

                if let notice = remote.notice {
                    Text(notice)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SberPalette.lime)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            mode = initialMode
            focused = true
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGlobalSearch() {
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
        if remote.notice == nil {
            text = ""
            dismiss()
        }
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
}

// MARK: - Ввод PIN-кода

struct PinSheet: View {
    @ObservedObject var remote: SberCastRemote
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            SberLiquidBackdrop()

            VStack(spacing: 18) {
                ZStack {
                    LiquidGlassCircle(accent: true)
                        .frame(width: 74, height: 74)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 28)

                Text("Код с экрана ТВ")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Введите код, который показан на телевизоре \(remote.connectedDevice?.name ?? "")")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)

                TextField("0000", text: $remote.pin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .padding()
                    .background(LiquidGlassPanel(cornerRadius: 18))

                if let error = remote.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(SberPalette.coral)
                }

                Button {
                    remote.confirmPIN()
                    Haptics.tap()
                } label: {
                    Text("Подключить")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(SberPrimaryButtonStyle(disabled: remote.pin.isEmpty))
                .disabled(remote.pin.isEmpty)

                Button("Отмена") {
                    remote.cancelPin()
                }
                .foregroundStyle(.white.opacity(0.65))

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
    }
}
