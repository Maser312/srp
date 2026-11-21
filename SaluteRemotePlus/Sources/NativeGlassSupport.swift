import SwiftUI

// MARK: - Нативный слой iOS 26–27 Liquid Glass, пружинной физики и системных компонентов SwiftUI
// На iOS 26–27 (Xcode 26+ / Swift 6.2+) задействуются настоящие системные API:
// GlassEffectContainer, .glassEffect(.regular.tint(...).interactive(), in: ...),
// .glassEffectID(_:in:), .glassEffectUnion(id:namespace:), .buttonStyle(.glass / .glassProminent),
// нативные прозрачные листы, NavigationStack с плавающим стеклянным toolbar и эластичная физика.

/// Единая эластичная пружинная физика в стиле iOS 26–27 Liquid Glass.
enum NativeLiquidSpring {
    /// Упругий отклик нажатия стеклянных кнопок и ползунков.
    static let press: Animation = .spring(response: 0.28, dampingFraction: 0.62, blendDuration: 0.08)
    /// Плавный жидкий морфинг при смене режимов пульта и экранов.
    static let morph: Animation = .spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.14)
    /// Мягкий возврат при отпускании жеста.
    static let release: Animation = .spring(response: 0.34, dampingFraction: 0.68, blendDuration: 0.10)
}

/// Чистый глубокий тёмный фон в стиле пульта без цветных градиентов,
/// обеспечивающий максимальный контраст и преломление нативного Liquid Glass.
struct NativeDarkBackdrop: View {
    var body: some View {
        Color(red: 0.02, green: 0.02, blue: 0.028)
            .ignoresSafeArea()
    }
}

/// Контейнер для объединения соседних Liquid Glass элементов (на iOS 26–27 — нативный `GlassEffectContainer`).
struct NativeGlassContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

/// Нативный навигационный стек (`NavigationStack` на iOS 16–27 с нативным стеклянным toolbar iOS 26–27).
struct NativeNavigationContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content()
            }
        } else {
            NavigationView {
                content()
            }
            .navigationViewStyle(.stack)
        }
    }
}

/// Нативная строка «Метка — Значение» (`LabeledContent` на iOS 16–27).
struct NativeLabeledRow<Value: View>: View {
    let title: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        if #available(iOS 16.0, *) {
            LabeledContent(title) {
                value()
            }
        } else {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                value()
            }
        }
    }
}

/// Нативный пустой экран (`ContentUnavailableView` на iOS 17–27).
struct NativeEmptyStateView<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(description)
            } actions: {
                actions()
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                actions()
            }
            .padding(20)
        }
    }
}

// MARK: - Модификаторы нативного Liquid Glass и анимаций iOS 26–27

extension View {
    /// Применяет нативный `.glassEffect` строго под контентом на iOS 26–27
    /// с чистым матовым fallback (`.ultraThinMaterial`, без градиентов) на iOS 15–25.
    @ViewBuilder
    func nativeLiquidGlass<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if let tint {
                if interactive {
                    self.glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    self.glassEffect(.regular.tint(tint), in: shape)
                }
            } else {
                if interactive {
                    self.glassEffect(.regular.interactive(), in: shape)
                } else {
                    self.glassEffect(.regular, in: shape)
                }
            }
        } else {
            fallbackGlassSurface(in: shape, tint: tint)
        }
        #else
        fallbackGlassSurface(in: shape, tint: tint)
        #endif
    }

    @ViewBuilder
    private func fallbackGlassSurface<S: InsettableShape>(in shape: S, tint: Color?) -> some View {
        self.background(
            ZStack {
                shape.fill(.ultraThinMaterial)
                if let tint {
                    shape.fill(tint.opacity(0.24))
                } else {
                    shape.fill(Color.white.opacity(0.05))
                }
                shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.9)
            }
        )
    }

    /// Идентификатор морфинга Liquid Glass (`glassEffectID`) на iOS 26–27.
    @ViewBuilder
    func nativeGlassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Объединение соседних стеклянных элементов в единую жидкую группу (`glassEffectUnion`) на iOS 26–27.
    @ViewBuilder
    func nativeGlassUnion<ID: Hashable & Sendable>(id: ID, namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffectUnion(id: id, namespace: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Плавная нативная замена SF Symbols на iOS 17–27.
    @ViewBuilder
    func nativeSymbolReplaceTransition() -> some View {
        if #available(iOS 17.0, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }

    /// Нативный стиль кнопки iOS 26–27 (`.glass` / `.glassProminent`) с fallback на `.bordered` / `.borderedProminent`.
    @ViewBuilder
    func nativeGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if prominent {
                if let tint {
                    self.buttonStyle(.glassProminent).tint(tint)
                } else {
                    self.buttonStyle(.glassProminent)
                }
            } else {
                if let tint {
                    self.buttonStyle(.glass).tint(tint)
                } else {
                    self.buttonStyle(.glass)
                }
            }
        } else {
            fallbackNativeButton(prominent: prominent, tint: tint)
        }
        #else
        fallbackNativeButton(prominent: prominent, tint: tint)
        #endif
    }

    @ViewBuilder
    private func fallbackNativeButton(prominent: Bool, tint: Color?) -> some View {
        if prominent {
            if let tint {
                self.buttonStyle(.borderedProminent).tint(tint)
            } else {
                self.buttonStyle(.borderedProminent)
            }
        } else {
            if let tint {
                self.buttonStyle(.bordered).tint(tint)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    /// Скрывает системный фон Form/List на iOS 16–27, чтобы просвечивал фон и Liquid Glass.
    @ViewBuilder
    func nativeScrollContentHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    /// Нативное оформление модального листа (на iOS 26–27 сохраняет нативную прозрачность Liquid Glass листа).
    @ViewBuilder
    func nativePresentationSheet() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
        } else if #available(iOS 16.4, *) {
            self
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
                .presentationBackground(.ultraThinMaterial)
        } else if #available(iOS 16.0, *) {
            self.presentationDragIndicator(.visible)
        } else {
            self
        }
        #else
        if #available(iOS 16.4, *) {
            self
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
                .presentationBackground(.ultraThinMaterial)
        } else if #available(iOS 16.0, *) {
            self.presentationDragIndicator(.visible)
        } else {
            self
        }
        #endif
    }

    /// Фон модального листа: полностью прозрачный на iOS 26+ (работает нативный Liquid Glass листа)
    /// и чистый тёмный фон на ранних iOS.
    @ViewBuilder
    func nativeGlassSheetContainerBackground() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self
        } else {
            self.background(Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea())
        }
        #else
        self.background(Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea())
        #endif
    }
}
