import SwiftUI

// MARK: - Режим курсора (Трекпад / Мышь)

struct TrackpadSurfaceView: View {
    let onMove: (Float, Float) -> Void
    let onVerticalScroll: (Float) -> Void
    let onHorizontalScroll: (Float) -> Void
    let onClick: () -> Void
    let onClickDown: () -> Void
    let onClickUp: () -> Void

    @GestureState private var touchActive = false
    @State private var startPoint: CGPoint?
    @State private var lastPoint: CGPoint?
    @State private var touchPoint: CGPoint?
    @State private var totalTravel: CGFloat = 0
    @State private var touchStartedAt: Date = .distantPast
    @State private var isHoldingClick = false
    @State private var holdTask: Task<Void, Never>?
    @State private var clickFlash = false
    @State private var flashTask: Task<Void, Never>?
    @State private var gestureEndedNormally = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                // Основная сенсорная поверхность трекпада
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.05),
                                    SberPalette.teal.opacity(0.04),
                                    Color.black.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    isHoldingClick
                                        ? SberPalette.glassAccentBorder
                                        : LinearGradient(
                                            colors: [Color.white.opacity(0.18), SberPalette.teal.opacity(0.12)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                    lineWidth: isHoldingClick ? 1.5 : 1
                                )
                        )

                    // Едва заметная сетка-подсказка в стиле Сбера
                    if touchPoint == nil && !clickFlash {
                        VStack(spacing: 6) {
                            Image(systemName: "cursorarrow.motionlines")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(SberPalette.brandGradient)
                                .opacity(0.75)
                            Text("Водите пальцем · Тап = клик")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.45))
                            Text("Удержание = зажать ЛКМ")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.28))
                        }
                        .allowsHitTesting(false)
                    }

                    // Светящийся ореол под пальцем
                    if let pt = touchPoint {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        (isHoldingClick ? SberPalette.lime : SberPalette.brightGreen).opacity(0.55),
                                        SberPalette.teal.opacity(0.22),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: isHoldingClick ? 44 : 34
                                )
                            )
                            .frame(width: isHoldingClick ? 88 : 68, height: isHoldingClick ? 88 : 68)
                            .position(pt)
                            .allowsHitTesting(false)
                    }

                    if isHoldingClick {
                        VStack {
                            Text("ЛКМ зажата · можно перетаскивать")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(SberPalette.accentButtonGradient.opacity(0.85))
                                )
                                .padding(.top, 8)
                            Spacer()
                        }
                        .allowsHitTesting(false)
                    } else if clickFlash {
                        HStack(spacing: 5) {
                            Image(systemName: "hand.tap.fill")
                            Text("Клик")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(SberPalette.accentButtonGradient.opacity(0.82))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        )
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .updating($touchActive) { _, state, _ in
                            state = true
                        }
                        .onChanged { value in
                            touchPoint = value.location
                            if startPoint == nil {
                                gestureEndedNormally = false
                                startPoint = value.startLocation
                                lastPoint = value.startLocation
                                totalTravel = 0
                                touchStartedAt = Date()
                                scheduleHoldClick()
                            }

                            if let prev = lastPoint {
                                let rawDx = value.location.x - prev.x
                                let rawDy = value.location.y - prev.y
                                let step = hypot(rawDx, rawDy)
                                if step >= 0.4 {
                                    totalTravel += step
                                    lastPoint = value.location
                                    if totalTravel >= 10 && !isHoldingClick {
                                        holdTask?.cancel()
                                        holdTask = nil
                                    }
                                    // Ускорение курсора: плавная точность на малой скорости, быстрый размах на высокой
                                    let accel = 1.35 + min(step * 0.055, 1.55)
                                    onMove(Float(rawDx * accel), Float(rawDy * accel))
                                }
                            }
                        }
                        .onEnded { _ in
                            gestureEndedNormally = true
                            holdTask?.cancel()
                            holdTask = nil

                            let elapsed = Date().timeIntervalSince(touchStartedAt)
                            let wasTap = !isHoldingClick && totalTravel < 11 && elapsed < 0.32

                            if isHoldingClick {
                                releaseHoldClick()
                            } else if wasTap {
                                Haptics.tap()
                                onClick()
                                triggerClickFlash()
                            }

                            resetTouchState()
                        }
                )
                .onChange(of: touchActive) { active in
                    if !active {
                        holdTask?.cancel()
                        holdTask = nil
                        if isHoldingClick {
                            releaseHoldClick()
                        }
                        DispatchQueue.main.async {
                            if !touchActive && !gestureEndedNormally {
                                resetTouchState()
                            }
                        }
                    }
                }

                // Вертикальная полоса прокрутки вдоль правого края
                ScrollRailView(axis: .vertical) { delta in
                    onVerticalScroll(delta)
                }
                .frame(width: 30)
            }

            // Нижняя строка: горизонтальная прокрутка + физическая кнопка ЛКМ
            HStack(spacing: 6) {
                ScrollRailView(axis: .horizontal) { delta in
                    onHorizontalScroll(delta)
                }
                .frame(height: 26)

                MouseClickHoldButton(
                    width: 64,
                    height: 26,
                    title: "ЛКМ",
                    onDown: onClickDown,
                    onUp: onClickUp
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .onDisappear {
            holdTask?.cancel()
            holdTask = nil
            flashTask?.cancel()
            flashTask = nil
            if isHoldingClick {
                releaseHoldClick()
            }
            resetTouchState()
        }
    }

    private func scheduleHoldClick() {
        holdTask?.cancel()
        holdTask = Task {
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard startPoint != nil, totalTravel < 10, !isHoldingClick else { return }
                isHoldingClick = true
                Haptics.medium()
                onClickDown()
            }
        }
    }

    private func releaseHoldClick() {
        guard isHoldingClick else { return }
        isHoldingClick = false
        onClickUp()
    }

    private func resetTouchState() {
        startPoint = nil
        lastPoint = nil
        touchPoint = nil
        totalTravel = 0
    }

    private func triggerClickFlash() {
        flashTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            clickFlash = true
        }
        flashTask = Task {
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.16)) {
                    clickFlash = false
                }
            }
        }
    }
}

// MARK: - Режим Аэромыши (управление курсором через гироскоп)

struct AirMouseSurfaceView: View {
    let onMove: (Float, Float) -> Void
    let onVerticalScroll: (Float) -> Void
    let onClickDown: () -> Void
    let onClickUp: () -> Void

    @StateObject private var airMouse = AirMouseController()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("SaluteRemotePlus.airMouseSensitivity") private var savedSensitivity: Double = 1.0
    @State private var userPaused = false

    private let sensitivityPresets: [(label: String, value: Double)] = [
        ("0.7×", 0.7),
        ("1.0×", 1.0),
        ("1.5×", 1.5)
    ]

    private var currentSensitivityLabel: String {
        let closest = sensitivityPresets.min { abs($0.value - savedSensitivity) < abs($1.value - savedSensitivity) }
        return closest?.label ?? "1.0×"
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 8) {
                if !airMouse.isAvailable {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "gyroscope")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(SberPalette.coral)
                        Text("Гироскоп недоступен на этом устройстве")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)
                    Spacer()
                } else {
                    // Центральная область с живым индикатором наклона и большой кнопкой клика
                    ZStack {
                        // Внешнее стеклянное кольцо
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        SberPalette.brightGreen.opacity(userPaused ? 0.16 : 0.42),
                                        SberPalette.teal.opacity(userPaused ? 0.12 : 0.35)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                            .frame(width: 136, height: 136)

                        // Внутреннее кольцо
                        Circle()
                            .strokeBorder(.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .frame(width: 108, height: 108)

                        // Движущийся светящийся маркер наклона гироскопа
                        if !userPaused {
                            Circle()
                                .fill(SberPalette.brandGradient)
                                .frame(width: 12, height: 12)
                                .shadow(color: SberPalette.brightGreen.opacity(0.85), radius: 6)
                                .offset(x: airMouse.tiltX * 56, y: airMouse.tiltY * 56)
                                .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.78), value: airMouse.tiltX)
                                .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.78), value: airMouse.tiltY)
                                .allowsHitTesting(false)
                        }

                        // Крупная тактильная кнопка «Клик / Удержать» в центре
                        AirMouseTriggerButton(
                            isPaused: userPaused,
                            onDown: onClickDown,
                            onUp: onClickUp
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Нижняя строка настроек аэромыши: Пауза и Чувствительность
                    HStack(spacing: 8) {
                        Button {
                            Haptics.tap()
                            userPaused.toggle()
                            syncMotionState()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: userPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(userPaused ? "Включить" : "Пауза")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(userPaused ? .white : SberPalette.lime)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(
                                Capsule()
                                    .fill(userPaused ? Color.white.opacity(0.10) : SberPalette.green.opacity(0.28))
                                    .overlay(
                                        Capsule().strokeBorder(
                                            userPaused ? Color.white.opacity(0.18) : SberPalette.brightGreen.opacity(0.55),
                                            lineWidth: 1
                                        )
                                    )
                            )
                        }
                        .buttonStyle(RemotePressStyle())

                        Button {
                            Haptics.tap()
                            cycleSensitivity()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "dial.medium.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Скорость \(currentSensitivityLabel)")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                            )
                        }
                        .buttonStyle(RemotePressStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Вертикальная полоса прокрутки вдоль правого края
            ScrollRailView(axis: .vertical) { delta in
                onVerticalScroll(delta)
            }
            .frame(width: 30)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .onAppear {
            airMouse.sensitivity = savedSensitivity
            syncMotionState()
        }
        .onDisappear {
            airMouse.stop()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                syncMotionState()
            } else {
                airMouse.stop()
            }
        }
    }

    private func syncMotionState() {
        if !userPaused && scenePhase == .active {
            airMouse.sensitivity = savedSensitivity
            airMouse.start { dx, dy in
                onMove(dx, dy)
            }
        } else {
            airMouse.stop()
        }
    }

    private func cycleSensitivity() {
        let idx = sensitivityPresets.firstIndex { abs($0.value - savedSensitivity) < 0.05 } ?? 1
        let next = sensitivityPresets[(idx + 1) % sensitivityPresets.count]
        savedSensitivity = next.value
        airMouse.sensitivity = next.value
    }
}

private struct AirMouseTriggerButton: View {
    let isPaused: Bool
    let onDown: () -> Void
    let onUp: () -> Void

    @GestureState private var gesturePressed = false
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: isPaused ? "pause.circle.fill" : "hand.tap.fill")
                .font(.system(size: 22, weight: .bold))
            Text(isPaused ? "Пауза" : "Клик")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white)
        .frame(width: 82, height: 82)
        .background(LiquidGlassCircle(highlighted: isPressed, accent: !isPaused))
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .contentShape(Circle())
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
    }
}

// MARK: - Полосы прокрутки и кнопка ЛКМ

private struct ScrollRailView: View {
    enum Axis { case vertical, horizontal }

    let axis: Axis
    let onScroll: (Float) -> Void

    @GestureState private var active = false
    @State private var lastCoord: CGFloat?
    @State private var hapticAccum: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(active ? SberPalette.teal.opacity(0.22) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            active ? SberPalette.brightGreen.opacity(0.65) : Color.white.opacity(0.14),
                            lineWidth: 1
                        )
                )

            if axis == .vertical {
                VStack(spacing: 6) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(active ? 0.55 : 0.22))
                            .frame(width: 10, height: 2)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(active ? SberPalette.lime : .white.opacity(0.32))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8, weight: .bold))
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(active ? 0.55 : 0.22))
                            .frame(width: 2, height: 8)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(active ? SberPalette.lime : .white.opacity(0.32))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($active) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    let coord = axis == .vertical ? value.location.y : value.location.x
                    if let prev = lastCoord {
                        let delta = coord - prev
                        if abs(delta) >= 1.5 {
                            lastCoord = coord
                            hapticAccum += abs(delta)
                            if hapticAccum >= 26 {
                                hapticAccum = 0
                                Haptics.tap()
                            }
                            // Естественная прокрутка для Android/StarOS AXIS_VSCROLL / AXIS_HSCROLL
                            let scaled: Float = axis == .vertical
                                ? Float(delta * 0.085)
                                : Float(-delta * 0.085)
                            onScroll(scaled)
                        }
                    } else {
                        lastCoord = coord
                        hapticAccum = 0
                    }
                }
                .onEnded { _ in
                    lastCoord = nil
                    hapticAccum = 0
                }
        )
        .onChange(of: active) { isActive in
            if !isActive {
                lastCoord = nil
                hapticAccum = 0
            }
        }
    }
}

private struct MouseClickHoldButton: View {
    let width: CGFloat
    let height: CGFloat
    let title: String
    let onDown: () -> Void
    let onUp: () -> Void

    @GestureState private var gesturePressed = false
    @State private var isPressed = false

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPressed ? SberPalette.accentButtonGradient : LinearGradient(colors: [SberPalette.green.opacity(0.55), SberPalette.teal.opacity(0.45)], startPoint: .leading, endPoint: .trailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(SberPalette.glassAccentBorder.opacity(isPressed ? 1.0 : 0.65), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    }
}
