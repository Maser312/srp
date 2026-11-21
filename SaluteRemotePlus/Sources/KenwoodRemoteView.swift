import SwiftUI

// MARK: - Фирменная палитра KENWOOD Dark + Liquid Glass

enum KenwoodPalette {
    /// Фирменный красный KENWOOD (активные элементы и подсветка ресивера)
    static let crimson = Color(red: 0.902, green: 0.000, blue: 0.169)      // #E6002B
    static let neonRed = Color(red: 1.000, green: 0.196, blue: 0.286)      // #FF3249
    static let deepRed = Color(red: 0.580, green: 0.000, blue: 0.118)      // #94001E

    /// Фирменный холодный циан/голубой дисплея KENWOOD Car Audio
    static let cyan = Color(red: 0.000, green: 0.784, blue: 1.000)         // #00C8FF
    static let iceBlue = Color(red: 0.420, green: 0.878, blue: 1.000)      // #6BE0FF
    static let amber = Color(red: 1.000, green: 0.659, blue: 0.149)        // #FFA826

    static let bgTop = Color(red: 0.020, green: 0.020, blue: 0.028)
    static let bgMid = Color(red: 0.020, green: 0.020, blue: 0.028)
    static let bgBottom = Color(red: 0.020, green: 0.020, blue: 0.028)
}

/// Чистый глубокий тёмный фон в стиле пульта без градиентов для нативного Liquid Glass.
struct KenwoodLiquidBackdrop: View {
    let glowColor: Color

    var body: some View {
        NativeDarkBackdrop()
    }
}

struct KenwoodGlassPanel: View {
    var cornerRadius: CGFloat = 22
    var highlighted: Bool = false
    var accentGlow: Color? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(highlighted ? KenwoodPalette.crimson.opacity(0.62) : Color.white.opacity(0.05))
            shape.strokeBorder(
                highlighted ? KenwoodPalette.neonRed.opacity(0.45) : Color.white.opacity(0.14),
                lineWidth: 0.9
            )
        }
    }
}

struct KenwoodGlassCircle: View {
    var highlighted: Bool = false
    var accent: Bool = false

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill((accent || highlighted) ? KenwoodPalette.crimson.opacity(0.70) : Color.white.opacity(0.06))
            Circle().strokeBorder(
                (accent || highlighted) ? KenwoodPalette.neonRed.opacity(0.48) : Color.white.opacity(0.14),
                lineWidth: 0.9
            )
        }
    }
}

private extension View {
    @ViewBuilder
    func kenwoodGlassPanel(
        cornerRadius: CGFloat = 22,
        highlighted: Bool = false,
        interactive: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self.nativeLiquidGlass(
            in: shape,
            tint: highlighted ? KenwoodPalette.crimson.opacity(0.65) : nil,
            interactive: interactive
        )
    }

    @ViewBuilder
    func kenwoodGlassCircle(
        highlighted: Bool = false,
        accent: Bool = false,
        interactive: Bool = false
    ) -> some View {
        let tint: Color? = (accent || highlighted) ? KenwoodPalette.crimson.opacity(accent ? 0.72 : 0.48) : nil
        self.nativeLiquidGlass(in: Circle(), tint: tint, interactive: interactive)
    }
}

struct KenwoodPrimaryButtonStyle: ButtonStyle {
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        configuration.label
            .foregroundStyle(.white.opacity(disabled ? 0.45 : 1.0))
            .nativeLiquidGlass(
                in: shape,
                tint: KenwoodPalette.crimson.opacity(disabled ? 0.25 : 0.76),
                interactive: !disabled
            )
            .scaleEffect(configuration.isPressed && !disabled ? 0.95 : 1.0)
            .animation(NativeLiquidSpring.press, value: configuration.isPressed)
    }
}

struct KenwoodGlassButtonStyle: ButtonStyle {
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        configuration.label
            .foregroundStyle(.white.opacity(disabled ? 0.40 : 0.94))
            .nativeLiquidGlass(in: shape, interactive: !disabled)
            .scaleEffect(configuration.isPressed && !disabled ? 0.95 : 1.0)
            .animation(NativeLiquidSpring.press, value: configuration.isPressed)
    }
}

// MARK: - Вкладки раздела KENWOOD Remote

enum KenwoodTab: String, CaseIterable, Identifiable {
    case player
    case audio
    case keypad
    case color

    var id: String { rawValue }

    var title: String {
        switch self {
        case .player: return "Плеер"
        case .audio: return "Звук"
        case .keypad: return "Пульт"
        case .color: return "Подсветка"
        }
    }

    var symbol: String {
        switch self {
        case .player: return "play.circle.fill"
        case .audio: return "slider.vertical.3"
        case .keypad: return "circle.grid.cross.fill"
        case .color: return "paintpalette.fill"
        }
    }
}

enum KenwoodAudioSubtab: String, CaseIterable, Identifiable {
    case eq
    case fader
    case bass
    case dtaXover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eq: return "EQ"
        case .fader: return "Баланс"
        case .bass: return "Саб / Бас"
        case .dtaXover: return "DTA / Срез"
        }
    }
}

/// Полный интерфейс управления автомагнитолой KENWOOD в фирменном стиле KENWOOD Dark + Liquid Glass.
struct KenwoodRemoteView: View {
    @ObservedObject var kenwood: KenwoodRemoteManager
    let onBackToMenu: () -> Void

    @Namespace private var tabNamespace
    @State private var selectedTab: KenwoodTab = .player
    @State private var audioSubtab: KenwoodAudioSubtab = .eq
    @State private var showConnectionSheet = false
    @State private var gestureHint: String?

    private var illuminationColor: Color {
        Color(
            red: Double(kenwood.customRed) / 31.0,
            green: Double(kenwood.customGreen) / 31.0,
            blue: Double(kenwood.customBlue) / 31.0
        )
    }

    var body: some View {
        ZStack {
            KenwoodLiquidBackdrop(glowColor: illuminationColor)

            VStack(spacing: 0) {
                // Верхняя панель с фирменным знаком KENWOOD
                NativeGlassContainer(spacing: 8) {
                    HStack(spacing: 10) {
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
                            .kenwoodGlassPanel(cornerRadius: 18, interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(KenwoodPalette.neonRed)
                                    .rotationEffect(.degrees(-90))
                                Text((kenwood.connectedDeviceName ?? "KENWOOD").uppercased())
                                    .font(.system(size: 17, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(kenwood.isConnected ? KenwoodPalette.cyan : KenwoodPalette.amber)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: (kenwood.isConnected ? KenwoodPalette.cyan : KenwoodPalette.amber).opacity(0.85), radius: 4)
                                Text(kenwood.isConnected ? (kenwood.activeTransportLabel ?? "OpenLink готов") : "Нажмите для подключения")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(kenwood.isConnected ? KenwoodPalette.iceBlue : .white.opacity(0.58))
                                    .lineLimit(1)
                            }
                        }
                        .onTapGesture {
                            Haptics.tap()
                            showConnectionSheet = true
                        }

                        Spacer()

                        Button {
                            Haptics.tap()
                            kenwood.toggleMute()
                        } label: {
                            Text("ATT")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(kenwood.isMuted ? .white : KenwoodPalette.neonRed)
                                .frame(width: 40, height: 36)
                                .kenwoodGlassPanel(cornerRadius: 18, highlighted: kenwood.isMuted, interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())
                        .accessibilityLabel("ATT / Приглушить звук")

                        Button {
                            Haptics.tap()
                            showConnectionSheet = true
                        } label: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(kenwood.isConnected ? KenwoodPalette.cyan : .white.opacity(0.90))
                                .frame(width: 36, height: 36)
                                .kenwoodGlassCircle(highlighted: kenwood.isConnected, interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())
                        .accessibilityLabel("Подключение Bluetooth к Kenwood")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                // Содержимое выбранной вкладки
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        if !kenwood.isConnected {
                            connectBannerCard
                        }

                        switch selectedTab {
                        case .player:
                            playerTabContent
                        case .audio:
                            audioTabContent
                        case .keypad:
                            keypadTabContent
                        case .color:
                            colorAndSetupTabContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }

                // Нижняя стеклянная панель 4 вкладок в нативном Liquid Glass
                NativeGlassContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(KenwoodTab.allCases) { tab in
                            let active = tab == selectedTab
                            Button {
                                Haptics.tap()
                                withAnimation(NativeLiquidSpring.morph) {
                                    selectedTab = tab
                                }
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: tab.symbol)
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(tab.title)
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(active ? .white : .white.opacity(0.55))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .nativeLiquidGlass(
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                                    tint: active ? KenwoodPalette.crimson.opacity(0.75) : nil,
                                    interactive: true
                                )
                                .nativeGlassID(active ? "activeTab" : tab.id, in: tabNamespace)
                            }
                            .buttonStyle(RemotePressStyle())
                        }
                    }
                    .padding(5)
                    .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .padding(.top, 4)
            }
        }
        .onAppear {
            kenwood.start()
        }
        .sheet(isPresented: $showConnectionSheet) {
            KenwoodConnectionSheet(kenwood: kenwood, glowColor: illuminationColor)
        }
    }

    // MARK: - Баннер подключения

    private var connectBannerCard: some View {
        Button {
            Haptics.tap()
            showConnectionSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .kenwoodGlassCircle(accent: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Подключить ресивер KENWOOD")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(bannerSubtitle)
                        .font(.caption)
                        .foregroundStyle(KenwoodPalette.iceBlue)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(12)
            .kenwoodGlassPanel(cornerRadius: 20, interactive: true)
        }
        .buttonStyle(RemotePressStyle())
    }

    private var bannerSubtitle: String {
        if let btError = kenwood.bluetoothStateText {
            return btError
        }
        if !kenwood.discoveredDevices.isEmpty {
            return "Найдено устройств: \(kenwood.discoveredDevices.count)"
        }
        if let audioName = kenwood.connectedBluetoothAudioName {
            return "Bluetooth Audio: \(audioName) · нужен iAP2 OpenLink"
        }
        return "Bluetooth iAP2 / USB или BLE"
    }

    // MARK: - Вкладка 1: Дисплей ресивера, Круговой энкодер громкости, Источники, Жесты, Тюнер

    private var playerTabContent: some View {
        VStack(spacing: 14) {
            // Фирменный OLED-дисплей автомагнитолы KENWOOD + круговая ручка громкости
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    // Бейдж источника (красный KENWOOD)
                    HStack(spacing: 6) {
                        Image(systemName: kenwood.currentSource.symbol)
                            .font(.caption.bold())
                        Text(kenwood.currentSource.title.uppercased())
                            .font(.caption.weight(.black))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .nativeLiquidGlass(in: Capsule(), tint: KenwoodPalette.crimson.opacity(0.76))

                    // Индикатор EQ
                    Text(kenwood.selectedEQPreset.title)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(KenwoodPalette.iceBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(KenwoodPalette.cyan.opacity(0.14))
                                .overlay(Capsule().strokeBorder(KenwoodPalette.cyan.opacity(0.35), lineWidth: 1))
                        )

                    Spacer()

                    if kenwood.subwooferEnabled {
                        Text("SW")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(KenwoodPalette.neonRed)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(KenwoodPalette.neonRed.opacity(0.6), lineWidth: 1))
                    }

                    if kenwood.loudness > 0 {
                        Text("LOUD\(kenwood.loudness)")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(KenwoodPalette.amber)
                    }
                }

                // Тёмная стеклянная OLED-матрица дисплея + круговой энкодер громкости
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        if kenwood.currentSource.isRadio {
                            Text(kenwood.tunerFrequency)
                                .font(.system(size: 28, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                                .shadow(color: illuminationColor.opacity(0.55), radius: 8)
                            Text("\(kenwood.tunerStation) · P\(kenwood.activeTunerPreset)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(KenwoodPalette.iceBlue)
                        } else {
                            Text(kenwood.trackTitle)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(kenwood.trackArtist)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(KenwoodPalette.iceBlue.opacity(0.88))
                                .lineLimit(1)
                            if !kenwood.trackAlbum.isEmpty {
                                Text(kenwood.trackAlbum)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(1)
                            }
                        }

                        // Стилизованный индикатор уровня громкости (сегменты)
                        HStack(spacing: 2) {
                            ForEach(0..<18, id: \.self) { seg in
                                let active = !kenwood.isMuted && Double(seg) / 18.0 < Double(kenwood.volume) / 35.0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(active ? (seg >= 14 ? KenwoodPalette.neonRed : illuminationColor) : Color.white.opacity(0.10))
                                    .frame(height: 5)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Фирменная круглая ручка громкости KENWOOD с дугой подсветки
                    KenwoodRotaryVolumeKnob(
                        volume: kenwood.volume,
                        isMuted: kenwood.isMuted,
                        ringColor: illuminationColor,
                        onStepUp: { kenwood.volumeUp() },
                        onStepDown: { kenwood.volumeDown() },
                        onTapMute: { kenwood.toggleMute() }
                    )
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.42))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(illuminationColor.opacity(0.45), lineWidth: 1.2)
                        )
                )

                // Точный ползунок громкости + быстрые кнопки − / +
                NativeGlassContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap()
                            kenwood.volumeDown()
                        } label: {
                            Image(systemName: "speaker.wave.1.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .kenwoodGlassCircle(interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())

                        Slider(
                            value: Binding(
                                get: { Double(kenwood.volume) },
                                set: { kenwood.setVolume(Int($0.rounded())) }
                            ),
                            in: 0...35,
                            step: 1
                        )
                        .tint(KenwoodPalette.neonRed)

                        Button {
                            Haptics.tap()
                            kenwood.volumeUp()
                        } label: {
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .kenwoodGlassCircle(interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())
                    }
                }
            }
            .padding(16)
            .kenwoodGlassPanel(cornerRadius: 24)

            // Селектор источников KENWOOD
            ScrollView(.horizontal, showsIndicators: false) {
                NativeGlassContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(KenwoodSource.allCases) { source in
                            let selected = source == kenwood.currentSource
                            Button {
                                Haptics.tap()
                                kenwood.selectSource(source)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: source.symbol)
                                        .font(.system(size: 12, weight: .bold))
                                    Text(source.title)
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundStyle(selected ? .white : .white.opacity(0.74))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .nativeLiquidGlass(
                                    in: Capsule(),
                                    tint: selected ? KenwoodPalette.crimson.opacity(0.76) : nil,
                                    interactive: true
                                )
                            }
                            .buttonStyle(RemotePressStyle())
                        }
                    }
                }
            }

            // Фирменная жестовая зона KENWOOD Remote
            KenwoodGesturePad(
                hintText: gestureHint,
                isRadio: kenwood.currentSource.isRadio,
                glowColor: illuminationColor,
                onTap: {
                    showGestureFeedback(kenwood.currentSource.isRadio ? "ATT / Mute" : (kenwood.isPlaying ? "Пауза" : "Играть"))
                    kenwood.playPause()
                },
                onSwipeLeft: {
                    showGestureFeedback(kenwood.currentSource.isRadio ? "Поиск вперёд" : "Следующий трек")
                    kenwood.nextTrack()
                },
                onSwipeRight: {
                    showGestureFeedback(kenwood.currentSource.isRadio ? "Поиск назад" : "Предыдущий трек")
                    kenwood.previousTrack()
                },
                onSwipeUp: {
                    showGestureFeedback("Громкость +")
                    kenwood.volumeUp()
                },
                onSwipeDown: {
                    showGestureFeedback("Громкость −")
                    kenwood.volumeDown()
                }
            )

            // Панель управления медиа или тюнером
            if kenwood.currentSource.isRadio {
                tunerControlCard
            } else {
                mediaTransportCard
            }
        }
    }

    private var mediaTransportCard: some View {
        NativeGlassContainer(spacing: 10) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        kenwood.previousTrack()
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .kenwoodGlassPanel(cornerRadius: 18, interactive: true)
                    }
                    .buttonStyle(RemotePressStyle())

                    Button {
                        Haptics.medium()
                        kenwood.playPause()
                    } label: {
                        Image(systemName: kenwood.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .nativeSymbolReplaceTransition()
                            .frame(width: 84, height: 56)
                            .nativeLiquidGlass(
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                                tint: KenwoodPalette.crimson.opacity(0.78),
                                interactive: true
                            )
                    }
                    .buttonStyle(RemotePressStyle())

                    Button {
                        Haptics.tap()
                        kenwood.nextTrack()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .kenwoodGlassPanel(cornerRadius: 18, interactive: true)
                    }
                    .buttonStyle(RemotePressStyle())
                }

                HStack(spacing: 8) {
                    compactTransportButton(symbol: "folder.fill", title: "Папка −") {
                        kenwood.folderDown()
                    }
                    compactTransportButton(symbol: "folder.fill", title: "Папка +") {
                        kenwood.folderUp()
                    }
                    compactTransportButton(
                        symbol: "repeat",
                        title: kenwood.repeatMode == 0 ? "Повтор" : (kenwood.repeatMode == 1 ? "1 трек" : "Все"),
                        active: kenwood.repeatMode > 0
                    ) {
                        kenwood.cycleRepeat()
                    }
                    compactTransportButton(
                        symbol: "shuffle",
                        title: "Микс",
                        active: kenwood.randomEnabled
                    ) {
                        kenwood.toggleRandom()
                    }
                }
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 22)
        }
    }

    private var tunerControlCard: some View {
        NativeGlassContainer(spacing: 8) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    compactTransportButton(symbol: "backward.fill", title: "Seek −") {
                        kenwood.tunerSeekDown()
                    }
                    compactTransportButton(symbol: "minus", title: "Freq −") {
                        kenwood.tunerFreqDown()
                    }
                    compactTransportButton(symbol: "plus", title: "Freq +") {
                        kenwood.tunerFreqUp()
                    }
                    compactTransportButton(symbol: "forward.fill", title: "Seek +") {
                        kenwood.tunerSeekUp()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Пресеты тюнера (удержание — сохранить)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(1...6, id: \.self) { num in
                            let active = kenwood.activeTunerPreset == num
                            Text("P\(num)")
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(active ? .white : .white.opacity(0.84))
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .nativeLiquidGlass(
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                    tint: active ? KenwoodPalette.crimson.opacity(0.76) : nil,
                                    interactive: true
                                )
                                .onTapGesture {
                                    Haptics.tap()
                                    kenwood.tunerSelectPreset(num)
                                }
                                .onLongPressGesture(minimumDuration: 0.6) {
                                    Haptics.heavy()
                                    kenwood.tunerSavePreset(num)
                                    showGestureFeedback("Станция сохранена в P\(num)")
                                }
                        }
                    }
                }
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 22)
        }
    }

    private func compactTransportButton(symbol: String, title: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? .white : .white.opacity(0.84))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .kenwoodGlassPanel(cornerRadius: 14, highlighted: active, interactive: true)
        }
        .buttonStyle(RemotePressStyle())
    }

    private func showGestureFeedback(_ text: String) {
        withAnimation(.easeOut(duration: 0.12)) {
            gestureHint = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            if gestureHint == text {
                withAnimation(.easeOut(duration: 0.2)) {
                    gestureHint = nil
                }
            }
        }
    }

    // MARK: - Вкладка 2: Звук DSP (13-band EQ, Баланс/Фейдер, Сабвуфер/Бас, DTA/Кроссовер)

    private var audioTabContent: some View {
        VStack(spacing: 14) {
            Picker("Раздел звука", selection: $audioSubtab) {
                ForEach(KenwoodAudioSubtab.allCases) { sub in
                    Text(sub.title).tag(sub)
                }
            }
            .pickerStyle(.segmented)

            switch audioSubtab {
            case .eq:
                equalizerSection
            case .fader:
                faderBalanceSection
            case .bass:
                subwooferAndEffectsSection
            case .dtaXover:
                dtaAndCrossoverSection
            }
        }
    }

    private var equalizerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Пресеты эквалайзера")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Сброс (Flat)") {
                        Haptics.tap()
                        kenwood.resetEQFlat()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KenwoodPalette.iceBlue)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(KenwoodEQPreset.allCases) { preset in
                        let selected = preset == kenwood.selectedEQPreset
                        Button {
                            Haptics.tap()
                            kenwood.selectEQPreset(preset)
                        } label: {
                            Text(preset.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selected ? .white : .white.opacity(0.76))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .nativeLiquidGlass(
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                    tint: selected ? KenwoodPalette.crimson.opacity(0.76) : nil,
                                    interactive: true
                                )
                        }
                        .buttonStyle(RemotePressStyle())
                    }
                }
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 22)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("13-полосный графический EQ")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("−9 … +9 dB")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(KenwoodPalette.cyan)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<13, id: \.self) { idx in
                            KenwoodEQBandSlider(
                                label: KenwoodRemoteManager.eqBandLabels[idx],
                                value: kenwood.eqBands[idx]
                            ) { newVal in
                                kenwood.updateEQBand(index: idx, value: newVal)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 22)
        }
    }

    private var faderBalanceSection: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Фейдер и Баланс")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Перетащите точку фокуса звука по салону")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.56))
                }
                Spacer()
                Button("Центр") {
                    Haptics.medium()
                    kenwood.updateFaderBalance(fader: 0, balance: 0)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(KenwoodPalette.iceBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .kenwoodGlassPanel(cornerRadius: 14, interactive: true)
            }

            KenwoodCabinFaderPad(
                fader: kenwood.fader,
                balance: kenwood.balance
            ) { newFader, newBalance in
                kenwood.updateFaderBalance(fader: newFader, balance: newBalance)
            }
            .frame(height: 256)

            HStack(spacing: 10) {
                VStack(spacing: 4) {
                    Text("Фейдер (F / R)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(kenwood.fader == 0 ? "Центр (0)" : (kenwood.fader > 0 ? "Перед +\(kenwood.fader)" : "Зад \(kenwood.fader)"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KenwoodPalette.neonRed)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .kenwoodGlassPanel(cornerRadius: 16)

                VStack(spacing: 4) {
                    Text("Баланс (L / R)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(kenwood.balance == 0 ? "Центр (0)" : (kenwood.balance > 0 ? "Право +\(kenwood.balance)" : "Лево \(kenwood.balance)"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KenwoodPalette.cyan)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .kenwoodGlassPanel(cornerRadius: 16)
            }
        }
        .padding(14)
        .kenwoodGlassPanel(cornerRadius: 22)
    }

    private var subwooferAndEffectsSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { kenwood.subwooferEnabled },
                    set: { Haptics.tap(); kenwood.setSubwooferEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Сабвуфер")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Выход предусилителя / тыл")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .tint(KenwoodPalette.neonRed)

                if kenwood.subwooferEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Уровень сабвуфера")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.82))
                            Spacer()
                            Text("\(kenwood.subwooferLevel > 0 ? "+" : "")\(kenwood.subwooferLevel) dB")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(KenwoodPalette.neonRed)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(kenwood.subwooferLevel) },
                                set: { kenwood.setSubwooferLevel(Int($0.rounded())) }
                            ),
                            in: -15...10,
                            step: 1
                        )
                        .tint(KenwoodPalette.neonRed)
                    }

                    HStack(spacing: 10) {
                        Text("Фаза сабвуфера")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer()
                        kenwoodChip(title: "Normal (0°)", selected: !kenwood.subwooferPhaseReversed) {
                            kenwood.setSubwooferPhase(reversed: false)
                        }
                        kenwoodChip(title: "Reverse (180°)", selected: kenwood.subwooferPhaseReversed) {
                            kenwood.setSubwooferPhase(reversed: true)
                        }
                    }
                }
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 22)

            VStack(alignment: .leading, spacing: 14) {
                Text("Звуковые эффекты")
                    .font(.headline)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Bass Boost")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer()
                        Text(kenwood.bassBoost == 0 ? "Выкл" : "Уровень \(kenwood.bassBoost)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KenwoodPalette.neonRed)
                    }
                    HStack(spacing: 6) {
                        ForEach(0...5, id: \.self) { lvl in
                            let active = kenwood.bassBoost == lvl
                            Button {
                                Haptics.tap()
                                kenwood.setBassBoost(lvl)
                            } label: {
                                Text(lvl == 0 ? "OFF" : "\(lvl)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(active ? .white : .white.opacity(0.74))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .nativeLiquidGlass(
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                        tint: active ? KenwoodPalette.crimson.opacity(0.76) : nil,
                                        interactive: true
                                    )
                            }
                            .buttonStyle(RemotePressStyle())
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Тонкомпенсация (Loudness)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                    HStack(spacing: 8) {
                        ForEach([(0, "Выкл"), (1, "Уровень 1"), (2, "Уровень 2")], id: \.0) { pair in
                            let active = kenwood.loudness == pair.0
                            Button {
                                Haptics.tap()
                                kenwood.setLoudness(pair.0)
                            } label: {
                                Text(pair.1)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(active ? .white : .white.opacity(0.74))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .nativeLiquidGlass(
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                        tint: active ? KenwoodPalette.crimson.opacity(0.76) : nil,
                                        interactive: true
                                    )
                            }
                            .buttonStyle(RemotePressStyle())
                        }
                    }
                }

                Toggle(isOn: Binding(
                    get: { kenwood.bassExtend },
                    set: { Haptics.tap(); kenwood.setBassExtend($0) }
                )) {
                    Text("Bass Extend (глубокий бас)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .tint(KenwoodPalette.neonRed)
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 22)
        }
    }

    private func kenwoodChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(selected ? .white : .white.opacity(0.74))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .nativeLiquidGlass(
                    in: Capsule(),
                    tint: selected ? KenwoodPalette.crimson.opacity(0.76) : nil,
                    interactive: true
                )
        }
        .buttonStyle(RemotePressStyle())
    }

    private var dtaAndCrossoverSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Временные задержки (DTA)")
                    .font(.headline)
                    .foregroundStyle(.white)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(KenwoodListeningPosition.allCases) { pos in
                        let active = pos == kenwood.listeningPosition
                        Button {
                            Haptics.tap()
                            kenwood.setListeningPosition(pos)
                        } label: {
                            Text(pos.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(active ? .white : .white.opacity(0.76))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .nativeLiquidGlass(
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                    tint: active ? KenwoodPalette.crimson.opacity(0.76) : nil,
                                    interactive: true
                                )
                        }
                        .buttonStyle(RemotePressStyle())
                    }
                }

                let channelNames = ["Перед левый (FL)", "Перед правый (FR)", "Тыл левый (RL)", "Тыл правый (RR)", "Сабвуфер (SW)"]
                ForEach(0..<channelNames.count, id: \.self) { idx in
                    VStack(spacing: 4) {
                        HStack {
                            Text(channelNames[idx])
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.78))
                            Spacer()
                            Text("\(kenwood.dtaDistancesCm[idx]) см")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KenwoodPalette.iceBlue)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(kenwood.dtaDistancesCm[idx]) },
                                set: { kenwood.updateDTADistance(channel: idx, cm: Int($0.rounded())) }
                            ),
                            in: 0...610,
                            step: 2
                        )
                        .tint(KenwoodPalette.cyan)
                    }
                }
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 22)

            VStack(alignment: .leading, spacing: 12) {
                Text("Кроссовер (HPF / LPF)")
                    .font(.headline)
                    .foregroundStyle(.white)

                xoverFrequencyRow(title: "HPF Фронт", index: kenwood.frontHPFIndex) { idx in
                    kenwood.updateCrossover(frontHPF: idx, rearHPF: kenwood.rearHPFIndex, subLPF: kenwood.subLPFIndex, slopeIdx: kenwood.xoverSlopeIndex)
                }
                xoverFrequencyRow(title: "HPF Тыл", index: kenwood.rearHPFIndex) { idx in
                    kenwood.updateCrossover(frontHPF: kenwood.frontHPFIndex, rearHPF: idx, subLPF: kenwood.subLPFIndex, slopeIdx: kenwood.xoverSlopeIndex)
                }
                xoverFrequencyRow(title: "LPF Сабвуфер", index: kenwood.subLPFIndex) { idx in
                    kenwood.updateCrossover(frontHPF: kenwood.frontHPFIndex, rearHPF: kenwood.rearHPFIndex, subLPF: idx, slopeIdx: kenwood.xoverSlopeIndex)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Крутизна среза (Slope)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    HStack(spacing: 8) {
                        ForEach(0..<KenwoodRemoteManager.crossoverSlopes.count, id: \.self) { sIdx in
                            let slope = KenwoodRemoteManager.crossoverSlopes[sIdx]
                            let active = kenwood.xoverSlopeIndex == sIdx
                            Button {
                                Haptics.tap()
                                kenwood.updateCrossover(frontHPF: kenwood.frontHPFIndex, rearHPF: kenwood.rearHPFIndex, subLPF: kenwood.subLPFIndex, slopeIdx: sIdx)
                            } label: {
                                Text("−\(slope) dB")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(active ? .white : .white.opacity(0.74))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .nativeLiquidGlass(
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                        tint: active ? KenwoodPalette.crimson.opacity(0.76) : nil,
                                        interactive: true
                                    )
                            }
                            .buttonStyle(RemotePressStyle())
                        }
                    }
                }
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 22)
        }
    }

    private func xoverFrequencyRow(title: String, index: Int, onChange: @escaping (Int) -> Void) -> some View {
        let freq = KenwoodRemoteManager.crossoverFrequencies[index]
        return VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(freq == 0 ? "Through (Выкл)" : "\(freq) Hz")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KenwoodPalette.neonRed)
            }
            Slider(
                value: Binding(
                    get: { Double(index) },
                    set: { onChange(Int($0.rounded())) }
                ),
                in: 0...Double(KenwoodRemoteManager.crossoverFrequencies.count - 1),
                step: 1
            )
            .tint(KenwoodPalette.neonRed)
        }
    }

    // MARK: - Вкладка 3: Пульт пассажира KENWOOD (D-Pad + Цифры + Кнопки магнитолы)

    private var keypadTabContent: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Профиль кнопок")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                kenwoodChip(title: "1DIN / 2DIN", selected: !kenwood.multimediaRemocon) {
                    kenwood.multimediaRemocon = false
                }
                kenwoodChip(title: "Multimedia", selected: kenwood.multimediaRemocon) {
                    kenwood.multimediaRemocon = true
                }
            }
            .padding(12)
            .kenwoodGlassPanel(cornerRadius: 18)

            NativeGlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    remoconTile("SRC", symbol: "square.stack.fill") { kenwood.cycleSource() }
                    remoconTile("ATT", symbol: "speaker.slash.fill") { kenwood.toggleMute() }
                    remoconTile("AUDIO", symbol: "slider.horizontal.3") { kenwood.sendRemoconKey(.audio) }
                    remoconTile("MENU", symbol: "line.3.horizontal") { kenwood.sendRemoconKey(.menu) }
                }
            }

            // Фирменный круговой джойстик KENWOOD в нативном Liquid Glass
            NativeGlassContainer(spacing: 12) {
                VStack(spacing: 10) {
                    remoconCircle(symbol: "chevron.up", size: 58) { kenwood.sendRemoconKey(.up) }
                    HStack(spacing: 14) {
                        remoconCircle(symbol: "chevron.left", size: 58) { kenwood.sendRemoconKey(.left) }
                        Button {
                            Haptics.medium()
                            kenwood.sendRemoconKey(.enter)
                        } label: {
                            Text("ENT")
                                .font(.headline.weight(.black))
                                .foregroundStyle(.white)
                                .frame(width: 74, height: 74)
                                .kenwoodGlassCircle(accent: true, interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())
                        remoconCircle(symbol: "chevron.right", size: 58) { kenwood.sendRemoconKey(.right) }
                    }
                    remoconCircle(symbol: "chevron.down", size: 58) { kenwood.sendRemoconKey(.down) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .kenwoodGlassPanel(cornerRadius: 26)
            }

            NativeGlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    remoconTile("Назад", symbol: "arrow.uturn.backward") { kenwood.sendRemoconKey(.back) }
                    remoconTile("FM", symbol: "radio.fill") { kenwood.sendRemoconKey(.fm) }
                    remoconTile("AM", symbol: "antenna.radiowaves.left.and.right") { kenwood.sendRemoconKey(.am) }
                    remoconTile("2-Zone", symbol: "rectangle.split.2x1.fill") { kenwood.sendRemoconKey(.twoZone) }
                }
            }

            NativeGlassContainer(spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(1...9, id: \.self) { digit in
                        Button {
                            Haptics.tap()
                            kenwood.sendRemoconKey(.digit(digit))
                        } label: {
                            Text("\(digit)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .kenwoodGlassPanel(cornerRadius: 16, interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())
                    }

                    remoconTile("Direct", symbol: "magnifyingglass") { kenwood.sendRemoconKey(.direct) }

                    Button {
                        Haptics.tap()
                        kenwood.sendRemoconKey(.digit(0))
                    } label: {
                        Text("0")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .kenwoodGlassPanel(cornerRadius: 16, interactive: true)
                    }
                    .buttonStyle(RemotePressStyle())

                    remoconTile("Top", symbol: "house.fill") { kenwood.sendRemoconKey(.topMenu) }
                }
                .padding(12)
                .kenwoodGlassPanel(cornerRadius: 22)
            }
        }
    }

    private func remoconTile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .kenwoodGlassPanel(cornerRadius: 15, interactive: true)
        }
        .buttonStyle(RemotePressStyle())
    }

    private func remoconCircle(symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .kenwoodGlassCircle(interactive: true)
        }
        .buttonStyle(RemotePressStyle())
    }

    // MARK: - Вкладка 4: Подсветка RGB и настройки авто

    private var colorAndSetupTabContent: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Подсветка панели KENWOOD")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Circle()
                        .fill(illuminationColor)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1.5))
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                    ForEach(KenwoodColorPreset.presets) { preset in
                        let selected = kenwood.selectedColorPresetId == preset.id
                        Button {
                            Haptics.tap()
                            kenwood.selectColorPreset(preset)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(preset.swiftUIColor)
                                    .frame(width: 38, height: 38)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(selected ? Color.white : Color.white.opacity(0.22), lineWidth: selected ? 2.5 : 1)
                                    )
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(preset.r + preset.g + preset.b > 60 ? .black : .white)
                                }
                            }
                        }
                        .buttonStyle(RemotePressStyle())
                    }
                }
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 22)

            VStack(alignment: .leading, spacing: 10) {
                Text("Свой цвет (RGB 0–31)")
                    .font(.headline)
                    .foregroundStyle(.white)

                rgbRow(label: "Красный (R)", value: kenwood.customRed, tint: KenwoodPalette.neonRed) { r in
                    kenwood.applyCustomRGB(r: r, g: kenwood.customGreen, b: kenwood.customBlue)
                }
                rgbRow(label: "Зелёный (G)", value: kenwood.customGreen, tint: .green) { g in
                    kenwood.applyCustomRGB(r: kenwood.customRed, g: g, b: kenwood.customBlue)
                }
                rgbRow(label: "Синий (B)", value: kenwood.customBlue, tint: KenwoodPalette.cyan) { b in
                    kenwood.applyCustomRGB(r: kenwood.customRed, g: kenwood.customGreen, b: b)
                }
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 22)

            VStack(alignment: .leading, spacing: 12) {
                Text("Автомобиль и синхронизация")
                    .font(.headline)
                    .foregroundStyle(.white)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(KenwoodCarType.allCases) { type in
                        let active = type == kenwood.carType
                        Button {
                            Haptics.tap()
                            kenwood.setCarType(type)
                        } label: {
                            Text(type.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(active ? .white : .white.opacity(0.76))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .nativeLiquidGlass(
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                    tint: active ? KenwoodPalette.crimson.opacity(0.76) : nil,
                                    interactive: true
                                )
                        }
                        .buttonStyle(RemotePressStyle())
                    }
                }

                NativeGlassContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            Haptics.medium()
                            kenwood.syncClockAndDate()
                        } label: {
                            Label("Синхр. часы", systemImage: "clock.arrow.2.circlepath")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(KenwoodPrimaryButtonStyle())

                        Button {
                            Haptics.tap()
                            kenwood.switchBTAudioDevice()
                        } label: {
                            Label("Смена BT", systemImage: "arrow.left.arrow.right")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(KenwoodGlassButtonStyle())
                    }
                }
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 22)
        }
    }

    private func rgbRow(label: String, value: Int, tint: Color, onChange: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Text("\(value)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0.rounded())) }
                ),
                in: 0...31,
                step: 1
            )
            .tint(tint)
        }
    }
}

// MARK: - Фирменная круглая ручка громкости KENWOOD (Rotary Volume Knob)

private struct KenwoodRotaryVolumeKnob: View {
    let volume: Int
    let isMuted: Bool
    let ringColor: Color
    let onStepUp: () -> Void
    let onStepDown: () -> Void
    let onTapMute: () -> Void

    @State private var lastDragY: CGFloat?

    private var progress: CGFloat {
        isMuted ? 0 : CGFloat(volume) / 35.0
    }

    var body: some View {
        ZStack {
            // Фоновое кольцо
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(90))

            // Активная дуга подсветки
            Circle()
                .trim(from: 0.15, to: 0.15 + 0.70 * progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(90))
                .shadow(color: ringColor.opacity(0.8), radius: 6)

            // Стеклянный корпус ручки в нативном Liquid Glass
            VStack(spacing: 1) {
                Text(isMuted ? "ATT" : "\(volume)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(isMuted ? KenwoodPalette.neonRed : .white)
                Text("VOL")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(width: 60, height: 60)
            .nativeLiquidGlass(in: Circle(), interactive: true)
        }
        .frame(width: 78, height: 78)
        .contentShape(Circle())
        .onTapGesture {
            Haptics.tap()
            onTapMute()
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    if let prev = lastDragY {
                        let dy = prev - value.location.y
                        if dy >= 10 {
                            Haptics.tap()
                            onStepUp()
                            lastDragY = value.location.y
                        } else if dy <= -10 {
                            Haptics.tap()
                            onStepDown()
                            lastDragY = value.location.y
                        }
                    } else {
                        lastDragY = value.location.y
                    }
                }
                .onEnded { _ in
                    lastDragY = nil
                }
        )
    }
}

// MARK: - Жестовая поверхность KENWOOD

private struct KenwoodGesturePad: View {
    let hintText: String?
    let isRadio: Bool
    let glowColor: Color
    let onTap: () -> Void
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    let onSwipeUp: () -> Void
    let onSwipeDown: () -> Void

    @State private var dragPoint: CGPoint?

    var body: some View {
        ZStack {
            if let pt = dragPoint {
                Circle()
                    .fill(glowColor.opacity(0.28))
                    .frame(width: 78, height: 78)
                    .blur(radius: 12)
                    .position(pt)
            }

            VStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(KenwoodPalette.neonRed)

                Text(hintText ?? (isRadio ? "Свайп ◄► поиск станции · ▲▼ громкость" : "Свайп ◄► трек · ▲▼ громкость · Тап пауза"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hintText != nil ? KenwoodPalette.iceBlue : .white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragPoint = value.location
                }
                .onEnded { value in
                    dragPoint = nil
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let dist = hypot(dx, dy)
                    if dist < 18 {
                        Haptics.medium()
                        onTap()
                    } else if abs(dx) >= abs(dy) {
                        Haptics.tap()
                        if dx < 0 { onSwipeLeft() } else { onSwipeRight() }
                    } else {
                        Haptics.tap()
                        if dy < 0 { onSwipeUp() } else { onSwipeDown() }
                    }
                }
        )
    }
}

// MARK: - Вертикальный ползунок полосы 13-band EQ (стиль KENWOOD)

private struct KenwoodEQBandSlider: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(value == 0 ? .white.opacity(0.5) : (value > 0 ? KenwoodPalette.neonRed : KenwoodPalette.cyan))
                .frame(width: 30)

            GeometryReader { geo in
                let h = geo.size.height
                let normalized = CGFloat(value + 9) / 18.0
                let thumbY = h * (1.0 - normalized)
                let midY = h * 0.5

                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 6)

                    Capsule()
                        .fill(value >= 0 ? KenwoodPalette.neonRed : KenwoodPalette.cyan)
                        .frame(width: 6, height: max(abs(thumbY - midY), 4))
                        .position(x: geo.size.width / 2, y: (thumbY + midY) / 2)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: (value >= 0 ? KenwoodPalette.crimson : KenwoodPalette.cyan).opacity(0.75), radius: 6)
                        .position(x: geo.size.width / 2, y: min(max(thumbY, 9), h - 9))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let ratio = 1.0 - min(max(drag.location.y / h, 0), 1)
                            let mapped = Int((ratio * 18.0).rounded()) - 9
                            if mapped != value {
                                Haptics.tap()
                                onChange(mapped)
                            }
                        }
                )
            }
            .frame(width: 34, height: 150)

            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
    }
}

// MARK: - 2D-карта салона авто KENWOOD для Фейдера и Баланса

private struct KenwoodCabinFaderPad: View {
    let fader: Int   // -15 (Зад) ... +15 (Перед)
    let balance: Int // -15 (Лево) ... +15 (Право)
    let onChange: (Int, Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let xPos = CGFloat(balance + 15) / 30.0 * (w - 36) + 18
            let yPos = CGFloat(15 - fader) / 30.0 * (h - 36) + 18

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.38))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Стилизованный контур салона автомобиля
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(KenwoodPalette.cyan.opacity(0.22), lineWidth: 1.5)
                    .frame(width: min(w * 0.54, 160), height: h * 0.72)

                // Крест осей
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: 16))
                    p.addLine(to: CGPoint(x: w / 2, y: h - 16))
                    p.move(to: CGPoint(x: 16, y: h / 2))
                    p.addLine(to: CGPoint(x: w - 16, y: h / 2))
                }
                .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                VStack {
                    Text("FRONT")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(KenwoodPalette.iceBlue.opacity(0.65))
                        .padding(.top, 8)
                    Spacer()
                    Text("REAR")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(KenwoodPalette.iceBlue.opacity(0.65))
                        .padding(.bottom, 8)
                }

                HStack {
                    Text("L")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.leading, 10)
                    Spacer()
                    Text("R")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.trailing, 10)
                }

                ZStack {
                    Circle()
                        .fill(KenwoodPalette.crimson.opacity(0.28))
                        .frame(width: 60, height: 60)
                    Circle()
                        .fill(KenwoodPalette.neonRed)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                }
                .position(x: xPos, y: yPos)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let clampedX = min(max(drag.location.x, 18), w - 18)
                        let clampedY = min(max(drag.location.y, 18), h - 18)
                        let nx = (clampedX - 18) / (w - 36)
                        let ny = (clampedY - 18) / (h - 36)
                        let newBal = Int((nx * 30.0).rounded()) - 15
                        let newFad = 15 - Int((ny * 30.0).rounded())
                        if newBal != balance || newFad != fader {
                            onChange(newFad, newBal)
                        }
                    }
            )
        }
    }
}

// MARK: - Экран выбора и подключения магнитолы KENWOOD (Bluetooth MFi + BLE)

private struct KenwoodConnectionSheet: View {
    @ObservedObject var kenwood: KenwoodRemoteManager
    let glowColor: Color
    @Environment(\.dismiss) private var dismiss
    @State private var showAllBLE = false

    var body: some View {
        NativeNavigationContainer {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(kenwood.isConnected ? KenwoodPalette.cyan : KenwoodPalette.amber)
                        .frame(width: 10, height: 10)
                    Text(kenwood.bluetoothStateText ?? kenwood.statusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer()
                    if kenwood.isScanning {
                        ProgressView().tint(KenwoodPalette.neonRed)
                    }
                }
                .padding(14)
                .kenwoodGlassPanel(cornerRadius: 18)

                NativeGlassContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap()
                            kenwood.refreshDevices()
                        } label: {
                            Label("Искать", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .nativeGlassButton(prominent: true, tint: KenwoodPalette.crimson)
                        .controlSize(.large)

                        Button {
                            Haptics.tap()
                            kenwood.showSystemBluetoothPicker()
                        } label: {
                            Label("Выбрать BT", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .nativeGlassButton(prominent: false)
                        .controlSize(.large)
                    }
                }

                if kenwood.isConnected {
                    Button(role: .destructive) {
                        Haptics.tap()
                        kenwood.disconnect()
                    } label: {
                        Text("Отключиться от \(kenwood.connectedDeviceName ?? "KENWOOD")")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                    }
                    .nativeGlassButton(prominent: false, tint: KenwoodPalette.neonRed)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        if kenwood.discoveredDevices.isEmpty {
                            if let audioName = kenwood.connectedBluetoothAudioName {
                                bluetoothAudioOnlyCard(
                                    deviceName: audioName,
                                    portType: kenwood.connectedBluetoothAudioPortType ?? "Bluetooth Audio"
                                )
                            } else {
                                NativeEmptyStateView(
                                    title: "Ресивер KENWOOD не обнаружен",
                                    systemImage: "car.fill",
                                    description: "Подключите iPhone к магнитоле в «Настройках → Bluetooth» или по кабелю USB, затем нажмите «Искать»."
                                ) {
                                    EmptyView()
                                }
                                .padding(12)
                                .kenwoodGlassPanel(cornerRadius: 20)
                            }
                        } else {
                            ForEach(kenwood.discoveredDevices) { device in
                                deviceRowButton(device)
                            }
                        }

                        if !kenwood.nearbyBLEDevices.isEmpty {
                            DisclosureGroup(isExpanded: $showAllBLE) {
                                VStack(spacing: 8) {
                                    ForEach(kenwood.nearbyBLEDevices) { device in
                                        deviceRowButton(device)
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                HStack {
                                    Text("Другие BLE-устройства рядом")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.72))
                                    Spacer()
                                    Text("\(kenwood.nearbyBLEDevices.count)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(KenwoodPalette.iceBlue)
                                }
                            }
                            .tint(KenwoodPalette.iceBlue)
                            .padding(14)
                            .kenwoodGlassPanel(cornerRadius: 18)
                        }
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .nativeGlassSheetContainerBackground()
            .navigationTitle("Подключение KENWOOD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .nativePresentationSheet()
        .preferredColorScheme(.dark)
        .onAppear {
            kenwood.refreshDevices()
        }
    }

    private func deviceRowButton(_ device: KenwoodDiscoveredDevice) -> some View {
        Button {
            Haptics.medium()
            kenwood.connect(to: device)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: device.transport == .mfiBluetooth ? "car.fill" : "wave.3.right")
                    .font(.title3)
                    .foregroundStyle(KenwoodPalette.neonRed)
                    .frame(width: 42, height: 42)
                    .kenwoodGlassCircle()

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(device.transport.rawValue) · \(device.detail)")
                        .font(.caption2)
                        .foregroundStyle(KenwoodPalette.iceBlue)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(14)
            .kenwoodGlassPanel(cornerRadius: 18, interactive: true)
        }
        .buttonStyle(RemotePressStyle())
    }

    private func bluetoothAudioOnlyCard(deviceName: String, portType: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.title3)
                    .foregroundStyle(KenwoodPalette.cyan)
                    .frame(width: 42, height: 42)
                    .kenwoodGlassCircle()

                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(portType) подключён · канал OpenLink (iAP2) не открыт")
                        .font(.caption)
                        .foregroundStyle(KenwoodPalette.amber)
                }
                Spacer()
            }

            Divider().overlay(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 6) {
                Text("Что проверить на магнитоле:")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.92))
                Text("1. Откройте MENU → SETTINGS → REMOTE APP → SELECT → iOS → YES.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                Text("2. Выберите источник BT AUDIO или iPod BT (либо подключите iPhone по USB-кабелю).")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                Text("3. Переподключите Bluetooth и нажмите «Искать». Диалог «Выбрать BT» показывает только новые несопряжённые аксессуары.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .padding(16)
        .kenwoodGlassPanel(cornerRadius: 20)
    }
}
