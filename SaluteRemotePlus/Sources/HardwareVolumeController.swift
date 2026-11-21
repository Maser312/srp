import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer

/// Невидимый мост для перехвата аппаратных кнопок громкости iPhone (+ / -)
/// на экране пульта ТВ. Использует системный `MPVolumeView` (скрывает HUD громкости iOS)
/// и KVO на `AVAudioSession.outputVolume` с возвратом якоря громкости,
/// чтобы кнопки работали бесконечно и не сбивали громкость телефона.
struct HardwareVolumeButtonsModifier: ViewModifier {
    let isActive: Bool
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void

    func body(content: Content) -> some View {
        content.background(
            HardwareVolumeBridgeView(
                isActive: isActive,
                onVolumeUp: onVolumeUp,
                onVolumeDown: onVolumeDown
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        )
    }
}

extension View {
    func onHardwareVolumeButtons(
        isActive: Bool,
        onVolumeUp: @escaping () -> Void,
        onVolumeDown: @escaping () -> Void
    ) -> some View {
        modifier(
            HardwareVolumeButtonsModifier(
                isActive: isActive,
                onVolumeUp: onVolumeUp,
                onVolumeDown: onVolumeDown
            )
        )
    }
}

private struct HardwareVolumeBridgeView: UIViewRepresentable {
    let isActive: Bool
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVolumeUp: onVolumeUp, onVolumeDown: onVolumeDown)
    }

    func makeUIView(context: Context) -> HardwareVolumeHostView {
        let host = HardwareVolumeHostView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        context.coordinator.attach(to: host)
        context.coordinator.setActive(isActive)
        return host
    }

    func updateUIView(_ uiView: HardwareVolumeHostView, context: Context) {
        context.coordinator.onVolumeUp = onVolumeUp
        context.coordinator.onVolumeDown = onVolumeDown
        context.coordinator.attach(to: uiView)
        context.coordinator.setActive(isActive)
    }

    static func dismantleUIView(_ uiView: HardwareVolumeHostView, coordinator: Coordinator) {
        coordinator.setActive(false)
    }

    final class Coordinator: NSObject {
        var onVolumeUp: () -> Void
        var onVolumeDown: () -> Void

        private weak var hostView: HardwareVolumeHostView?
        private var isActive = false
        private var volumeObservation: NSKeyValueObservation?
        private var interruptionObserver: NSObjectProtocol?

        private var savedInitialVolume: Float?
        private var anchorVolume: Float = 0.5
        private var expectedVolume: Float = 0.5
        private var pendingResetTarget: Float?
        private var pendingResetExpiry: Date = .distantPast
        private var resetWorkItem: DispatchWorkItem?

        init(onVolumeUp: @escaping () -> Void, onVolumeDown: @escaping () -> Void) {
            self.onVolumeUp = onVolumeUp
            self.onVolumeDown = onVolumeDown
            super.init()
        }

        deinit {
            tearDown(restoreVolume: false)
        }

        func attach(to host: HardwareVolumeHostView) {
            if hostView !== host {
                hostView = host
            }
        }

        func setActive(_ active: Bool) {
            guard active != isActive else { return }
            isActive = active
            if active {
                startMonitoring()
            } else {
                tearDown(restoreVolume: true)
            }
        }

        private func startMonitoring() {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.ambient, options: [.mixWithOthers])
                try session.setActive(true)
            } catch {
                // Если аудиосессия занята, всё равно продолжаем наблюдать outputVolume
            }

            let current = session.outputVolume
            savedInitialVolume = current

            // Если громкость на iPhone на самом краю (0% или 100%), ставим якорь в середину,
            // чтобы обе аппаратные кнопки (+ и -) гарантированно срабатывали.
            let safeAnchor: Float = (current <= 0.14 || current >= 0.86) ? 0.5 : current
            anchorVolume = safeAnchor
            expectedVolume = current

            volumeObservation?.invalidate()
            volumeObservation = session.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, change in
                guard let newVal = change.newValue else { return }
                DispatchQueue.main.async {
                    self?.handleVolumeChange(newVal: newVal, oldVal: change.oldValue)
                }
            }

            if interruptionObserver == nil {
                interruptionObserver = NotificationCenter.default.addObserver(
                    forName: AVAudioSession.interruptionNotification,
                    object: session,
                    queue: .main
                ) { [weak self] note in
                    guard let self, self.isActive else { return }
                    if let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                       typeValue == AVAudioSession.InterruptionType.ended.rawValue {
                        try? AVAudioSession.sharedInstance().setActive(true)
                    }
                }
            }

            if abs(current - safeAnchor) > 0.015 {
                scheduleReset(to: safeAnchor, delay: 0.08)
            }
        }

        private func tearDown(restoreVolume: Bool) {
            resetWorkItem?.cancel()
            resetWorkItem = nil
            volumeObservation?.invalidate()
            volumeObservation = nil
            if let obs = interruptionObserver {
                NotificationCenter.default.removeObserver(obs)
                interruptionObserver = nil
            }
            pendingResetTarget = nil
            pendingResetExpiry = .distantPast

            if restoreVolume, let original = savedInitialVolume {
                let current = AVAudioSession.sharedInstance().outputVolume
                if abs(current - original) > 0.015 {
                    applySliderValue(original)
                }
            }
            savedInitialVolume = nil
        }

        private func handleVolumeChange(newVal: Float, oldVal: Float?) {
            guard isActive else { return }

            // Поглощаем синтетическое событие от нашего возврата ползунка к якорю
            if let target = pendingResetTarget, Date() < pendingResetExpiry {
                if abs(newVal - target) < 0.025 {
                    pendingResetTarget = nil
                    pendingResetExpiry = .distantPast
                    expectedVolume = newVal
                    return
                }
            }

            let reference = expectedVolume
            let delta = newVal - reference

            if delta > 0.001 {
                expectedVolume = newVal
                onVolumeUp()
                let delay: TimeInterval = newVal >= 0.85 ? 0.02 : 0.14
                scheduleReset(to: anchorVolume, delay: delay)
            } else if delta < -0.001 {
                expectedVolume = newVal
                onVolumeDown()
                let delay: TimeInterval = newVal <= 0.15 ? 0.02 : 0.14
                scheduleReset(to: anchorVolume, delay: delay)
            } else if let oldVal, abs(newVal - oldVal) > 0.001 {
                expectedVolume = newVal
                if newVal > oldVal {
                    onVolumeUp()
                } else {
                    onVolumeDown()
                }
                scheduleReset(to: anchorVolume, delay: 0.14)
            }
        }

        private func scheduleReset(to target: Float, delay: TimeInterval) {
            resetWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.isActive else { return }
                let current = AVAudioSession.sharedInstance().outputVolume
                guard abs(current - target) > 0.01 else {
                    self.expectedVolume = current
                    return
                }
                self.pendingResetTarget = target
                self.pendingResetExpiry = Date().addingTimeInterval(0.35)
                if self.applySliderValue(target) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
                        guard let self, self.isActive else { return }
                        if self.pendingResetTarget != nil {
                            self.pendingResetTarget = nil
                            self.pendingResetExpiry = .distantPast
                            self.expectedVolume = AVAudioSession.sharedInstance().outputVolume
                        }
                    }
                } else {
                    self.pendingResetTarget = nil
                    self.pendingResetExpiry = .distantPast
                    self.expectedVolume = current
                }
            }
            resetWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }

        @discardableResult
        private func applySliderValue(_ value: Float) -> Bool {
            guard let slider = hostView?.volumeSlider else { return false }
            let clamped = min(max(value, 0.0), 1.0)
            slider.setValue(clamped, animated: false)
            slider.sendActions(for: .touchUpInside)
            return true
        }
    }
}

private final class HardwareVolumeHostView: UIView {
    private let volumeView: MPVolumeView

    var volumeSlider: UISlider? {
        findSlider(in: volumeView)
    }

    override init(frame: CGRect) {
        self.volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 40, height: 24))
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true

        // Оставляем alpha = 0.01 внутри видимого окна (не 0 и не isHidden),
        // чтобы iOS гарантированно скрывала системный HUD громкости
        volumeView.alpha = 0.01
        volumeView.isUserInteractionEnabled = false
        addSubview(volumeView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func findSlider(in view: UIView) -> UISlider? {
        for sub in view.subviews {
            if let slider = sub as? UISlider {
                return slider
            }
            if let nested = findSlider(in: sub) {
                return nested
            }
        }
        return nil
    }
}
