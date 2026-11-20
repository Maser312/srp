import SwiftUI

/// Фирменная палитра Сбера (тёмная тема + Liquid Glass + изумрудно-бирюзовые градиенты).
enum SberPalette {
    static let bgTop = Color(red: 0.016, green: 0.047, blue: 0.035)
    static let bgMid = Color(red: 0.024, green: 0.090, blue: 0.067)
    static let bgBottom = Color(red: 0.012, green: 0.039, blue: 0.047)

    static let green = Color(red: 0.129, green: 0.627, blue: 0.220)        // #21A038
    static let brightGreen = Color(red: 0.184, green: 0.839, blue: 0.361)  // #2FD65C
    static let lime = Color(red: 0.569, green: 0.910, blue: 0.255)         // #91E841
    static let teal = Color(red: 0.125, green: 0.757, blue: 0.780)         // #20C1C7
    static let aqua = Color(red: 0.078, green: 0.541, blue: 0.608)         // #148A9B
    static let coral = Color(red: 1.000, green: 0.376, blue: 0.396)        // #FF6065

    static let brandGradient = LinearGradient(
        colors: [lime, brightGreen, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentButtonGradient = LinearGradient(
        colors: [green, brightGreen, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let activeGlowGradient = LinearGradient(
        colors: [brightGreen.opacity(0.85), teal.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassBorderGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.32),
            Color.white.opacity(0.08),
            teal.opacity(0.24),
            brightGreen.opacity(0.18)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassAccentBorder = LinearGradient(
        colors: [
            lime.opacity(0.75),
            brightGreen.opacity(0.55),
            teal.opacity(0.70)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let specularSheen = LinearGradient(
        colors: [
            Color.white.opacity(0.18),
            Color.white.opacity(0.04),
            Color.clear
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// Тёмный атмосферный фон Сбера с мягкими светящимися сферами для преломления Liquid Glass.
struct SberLiquidBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [SberPalette.bgTop, SberPalette.bgMid, SberPalette.bgBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Верхний левый изумрудный ореол
            RadialGradient(
                colors: [SberPalette.green.opacity(0.34), SberPalette.green.opacity(0.0)],
                center: .topLeading,
                startRadius: 10,
                endRadius: 340
            )

            // Верхний правый бирюзовый ореол
            RadialGradient(
                colors: [SberPalette.teal.opacity(0.26), SberPalette.teal.opacity(0.0)],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 310
            )

            // Мягкое нижнее свечение для глубины стеклянных кнопок
            RadialGradient(
                colors: [SberPalette.brightGreen.opacity(0.18), SberPalette.aqua.opacity(0.08), Color.clear],
                center: .bottom,
                startRadius: 20,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}

/// Стеклянная панель в стиле Liquid Glass с матовым размытием, верхним бликом и тонкой градиентной кромкой.
struct LiquidGlassPanel: View {
    var cornerRadius: CGFloat = 22
    var highlighted: Bool = false
    var tint: Color = SberPalette.teal

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial)

            if highlighted {
                shape.fill(SberPalette.accentButtonGradient).opacity(0.76)
            } else {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.09),
                            tint.opacity(0.05),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            // Верхний стеклянный блик
            shape.fill(SberPalette.specularSheen)
                .opacity(highlighted ? 0.55 : 0.75)

            // Тонкая переливающаяся рамка Liquid Glass
            shape.strokeBorder(
                highlighted ? SberPalette.glassAccentBorder : SberPalette.glassBorderGradient,
                lineWidth: highlighted ? 1.25 : 1.0
            )
        }
        .shadow(color: highlighted ? SberPalette.brightGreen.opacity(0.26) : Color.black.opacity(0.30), radius: highlighted ? 12 : 8, x: 0, y: 4)
    }
}

/// Круглая стеклянная кнопка в стиле Liquid Glass.
struct LiquidGlassCircle: View {
    var highlighted: Bool = false
    var accent: Bool = false

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)

            if accent || highlighted {
                Circle().fill(SberPalette.accentButtonGradient).opacity(accent ? 0.88 : 0.65)
            } else {
                Circle().fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.11),
                            SberPalette.teal.opacity(0.05),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            Circle()
                .fill(SberPalette.specularSheen)
                .opacity(accent ? 0.45 : 0.70)

            Circle()
                .strokeBorder(
                    (accent || highlighted) ? SberPalette.glassAccentBorder : SberPalette.glassBorderGradient,
                    lineWidth: (accent || highlighted) ? 1.3 : 1.0
                )
        }
        .shadow(
            color: (accent || highlighted) ? SberPalette.brightGreen.opacity(0.32) : Color.black.opacity(0.28),
            radius: (accent || highlighted) ? 12 : 6,
            x: 0,
            y: 4
        )
    }
}

/// Стеклянная кнопка-капсула с фирменным градиентом Сбера (для главных CTA в листах).
struct SberPrimaryButtonStyle: ButtonStyle {
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(SberPalette.accentButtonGradient)
                        .opacity(disabled ? 0.35 : (configuration.isPressed ? 0.82 : 1.0))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(SberPalette.specularSheen)
                        .opacity(0.42)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(SberPalette.glassAccentBorder, lineWidth: 1.1)
                }
            )
            .shadow(color: disabled ? .clear : SberPalette.brightGreen.opacity(0.28), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Вторичная стеклянная кнопка для листов и диалогов.
struct SberGlassButtonStyle: ButtonStyle {
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white.opacity(disabled ? 0.38 : 0.92))
            .background(LiquidGlassPanel(cornerRadius: 14, highlighted: false))
            .opacity(configuration.isPressed ? 0.78 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
