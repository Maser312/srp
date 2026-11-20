import Foundation
import CoreMotion
import CoreGraphics

/// Контроллер гироскопа для режима «Аэромышь».
/// Читает угловую скорость (`CMDeviceMotion.rotationRate`) с частотой 60 Гц,
/// проецирует поворот вокруг мировой вертикали (вектор гравитации) для горизонтального
/// перемещения курсора (работает при любом угле наклона телефона в руке) и использует
/// наклон вперёд/назад (`rotationRate.x`) для вертикального перемещения.
@MainActor
final class AirMouseController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isAvailable: Bool
    @Published private(set) var tiltX: CGFloat = 0
    @Published private(set) var tiltY: CGFloat = 0
    @Published var sensitivity: Double = 1.0

    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "SaluteRemotePlus.AirMouse"
        q.qualityOfService = .userInteractive
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var onOffset: ((Float, Float) -> Void)?
    private var smoothedX: Double = 0
    private var smoothedY: Double = 0
    private var lastVisualUpdate: CFAbsoluteTime = 0

    init() {
        self.isAvailable = motionManager.isDeviceMotionAvailable || motionManager.isGyroAvailable
    }

    func start(onOffset: @escaping (Float, Float) -> Void) {
        self.onOffset = onOffset
        guard !isRunning else { return }

        if motionManager.isDeviceMotionAvailable {
            isAvailable = true
            isRunning = true
            smoothedX = 0
            smoothedY = 0
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, _ in
                guard let self, let motion else { return }
                let r = motion.rotationRate
                let g = motion.gravity

                // Поворот кисти влево/вправо вокруг оси гравитации:
                // при любом наклоне телефона (плоско, 45°, вертикально) поворот вправо даёт > 0.
                let yawRight = r.x * g.x + r.y * g.y + r.z * g.z
                // Наклон верхнего края вверх даёт r.x > 0 → на экране курсор должен идти вверх (dy < 0).
                let pitchDown = -r.x

                self.processAngularRates(yawRight: yawRight, pitchDown: pitchDown)
            }
        } else if motionManager.isGyroAvailable {
            isAvailable = true
            isRunning = true
            smoothedX = 0
            smoothedY = 0
            motionManager.gyroUpdateInterval = 1.0 / 60.0
            motionManager.startGyroUpdates(to: motionQueue) { [weak self] data, _ in
                guard let self, let data else { return }
                let r = data.rotationRate
                // Фоллбэк без вектора гравитации (типичный хват под ~45°).
                let yawRight = -(r.z * 0.72 + r.y * 0.72)
                let pitchDown = -r.x
                self.processAngularRates(yawRight: yawRight, pitchDown: pitchDown)
            }
        } else {
            isAvailable = false
            isRunning = false
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopGyroUpdates()
        onOffset = nil
        isRunning = false
        smoothedX = 0
        smoothedY = 0
        tiltX = 0
        tiltY = 0
    }

    private nonisolated func processAngularRates(yawRight: Double, pitchDown: Double) {
        // Мёртвая зона подавляет дрожание руки, когда телефон держат неподвижно.
        let deadzone = 0.032
        let filteredX = abs(yawRight) < deadzone ? 0.0 : (yawRight - (yawRight > 0 ? deadzone : -deadzone))
        let filteredY = abs(pitchDown) < deadzone ? 0.0 : (pitchDown - (pitchDown > 0 ? deadzone : -deadzone))

        // Лёгкое экспоненциальное сглаживание для плавности без заметной задержки.
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }

            let alpha = 0.45
            self.smoothedX = self.smoothedX * (1.0 - alpha) + filteredX * alpha
            self.smoothedY = self.smoothedY * (1.0 - alpha) + filteredY * alpha

            let speed = hypot(self.smoothedX, self.smoothedY)
            // Нелинейное ускорение курсора: точное наведение при медленном движении,
            // быстрый переход через весь экран при уверенном взмахе.
            let accel = 1.0 + min(speed * 0.48, 2.2)
            let baseGain = 15.5 * self.sensitivity
            let dx = Float(self.smoothedX * baseGain * accel)
            let dy = Float(self.smoothedY * baseGain * accel)

            if abs(dx) >= 0.35 || abs(dy) >= 0.35 {
                self.onOffset?(dx, dy)
            }

            // Обновляем визуальный индикатор наклона не чаще ~30 Гц, чтобы не перегружать SwiftUI.
            let now = CFAbsoluteTimeGetCurrent()
            if now - self.lastVisualUpdate >= 0.033 {
                self.lastVisualUpdate = now
                let clampedX = max(-1.0, min(1.0, self.smoothedX * 0.85))
                let clampedY = max(-1.0, min(1.0, self.smoothedY * 0.85))
                self.tiltX = CGFloat(clampedX)
                self.tiltY = CGFloat(clampedY)
            }
        }
    }
}
