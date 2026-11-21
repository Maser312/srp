import SwiftUI

/// Палитра акцентов без градиентов — для чистого тёмного интерфейса с нативным iOS 26–27 Liquid Glass.
enum SberPalette {
    static let bgTop = Color(red: 0.020, green: 0.020, blue: 0.028)
    static let bgMid = Color(red: 0.020, green: 0.020, blue: 0.028)
    static let bgBottom = Color(red: 0.020, green: 0.020, blue: 0.028)

    static let green = Color(red: 0.129, green: 0.627, blue: 0.220)        // #21A038
    static let brightGreen = Color(red: 0.184, green: 0.839, blue: 0.361)  // #2FD65C
    static let lime = Color(red: 0.569, green: 0.910, blue: 0.255)         // #91E841
    static let teal = Color(red: 0.125, green: 0.757, blue: 0.780)         // #20C1C7
    static let aqua = Color(red: 0.078, green: 0.541, blue: 0.608)         // #148A9B
    static let coral = Color(red: 1.000, green: 0.376, blue: 0.396)        // #FF6065
}

/// Чистый глубокий тёмный фон без градиентов в стиле пульта.
struct SberLiquidBackdrop: View {
    var body: some View {
        NativeDarkBackdrop()
    }
}

/// Матовая полупрозрачная подложка без градиентов (fallback для iOS 15–25).
struct LiquidGlassPanel: View {
    var cornerRadius: CGFloat = 22
    var highlighted: Bool = false
    var tint: Color = SberPalette.brightGreen
    var interactive: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(highlighted ? tint.opacity(0.32) : Color.white.opacity(0.04))
            shape.strokeBorder(
                highlighted ? tint.opacity(0.65) : Color.white.opacity(0.14),
                lineWidth: highlighted ? 1.1 : 0.85
            )
        }
    }
}

/// Круглая полупрозрачная подложка без градиентов (fallback для iOS 15–25).
struct LiquidGlassCircle: View {
    var highlighted: Bool = false
    var accent: Bool = false

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill((accent || highlighted) ? SberPalette.brightGreen.opacity(accent ? 0.38 : 0.28) : Color.white.opacity(0.05))
            Circle().strokeBorder(
                (accent || highlighted) ? SberPalette.brightGreen.opacity(0.65) : Color.white.opacity(0.14),
                lineWidth: (accent || highlighted) ? 1.15 : 0.85
            )
        }
    }
}

// MARK: - Прямые модификаторы Liquid Glass iOS 26–27 (стекло строго под контентом)

extension View {
    @ViewBuilder
    func sberGlassPanel(
        cornerRadius: CGFloat = 22,
        highlighted: Bool = false,
        tint: Color = SberPalette.brightGreen,
        interactive: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self.nativeLiquidGlass(
            in: shape,
            tint: highlighted ? tint.opacity(0.55) : nil,
            interactive: interactive
        )
    }

    @ViewBuilder
    func sberGlassCircle(
        highlighted: Bool = false,
        accent: Bool = false,
        interactive: Bool = true
    ) -> some View {
        let activeTint: Color? = (accent || highlighted)
            ? SberPalette.brightGreen.opacity(accent ? 0.52 : 0.36)
            : nil
        self.nativeLiquidGlass(
            in: Circle(),
            tint: activeTint,
            interactive: interactive
        )
    }
}

/// Стеклянная кнопка-капсула с нативным Liquid Glass и упругой физикой.
struct SberPrimaryButtonStyle: ButtonStyle {
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(disabled ? .white.opacity(0.42) : .white)
            .nativeLiquidGlass(
                in: Capsule(),
                tint: disabled ? nil : SberPalette.green.opacity(0.75),
                interactive: !disabled
            )
            .scaleEffect(configuration.isPressed && !disabled ? 0.96 : 1.0)
            .animation(NativeLiquidSpring.press, value: configuration.isPressed)
            .opacity(disabled ? 0.55 : 1.0)
    }
}

/// Вторичная стеклянная кнопка-капсула с нативным Liquid Glass.
struct SberGlassButtonStyle: ButtonStyle {
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white.opacity(disabled ? 0.38 : 0.94))
            .nativeLiquidGlass(in: Capsule(), interactive: !disabled)
            .scaleEffect(configuration.isPressed && !disabled ? 0.96 : 1.0)
            .animation(NativeLiquidSpring.press, value: configuration.isPressed)
    }
}
