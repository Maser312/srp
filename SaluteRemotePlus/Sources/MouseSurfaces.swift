import SwiftUI

// MARK: - Режим курсора (Трекпад — нативный Liquid Glass + 3 шкалы прокрутки)

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
        let padShape = RoundedRectangle(cornerRadius: 32, style: .continuous)

        VStack(spacing: 14) {
            HStack(spacing: 10) {
                // Левая вертикальная шкала прокрутки
                MinimalScrollTickStrip(axis: .vertical) { delta in
                    onVerticalScroll(delta)
                }
                .frame(width: 34)

                // Центральная сенсорная панель трекпада с нативным Liquid Glass
                ZStack {
                    if touchPoint == nil && !clickFlash {
                        VStack(spacing: 14) {
                            Image(systemName: "hand.draw.fill")
                                .font(.system(size: 46, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.32))

                            Text("Водите пальцем по панели и управляйте курсором")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.38))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 22)
                        }
                        .allowsHitTesting(false)
                    }

                    if let pt = touchPoint {
                        Circle()
                            .fill(Color.white.opacity(isHoldingClick ? 0.28 : 0.16))
                            .frame(width: isHoldingClick ? 76 : 56, height: isHoldingClick ? 76 : 56)
                            .blur(radius: isHoldingClick ? 12 : 10)
                            .position(pt)
                            .allowsHitTesting(false)
                    }

                    if isHoldingClick {
                        VStack {
                            Text("Перетаскивание (ЛКМ зажата)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .nativeLiquidGlass(in: Capsule(), tint: Color.white.opacity(0.18))
                                .padding(.top, 14)
                            Spacer()
                        }
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                        .allowsHitTesting(false)
                    } else if clickFlash {
                        Text("Клик")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .nativeLiquidGlass(in: Capsule(), tint: Color.white.opacity(0.20))
                            .transition(.scale(scale: 0.84).combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .nativeLiquidGlass(
                    in: padShape,
                    tint: isHoldingClick ? Color.white.opacity(0.14) : nil,
                    interactive: true
                )
                .scaleEffect(isHoldingClick ? 0.985 : 1.0)
                .animation(NativeLiquidSpring.press, value: isHoldingClick)
                .contentShape(padShape)
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

                // Правая вертикальная шкала прокрутки
                MinimalScrollTickStrip(axis: .vertical) { delta in
                    onVerticalScroll(delta)
                }
                .frame(width: 34)
            }

            // Нижняя горизонтальная шкала прокрутки
            MinimalScrollTickStrip(axis: .horizontal) { delta in
                onHorizontalScroll(delta)
            }
            .frame(height: 30)
            .padding(.horizontal, 44)
        }
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
                withAnimation(NativeLiquidSpring.press) {
                    isHoldingClick = true
                }
                Haptics.medium()
                onClickDown()
            }
        }
    }

    private func releaseHoldClick() {
        guard isHoldingClick else { return }
        withAnimation(NativeLiquidSpring.release) {
            isHoldingClick = false
        }
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
        withAnimation(NativeLiquidSpring.press) {
            clickFlash = true
        }
        flashTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(NativeLiquidSpring.release) {
                    clickFlash = false
                }
            }
        }
    }
}

// MARK: - Режим Аэромыши (круглая кнопка клика Liquid Glass + 3 шкалы прокрутки)

struct AirMouseSurfaceView: View {
    let onMove: (Float, Float) -> Void
    let onVerticalScroll: (Float) -> Void
    let onHorizontalScroll: (Float) -> Void
    let onClickDown: () -> Void
    let onClickUp: () -> Void

    @StateObject private var airMouse = AirMouseController()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("SaluteRemotePlus.airMouseSensitivity") private var savedSensitivity: Double = 1.0
    @State private var userPaused = false

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                MinimalScrollTickStrip(axis: .vertical) { delta in
                    onVerticalScroll(delta)
                }
                .frame(width: 40)

                ZStack {
                    if !airMouse.isAvailable {
                        VStack(spacing: 8) {
                            Image(systemName: "gyroscope")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))
                            Text("Гироскоп недоступен")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    } else {
                        AirMouseCenterCircleButton(
                            isPaused: userPaused,
                            onDown: onClickDown,
                            onUp: onClickUp
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                MinimalScrollTickStrip(axis: .vertical) { delta in
                    onVerticalScroll(delta)
                }
                .frame(width: 40)
            }

            MinimalScrollTickStrip(axis: .horizontal) { delta in
                onHorizontalScroll(delta)
            }
            .frame(height: 30)
            .padding(.horizontal, 48)
        }
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
}

private struct AirMouseCenterCircleButton: View {
    let isPaused: Bool
    let onDown: () -> Void
    let onUp: () -> Void

    @GestureState private var gesturePressed = false
    @State private var isPressed = false

    var body: some View {
        Image(systemName: isPaused ? "pause.fill" : "hand.tap.fill")
            .font(.system(size: 46, weight: .regular))
            .foregroundStyle(.white.opacity(0.96))
            .frame(width: 196, height: 196)
            .nativeLiquidGlass(
                in: Circle(),
                tint: isPressed ? Color.white.opacity(0.18) : nil,
                interactive: true
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(NativeLiquidSpring.press, value: isPressed)
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

// MARK: - Минималистичная 5-линейная шкала прокрутки с упругим откликом

private struct MinimalScrollTickStrip: View {
    enum Axis { case vertical, horizontal }

    let axis: Axis
    let onScroll: (Float) -> Void

    @GestureState private var active = false
    @State private var lastCoord: CGFloat?
    @State private var hapticAccum: CGFloat = 0

    var body: some View {
        ZStack {
            Color.clear
            if axis == .vertical {
                VStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(active ? 0.96 : 0.45))
                            .frame(width: active ? 17 : 14, height: 2.0)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(active ? 0.96 : 0.45))
                            .frame(width: 2.0, height: active ? 17 : 14)
                    }
                }
            }
        }
        .animation(NativeLiquidSpring.press, value: active)
        .contentShape(Rectangle())
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
