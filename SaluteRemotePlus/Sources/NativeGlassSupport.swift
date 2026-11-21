import SwiftUI

// MARK: - Нативный слой iOS 26–27 Liquid Glass и системных компонентов SwiftUI
// На iOS 26–27 (Xcode 26+ / Swift 6.2+) задействуются настоящие системные API:
// GlassEffectContainer, .glassEffect(.regular.tint(...).interactive()), .buttonStyle(.glass / .glassProminent),
// NavigationStack с плавающим стеклянным toolbar, нативные Picker(.segmented), Form, ProgressView,
// LabeledContent, ContentUnavailableView и концентрические листы.
// На более ранних версиях iOS (15–25) предусмотрен аккуратный визуальный fallback.

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

// MARK: - Модификаторы нативного Liquid Glass и кнопок iOS 26–27

extension View {
    /// Применяет нативный `.glassEffect` на iOS 26–27 с плавным fallback на `.ultraThinMaterial` для iOS 15–25.
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
            self.background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint {
                        shape.fill(tint.opacity(0.22))
                    }
                    shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                }
            )
        }
        #else
        self.background(
            ZStack {
                shape.fill(.ultraThinMaterial)
                if let tint {
                    shape.fill(tint.opacity(0.22))
                }
                shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
        )
        #endif
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

    /// Скрывает системный фон Form/List на iOS 16–27, чтобы просвечивал фирменный фон и Liquid Glass.
    @ViewBuilder
    func nativeScrollContentHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    /// Нативное оформление модального листа (индикатор перетягивания и скругление iOS 16.4–27).
    @ViewBuilder
    func nativePresentationSheet() -> some View {
        if #available(iOS 16.4, *) {
            self
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        } else if #available(iOS 16.0, *) {
            self.presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}
