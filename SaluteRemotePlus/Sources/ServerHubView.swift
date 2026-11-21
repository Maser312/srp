import SwiftUI
import UIKit
import WebKit

// MARK: - Тема Серверного Хаба (Datacenter Cobalt & Cyan Liquid Glass)

enum ServerPalette {
    static let bgTop = Color(red: 0.025, green: 0.042, blue: 0.082)
    static let bgMid = Color(red: 0.040, green: 0.068, blue: 0.125)
    static let bgBottom = Color(red: 0.016, green: 0.026, blue: 0.052)

    static let dellBlue = Color(red: 0.00, green: 0.54, blue: 0.88)
    static let iruCyan = Color(red: 0.08, green: 0.78, blue: 0.96)
    static let electricIndigo = Color(red: 0.24, green: 0.44, blue: 0.98)
    static let onlineGreen = Color(red: 0.14, green: 0.88, blue: 0.60)
    static let warnAmber = Color(red: 1.00, green: 0.72, blue: 0.22)
    static let dangerRed = Color(red: 1.00, green: 0.28, blue: 0.34)

    static let accentButtonGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.74, blue: 0.96),
            Color(red: 0.00, green: 0.48, blue: 0.86),
            Color(red: 0.10, green: 0.30, blue: 0.74)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassTopSheen = LinearGradient(
        colors: [
            Color.white.opacity(0.22),
            Color.white.opacity(0.06),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassBorderGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.32),
            iruCyan.opacity(0.24),
            Color.white.opacity(0.06),
            dellBlue.opacity(0.20)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassAccentBorder = LinearGradient(
        colors: [
            Color.white.opacity(0.55),
            iruCyan.opacity(0.65),
            dellBlue.opacity(0.38)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct ServerLiquidBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ServerPalette.bgTop, ServerPalette.bgMid, ServerPalette.bgBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [ServerPalette.dellBlue.opacity(0.30), Color.clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 340
            )
            .offset(x: -70, y: -110)

            RadialGradient(
                colors: [ServerPalette.iruCyan.opacity(0.22), Color.clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 340
            )
            .offset(x: 90, y: 120)

            RadialGradient(
                colors: [ServerPalette.electricIndigo.opacity(0.14), Color.clear],
                center: .center,
                startRadius: 40,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

struct ServerGlassPanel: View {
    var cornerRadius: CGFloat = 22
    var accentGlow: Color? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.04, green: 0.07, blue: 0.13).opacity(0.70))
            if let glow = accentGlow {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [glow.opacity(0.18), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ServerPalette.glassTopSheen)
                .opacity(0.60)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(ServerPalette.glassBorderGradient, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.45), radius: 14, y: 8)
    }
}

struct ServerGlassCircle: View {
    var accent: Bool = false

    var body: some View {
        ZStack {
            if accent {
                Circle()
                    .fill(ServerPalette.accentButtonGradient)
                Circle()
                    .fill(ServerPalette.glassTopSheen)
                    .opacity(0.65)
                Circle()
                    .strokeBorder(ServerPalette.glassAccentBorder, lineWidth: 1.2)
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(Color.white.opacity(0.08))
                Circle()
                    .fill(ServerPalette.glassTopSheen)
                    .opacity(0.45)
                Circle()
                    .strokeBorder(ServerPalette.glassBorderGradient, lineWidth: 1)
            }
        }
    }
}

// MARK: - Главный экран управления серверами Dell / iRU

private struct PendingPowerConfirm: Identifiable {
    let id = UUID()
    let server: ServerProfile
    let action: ServerPowerAction
}

struct ServerHubView: View {
    @ObservedObject var manager: ServerManager
    let onExit: () -> Void

    @State private var editingProfile: ServerProfile?
    @State private var isCreatingNew = false
    @State private var newServerDefaultVendor: ServerVendor = .dellIDRAC
    @State private var discoveryPrefill: ServerEditorPrefill?
    @State private var isShowingDiscovery = false
    @State private var activeControlServer: ServerProfile?
    @State private var activeConsoleServer: ServerProfile?
    @State private var powerMenuServer: ServerProfile?
    @State private var pendingConfirmAction: PendingPowerConfirm?
    @State private var pendingDeleteServer: ServerProfile?

    var body: some View {
        ZStack {
            ServerLiquidBackdrop()

            if manager.requireBiometricLock && !manager.isUnlocked {
                biometricLockScreen
            } else {
                mainContent
            }

            if let notice = manager.actionNotice {
                VStack {
                    Spacer()
                    Text(notice)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .nativeLiquidGlass(in: Capsule(), tint: ServerPalette.dellBlue.opacity(0.32))
                        .shadow(color: Color.black.opacity(0.40), radius: 10, y: 4)
                        .padding(.bottom, 22)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            manager.startMonitoring()
            if manager.isUnlocked && !manager.servers.isEmpty {
                manager.refreshAllServers()
            } else if manager.requireBiometricLock && !manager.isUnlocked {
                manager.unlockWithBiometrics()
            }
        }
        .sheet(isPresented: $isCreatingNew) {
            ServerEditorSheet(
                manager: manager,
                existing: nil,
                defaultVendor: newServerDefaultVendor,
                prefill: nil
            )
        }
        .sheet(item: $discoveryPrefill) { prefill in
            ServerEditorSheet(
                manager: manager,
                existing: nil,
                defaultVendor: prefill.vendor,
                prefill: prefill
            )
        }
        .sheet(item: $editingProfile) { profile in
            ServerEditorSheet(
                manager: manager,
                existing: profile,
                defaultVendor: profile.vendor,
                prefill: nil
            )
        }
        .sheet(isPresented: $isShowingDiscovery) {
            ServerDiscoverySheet(manager: manager) { prefill in
                discoveryPrefill = prefill
            }
        }
        .fullScreenCover(item: $activeControlServer) { server in
            ServerControlView(
                manager: manager,
                server: server,
                onOpenWebConsole: {
                    activeConsoleServer = server
                }
            )
        }
        .fullScreenCover(item: $activeConsoleServer) { server in
            ServerWebConsoleView(
                server: server,
                password: manager.password(for: server),
                onCopyNotice: { text in
                    manager.showNotice(text)
                }
            )
        }
        .confirmationDialog(
            powerMenuServer.map { "Питание · \($0.name)" } ?? "Управление питанием",
            isPresented: Binding(
                get: { powerMenuServer != nil },
                set: { if !$0 { powerMenuServer = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let server = powerMenuServer {
                let caps = manager.capabilities(for: server)
                let actions = (caps?.allowedResetTypes.isEmpty == false)
                    ? (caps?.allowedResetTypes ?? [])
                    : [ServerPowerAction.on, .gracefulShutdown, .gracefulRestart, .forceRestart, .forceOff]

                if caps?.redfishSupported != false {
                    ForEach(actions) { action in
                        if action.isDestructive {
                            Button(action.title, role: .destructive) {
                                pendingConfirmAction = PendingPowerConfirm(server: server, action: action)
                            }
                        } else {
                            Button(action.title) {
                                if action.requiresConfirmation {
                                    pendingConfirmAction = PendingPowerConfirm(server: server, action: action)
                                } else {
                                    Task { await manager.sendPowerAction(action, to: server) }
                                }
                            }
                        }
                    }
                    if caps?.supportsIndicatorLED != false {
                        Button("Переключить индикатор локатора LED") {
                            Task { await manager.toggleLocatorLED(for: server) }
                        }
                    }
                    if caps?.supportsManagerReset == true {
                        Button("Перезагрузить контроллер \(caps?.bmcFamily.shortBadge ?? "BMC")") {
                            Task { await manager.resetBMCManager(for: server) }
                        }
                    }
                }
                if server.hasValidMAC {
                    Button("Отправить Wake-on-LAN (MAC)") {
                        manager.sendWakeOnLAN(to: server)
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
        .alert(
            "Подтвердите действие",
            isPresented: Binding(
                get: { pendingConfirmAction != nil },
                set: { if !$0 { pendingConfirmAction = nil } }
            ),
            presenting: pendingConfirmAction
        ) { item in
            if item.action.isDestructive {
                Button("Выполнить", role: .destructive) {
                    let targetServer = item.server
                    let targetAction = item.action
                    Task { await manager.sendPowerAction(targetAction, to: targetServer) }
                }
            } else {
                Button("Выполнить") {
                    let targetServer = item.server
                    let targetAction = item.action
                    Task { await manager.sendPowerAction(targetAction, to: targetServer) }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { item in
            Text("Отправить «\(item.action.title)» на сервер «\(item.server.name)» (\(item.server.displayAddress))?")
        }
        .alert(
            "Удалить сервер?",
            isPresented: Binding(
                get: { pendingDeleteServer != nil },
                set: { if !$0 { pendingDeleteServer = nil } }
            ),
            presenting: pendingDeleteServer
        ) { server in
            Button("Удалить", role: .destructive) {
                manager.deleteServer(server)
            }
            Button("Отмена", role: .cancel) {}
        } message: { server in
            Text("Сервер «\(server.name)» и его сохранённый пароль в Keychain будут удалены.")
        }
    }

    // MARK: - Экран блокировки Face ID / Touch ID

    private var biometricLockScreen: some View {
        VStack(spacing: 22) {
            HStack {
                Button(action: onExit) {
                    ZStack {
                        ServerGlassCircle()
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(RemotePressStyle())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer()

            ZStack {
                ServerGlassCircle(accent: true)
                    .frame(width: 84, height: 84)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: ServerPalette.dellBlue.opacity(0.45), radius: 16, y: 6)

            VStack(spacing: 8) {
                Text("Доступ к серверам защищён")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("Разблокируйте с помощью Face ID или код-пароля, чтобы открыть панели Dell iDRAC и iRU BMC.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                Haptics.medium()
                manager.unlockWithBiometrics()
            } label: {
                Label("Разблокировать", systemImage: "lock.open.fill")
                    .font(.headline.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .nativeGlassButton(prominent: true, tint: ServerPalette.dellBlue)
            .controlSize(.large)

            Spacer()
        }
    }

    // MARK: - Основной интерфейс

    private var mainContent: some View {
        NativeNavigationContainer {
            ZStack {
                ServerLiquidBackdrop()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        networkRouteBanner

                        if manager.servers.isEmpty {
                            emptyOnboardingCard
                        } else {
                            ForEach(manager.servers) { server in
                                ServerDashboardCard(
                                    server: server,
                                    telemetry: manager.telemetry[server.id] ?? ServerTelemetry(),
                                    capabilities: manager.capabilities(for: server),
                                    hasPassword: !manager.password(for: server).isEmpty,
                                    onOpenControl: {
                                        Haptics.medium()
                                        activeControlServer = server
                                    },
                                    onOpenConsole: {
                                        Haptics.medium()
                                        activeConsoleServer = server
                                    },
                                    onPowerMenu: {
                                        Haptics.light()
                                        powerMenuServer = server
                                    },
                                    onRefresh: {
                                        Haptics.light()
                                        Task { await manager.checkServer(server, deepProbe: true) }
                                    },
                                    onEdit: {
                                        Haptics.light()
                                        editingProfile = server
                                    },
                                    onDelete: {
                                        Haptics.light()
                                        pendingDeleteServer = server
                                    }
                                )
                            }
                        }

                        Spacer(minLength: 26)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .refreshable {
                    for server in manager.servers {
                        await manager.checkServer(server)
                    }
                }
            }
            .navigationTitle("Серверы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Haptics.light()
                        onExit()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Назад")
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.medium()
                        isShowingDiscovery = true
                    } label: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                    .accessibilityLabel("Автопоиск iDRAC / BMC")

                    Button {
                        Haptics.light()
                        manager.requireBiometricLock.toggle()
                        manager.showNotice(
                            manager.requireBiometricLock
                                ? "Защита входа по Face ID включена"
                                : "Защита входа по Face ID отключена"
                        )
                    } label: {
                        Image(systemName: manager.requireBiometricLock ? "lock.fill" : "lock.open.fill")
                    }
                    .tint(manager.requireBiometricLock ? ServerPalette.iruCyan : nil)
                    .accessibilityLabel("Защита Face ID")

                    Button {
                        Haptics.light()
                        manager.refreshAllServers()
                    } label: {
                        if manager.isRefreshingAll {
                            ProgressView()
                                .tint(ServerPalette.iruCyan)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Обновить статус")

                    Button {
                        Haptics.medium()
                        newServerDefaultVendor = .dellIDRAC
                        isCreatingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(ServerPalette.iruCyan)
                    .accessibilityLabel("Добавить сервер")
                }
            }
        }
    }

    private var networkRouteBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(manager.networkRoute.indicatorColor.opacity(0.20))
                    .frame(width: 38, height: 38)
                Image(systemName: manager.networkRoute.isReadyForLAN ? "shield.lefthalf.filled" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(manager.networkRoute.indicatorColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(manager.networkRoute.title)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                    Text(manager.networkRoute.shortBadge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ServerPalette.bgTop)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(manager.networkRoute.indicatorColor))
                }
                Text(
                    manager.networkRoute.isReadyForLAN
                        ? "Трафик к панелям идёт напрямую через локальную сеть или активный Kerio VPN."
                        : "Вы в сотовой сети без VPN. Включите Kerio VPN в Настройках iOS, затем обновите список."
                )
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(ServerGlassPanel(cornerRadius: 20, accentGlow: manager.networkRoute.indicatorColor))
    }

    private var emptyOnboardingCard: some View {
        NativeEmptyStateView(
            title: "Добавьте серверы Dell и iRU",
            systemImage: "server.rack",
            description: "Адреса, логины и пароли хранятся локально в защищённом iOS Keychain. Поддерживается авто-вход, самоподписанный SSL, десктопный режим и Redfish-телеметрия."
        ) {
            NativeGlassContainer(spacing: 10) {
                VStack(spacing: 10) {
                    Button {
                        Haptics.medium()
                        isShowingDiscovery = true
                    } label: {
                        Label("Автопоиск iDRAC / BMC в сети", systemImage: "dot.radiowaves.left.and.right")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .nativeGlassButton(prominent: true, tint: ServerPalette.dellBlue)
                    .controlSize(.large)

                    Button {
                        Haptics.medium()
                        newServerDefaultVendor = .dellIDRAC
                        isCreatingNew = true
                    } label: {
                        Label("Добавить сервер Dell (iDRAC)", systemImage: "server.rack")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                    }
                    .nativeGlassButton(prominent: false, tint: ServerVendor.dellIDRAC.accentColor)
                    .controlSize(.large)

                    Button {
                        Haptics.medium()
                        newServerDefaultVendor = .iruBMC
                        isCreatingNew = true
                    } label: {
                        Label("Добавить сервер iRU (BMC / IPMI)", systemImage: "cpu")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                    }
                    .nativeGlassButton(prominent: false, tint: ServerVendor.iruBMC.accentColor)
                    .controlSize(.large)

                    Button {
                        Haptics.light()
                        newServerDefaultVendor = .genericWeb
                        isCreatingNew = true
                    } label: {
                        Label("Другая веб-панель (Proxmox, ESXi)", systemImage: "globe")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .nativeGlassButton(prominent: false)
                }
                .padding(.top, 6)
            }
        }
        .padding(16)
        .background(ServerGlassPanel(cornerRadius: 24, accentGlow: ServerPalette.dellBlue))
    }
}

// MARK: - Карточка сервера на дашборде

private struct ServerDashboardCard: View {
    let server: ServerProfile
    let telemetry: ServerTelemetry
    let capabilities: ServerCapabilities?
    let hasPassword: Bool
    let onOpenControl: () -> Void
    let onOpenConsole: () -> Void
    let onPowerMenu: () -> Void
    let onRefresh: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var statusDotColor: Color {
        switch telemetry.reachability {
        case .online: return ServerPalette.onlineGreen
        case .checking: return ServerPalette.warnAmber
        case .offline: return ServerPalette.dangerRed
        case .unknown: return .white.opacity(0.35)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Верхняя строка: бейдж вендора, имя, статус
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [server.vendor.accentColor, server.vendor.secondaryAccentColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(ServerPalette.glassAccentBorder, lineWidth: 1)
                        )
                    Image(systemName: server.vendor.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(server.name)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(capabilities?.shortVersionLabel ?? server.vendor.shortBadge)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(server.vendor.accentColor.opacity(0.35))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(server.vendor.accentColor.opacity(0.75), lineWidth: 0.8)
                                    )
                            )
                    }

                    Text(server.displayAddress)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 7, height: 7)
                            .shadow(color: statusDotColor.opacity(0.8), radius: 3)
                        Text(telemetry.reachability.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(statusDotColor)

                        if !server.username.isEmpty {
                            Text("· \(server.username)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.50))
                                .lineLimit(1)
                        }
                        if hasPassword {
                            Image(systemName: "key.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(ServerPalette.iruCyan.opacity(0.85))
                        }
                    }
                }

                Spacer(minLength: 4)

                Menu {
                    Button {
                        onRefresh()
                    } label: {
                        Label("Проверить статус", systemImage: "arrow.clockwise")
                    }
                    Button {
                        onEdit()
                    } label: {
                        Label("Редактировать", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Удалить сервер", systemImage: "trash")
                    }
                } label: {
                    ZStack {
                        ServerGlassCircle()
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(width: 34, height: 34)
                }
            }

            // Состояние самого сервера (Работает / Выключен / Запускается + Здоровье + Системный статус)
            if telemetry.powerStatusTitle != nil || telemetry.healthTitle != nil || telemetry.systemStateTitle != nil {
                serverStateStrip
            }

            // Живая Redfish-телеметрия (если сервер ответил)
            if telemetry.redfishAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    if let model = telemetry.model, !model.isEmpty {
                        Text([telemetry.manufacturer, model].compactMap { $0 }.joined(separator: " "))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(1)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if let temp = telemetry.maxTempC {
                                telemetryChip(
                                    symbol: "thermometer",
                                    text: "\(temp)°C",
                                    color: temp >= 75 ? ServerPalette.dangerRed : (temp >= 60 ? ServerPalette.warnAmber : ServerPalette.iruCyan)
                                )
                            }
                            if let rpm = telemetry.fanRPM {
                                telemetryChip(
                                    symbol: "wind",
                                    text: "\(rpm) RPM",
                                    color: .white.opacity(0.80)
                                )
                            }
                            if let ram = telemetry.memoryGiB {
                                telemetryChip(
                                    symbol: "cpu",
                                    text: "\(ram) ГБ RAM",
                                    color: .white.opacity(0.80)
                                )
                            }
                            if let watts = telemetry.powerConsumedWatts {
                                telemetryChip(
                                    symbol: "bolt.fill",
                                    text: "\(watts) Вт",
                                    color: ServerPalette.onlineGreen
                                )
                            }
                            if let led = telemetry.indicatorLED, led.lowercased() == "lit" || led.lowercased() == "blinking" {
                                telemetryChip(
                                    symbol: "lightbulb.fill",
                                    text: "LED ВКЛ",
                                    color: ServerPalette.iruCyan
                                )
                            }
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }

            if !server.notes.isEmpty {
                Text(server.notes)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }

            // Основные действия: Нативный Пульт BMC + Веб-панель + быстрая кнопка Питания (Liquid Glass iOS 26–27)
            NativeGlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: onOpenControl) {
                        Label("Пульт BMC", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .nativeGlassButton(prominent: true, tint: server.vendor.accentColor)
                    .controlSize(.regular)

                    Button(action: onOpenConsole) {
                        Label("Веб-панель", systemImage: "desktopcomputer")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .nativeGlassButton(prominent: false)
                    .controlSize(.regular)

                    Button(action: onPowerMenu) {
                        Image(systemName: "power")
                            .font(.subheadline.weight(.bold))
                            .padding(.vertical, 4)
                    }
                    .nativeGlassButton(prominent: false)
                    .controlSize(.regular)
                    .accessibilityLabel("Питание сервера")
                }
            }
        }
        .padding(16)
        .background(ServerGlassPanel(cornerRadius: 22, accentGlow: server.vendor.accentColor))
    }

    private var serverStateStrip: some View {
        HStack(spacing: 8) {
            if let powerTitle = telemetry.powerStatusTitle {
                HStack(spacing: 6) {
                    Circle()
                        .fill(telemetry.powerStatusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: telemetry.powerStatusColor.opacity(0.85), radius: 4)
                    Image(systemName: telemetry.powerStatusSymbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(telemetry.powerStatusColor)
                    Text(powerTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(telemetry.powerStatusColor.opacity(0.20))
                        .overlay(Capsule().strokeBorder(telemetry.powerStatusColor.opacity(0.55), lineWidth: 1))
                )
            }

            if let healthTitle = telemetry.healthTitle {
                let isOK = (telemetry.health?.lowercased() == "ok")
                HStack(spacing: 4) {
                    Image(systemName: isOK ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(healthTitle)
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(telemetry.healthColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(telemetry.healthColor.opacity(0.14))
                        .overlay(Capsule().strokeBorder(telemetry.healthColor.opacity(0.40), lineWidth: 0.8))
                )
            }

            if let sysTitle = telemetry.systemStateTitle,
               telemetry.systemState?.lowercased() != "enabled" {
                Text(sysTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8))
                    )
            }

            Spacer(minLength: 0)
        }
    }

    private func telemetryChip(symbol: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
                .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.8))
        )
    }
}

// MARK: - Редактор сервера (Dell iDRAC / iRU BMC / Другой)

struct ServerEditorSheet: View {
    @ObservedObject var manager: ServerManager
    let existing: ServerProfile?
    let defaultVendor: ServerVendor
    var prefill: ServerEditorPrefill? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var vendor: ServerVendor = .dellIDRAC
    @State private var address: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showPassword = false
    @State private var macAddress: String = ""
    @State private var notes: String = ""
    @State private var allowUntrustedSSL: Bool = true
    @State private var desktopMode: Bool = true
    @State private var autoFillLogin: Bool = true
    @State private var redfishEnabled: Bool = true
    @State private var validationError: String?

    var body: some View {
        NativeNavigationContainer {
            ZStack {
                ServerLiquidBackdrop()
                editorForm
            }
            .navigationTitle(existing == nil ? "Новый сервер" : "Настройки сервера")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") { save() }
                        .font(.body.weight(.bold))
                        .tint(ServerPalette.iruCyan)
                }
            }
        }
        .nativePresentationSheet()
        .preferredColorScheme(.dark)
        .onAppear(perform: loadExistingProfile)
        .onChange(of: vendor) { newVendor in
            let knownDefaults = ServerVendor.allCases.map(\.defaultUsername)
            if username.isEmpty || knownDefaults.contains(username) {
                username = newVendor.defaultUsername
            }
        }
    }

    private var editorForm: some View {
        Form {
            vendorSection
            connectionSection
            compatibilitySection

            if let err = validationError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ServerPalette.dangerRed)
                }
                .listRowBackground(Color.white.opacity(0.06))
            }

            Section {
                Button(action: save) {
                    Text(existing == nil ? "Добавить сервер" : "Сохранить изменения")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .nativeGlassButton(prominent: true, tint: ServerPalette.dellBlue)
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }
        }
        .nativeScrollContentHidden()
    }

    private var vendorSection: some View {
        Section("Тип панели управления") {
            Picker("Тип панели", selection: $vendor) {
                ForEach(ServerVendor.allCases) { item in
                    Text(item.shortBadge).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(Color.white.opacity(0.07))
    }

    private var connectionSection: some View {
        Section("Подключение и учётные данные") {
            TextField(
                vendor == .dellIDRAC ? "Dell PowerEdge R740" : (vendor == .iruBMC ? "iRU Rock S2108" : "Название сервера"),
                text: $name
            )
            .textInputAutocapitalization(.sentences)

            TextField(vendor.addressPlaceholder, text: $address)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            TextField("Логин (\(vendor.defaultUsername))", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            HStack(spacing: 8) {
                Group {
                    if showPassword {
                        TextField("Пароль (сохраняется в Keychain)", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    } else {
                        SecureField("Пароль (сохраняется в Keychain)", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                }

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField("MAC-адрес для Wake-on-LAN (необязательно)", text: $macAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            TextField("Заметка (стойка, роль, порт)", text: $notes)
        }
        .listRowBackground(Color.white.opacity(0.07))
    }

    private var compatibilitySection: some View {
        Section("Параметры веб-панели и BMC") {
            toggleRow(
                title: "Доверять самоподписанному SSL",
                subtitle: "Нужно для локальных сертификатов Dell iDRAC и iRU BMC",
                isOn: $allowUntrustedSSL
            )
            toggleRow(
                title: "Десктопный режим (Desktop UA)",
                subtitle: "Предотвращает поломку вёрстки iDRAC / MegaRAC на iPhone",
                isOn: $desktopMode
            )
            toggleRow(
                title: "Автозаполнение логина и пароля",
                subtitle: "Автоматически подставляет данные из Keychain на странице входа",
                isOn: $autoFillLogin
            )
            toggleRow(
                title: "Опрос Redfish API (питание, °C, статус)",
                subtitle: "Показывает состояние железа прямо на карточке сервера",
                isOn: $redfishEnabled
            )
        }
        .listRowBackground(Color.white.opacity(0.07))
    }

    private func loadExistingProfile() {
        if let profile = existing {
            name = profile.name
            vendor = profile.vendor
            address = profile.address
            username = profile.username
            password = manager.password(for: profile)
            macAddress = profile.macAddress
            notes = profile.notes
            allowUntrustedSSL = profile.allowUntrustedSSL
            desktopMode = profile.desktopMode
            autoFillLogin = profile.autoFillLogin
            redfishEnabled = profile.redfishEnabled
        } else if let pre = prefill {
            name = pre.name
            vendor = pre.vendor
            address = pre.address
            username = pre.username
            notes = pre.notes
            redfishEnabled = pre.redfishEnabled
        } else {
            vendor = defaultVendor
            username = defaultVendor.defaultUsername
            redfishEnabled = (defaultVendor != .genericWeb)
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(ServerPalette.iruCyan)
    }

    private func save() {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            validationError = "Укажите IP-адрес или URL веб-панели сервера"
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "\(vendor.title) (\(trimmedAddress))" : trimmedName

        var profile = existing ?? ServerProfile(
            name: finalName,
            vendor: vendor,
            address: trimmedAddress,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        profile.name = finalName
        profile.vendor = vendor
        profile.address = trimmedAddress
        profile.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.macAddress = macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.allowUntrustedSSL = allowUntrustedSSL
        profile.desktopMode = desktopMode
        profile.autoFillLogin = autoFillLogin
        profile.redfishEnabled = redfishEnabled

        guard profile.normalizedURL != nil else {
            validationError = "Некорректный формат адреса (пример: 192.168.1.10 или https://192.168.1.10)"
            return
        }

        Haptics.medium()
        manager.saveServer(profile, password: password)
        dismiss()
    }
}

// MARK: - Встроенная полноэкранная Веб-консоль Dell iDRAC / iRU BMC (WKWebView)

struct ServerWebConsoleView: View {
    let server: ServerProfile
    let password: String
    let onCopyNotice: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = ServerWebConsoleController()
    @State private var useDesktopUA: Bool

    init(server: ServerProfile, password: String, onCopyNotice: @escaping (String) -> Void) {
        self.server = server
        self.password = password
        self.onCopyNotice = onCopyNotice
        self._useDesktopUA = State(initialValue: server.desktopMode)
    }

    var body: some View {
        ZStack {
            ServerPalette.bgTop.ignoresSafeArea()

            VStack(spacing: 0) {
                // Компактная верхняя панель консоли
                HStack(spacing: 8) {
                    Button {
                        Haptics.light()
                        dismiss()
                    } label: {
                        ZStack {
                            ServerGlassCircle()
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 34, height: 34)
                    }
                    .buttonStyle(RemotePressStyle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(server.name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(controller.currentHostDisplay.isEmpty ? server.displayAddress : controller.currentHostDisplay)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    // Назад / Вперёд
                    Button {
                        controller.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(controller.canGoBack ? Color.white : Color.white.opacity(0.28))
                            .frame(width: 30, height: 34)
                    }
                    .disabled(!controller.canGoBack)

                    Button {
                        controller.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(controller.canGoForward ? Color.white : Color.white.opacity(0.28))
                            .frame(width: 30, height: 34)
                    }
                    .disabled(!controller.canGoForward)

                    // Автозаполнение логина/пароля в 1 тап
                    if !server.username.isEmpty || !password.isEmpty {
                        Button {
                            Haptics.medium()
                            controller.injectLoginAutofill(username: server.username, password: password, submit: true)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Вход")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(server.vendor.accentColor.opacity(0.85))
                                    .overlay(Capsule().strokeBorder(ServerPalette.glassAccentBorder, lineWidth: 0.8))
                            )
                        }
                        .buttonStyle(RemotePressStyle())
                    }

                    // Меню консоли: копирование логина/пароля, Desktop/Mobile UA, обновить
                    Menu {
                        if !server.username.isEmpty {
                            Button {
                                UIPasteboard.general.string = server.username
                                onCopyNotice("Логин скопирован")
                            } label: {
                                Label("Скопировать логин", systemImage: "doc.on.doc")
                            }
                        }
                        if !password.isEmpty {
                            Button {
                                UIPasteboard.general.string = password
                                onCopyNotice("Пароль скопирован")
                            } label: {
                                Label("Скопировать пароль", systemImage: "key.fill")
                            }
                        }
                        if !server.username.isEmpty || !password.isEmpty {
                            Button {
                                controller.injectLoginAutofill(username: server.username, password: password, submit: false)
                            } label: {
                                Label("Заполнить поля без отправки", systemImage: "pencil")
                            }
                        }
                        Divider()
                        Button {
                            useDesktopUA.toggle()
                            controller.setDesktopMode(useDesktopUA)
                        } label: {
                            Label(
                                useDesktopUA ? "Переключить на мобильный вид" : "Переключить на десктопный вид",
                                systemImage: useDesktopUA ? "iphone" : "desktopcomputer"
                            )
                        }
                        Button {
                            controller.reload()
                        } label: {
                            Label("Обновить страницу", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        ZStack {
                            ServerGlassCircle()
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 34, height: 34)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.03, green: 0.05, blue: 0.10))

                // Нативный линейный индикатор загрузки
                if controller.isLoading {
                    ProgressView(value: min(max(controller.estimatedProgress, 0.08), 1.0))
                        .progressViewStyle(.linear)
                        .tint(ServerPalette.iruCyan)
                        .frame(height: 2.5)
                }

                // Область WebView или баннер ошибки подключения
                ZStack {
                    ServerWKWebViewRepresentable(
                        server: server,
                        password: password,
                        useDesktopUA: useDesktopUA,
                        controller: controller
                    )
                    .ignoresSafeArea(edges: .bottom)

                    if let loadError = controller.lastLoadError {
                        NativeEmptyStateView(
                            title: "Не удалось открыть веб-панель",
                            systemImage: "wifi.exclamationmark",
                            description: "\(loadError)\nУбедитесь, что вы подключены к локальной Wi-Fi сети или включили Kerio VPN."
                        ) {
                            Button {
                                Haptics.medium()
                                controller.reload()
                            } label: {
                                Label("Повторить", systemImage: "arrow.clockwise")
                                    .font(.subheadline.weight(.bold))
                            }
                            .nativeGlassButton(prominent: true, tint: ServerPalette.dellBlue)
                            .controlSize(.large)
                        }
                        .padding(20)
                        .background(ServerGlassPanel(cornerRadius: 24))
                        .padding(20)
                    }
                }
            }

            if controller.showJSDialog {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                VStack(spacing: 14) {
                    Text(controller.jsDialogTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    if !controller.jsDialogMessage.isEmpty {
                        Text(controller.jsDialogMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                    }
                    if controller.jsDialogKind == .prompt {
                        TextField("Введите значение", text: $controller.jsPromptText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textFieldStyle(.roundedBorder)
                    }
                    NativeGlassContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            if controller.jsDialogKind == .confirm || controller.jsDialogKind == .prompt {
                                Button("Отмена") {
                                    controller.completeJSDialog(accepted: false)
                                }
                                .frame(maxWidth: .infinity)
                                .nativeGlassButton(prominent: false)
                            }
                            Button("ОК") {
                                controller.completeJSDialog(accepted: true)
                            }
                            .frame(maxWidth: .infinity)
                            .nativeGlassButton(prominent: true, tint: ServerPalette.dellBlue)
                        }
                    }
                }
                .padding(20)
                .background(ServerGlassPanel(cornerRadius: 22))
                .padding(.horizontal, 26)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Контроллер и Representable для WKWebView (Dell iDRAC 7/8/9 + iRU MegaRAC/IPMI)

@MainActor
final class ServerWebConsoleController: ObservableObject {
    enum JSDialogKind { case alert, confirm, prompt }

    @Published var isLoading = true
    @Published var estimatedProgress: Double = 0.1
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentHostDisplay: String = ""
    @Published var lastLoadError: String?

    @Published var showJSDialog = false
    @Published var jsDialogKind: JSDialogKind = .alert
    @Published var jsDialogTitle: String = "Панель сервера"
    @Published var jsDialogMessage: String = ""
    @Published var jsPromptText: String = ""

    fileprivate weak var webView: WKWebView?
    fileprivate var initialURL: URL?
    private var alertCompletion: (() -> Void)?
    private var confirmCompletion: ((Bool) -> Void)?
    private var promptCompletion: ((String?) -> Void)?

    nonisolated static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        lastLoadError = nil
        if let webView = webView {
            if webView.url != nil {
                webView.reload()
            } else if let url = initialURL {
                webView.load(URLRequest(url: url))
            }
        }
    }

    func setDesktopMode(_ enabled: Bool) {
        guard let webView = webView else { return }
        webView.customUserAgent = enabled ? Self.desktopUserAgent : nil
        reload()
    }

    /// Безопасно подставляет логин и пароль в формы Dell iDRAC 7/8/9, iRU AMI MegaRAC, OpenBMC и стандартные веб-формы.
    func injectLoginAutofill(username: String, password: String, submit: Bool) {
        guard let webView = webView else { return }
        guard let userJSON = jsonStringLiteral(username),
              let passJSON = jsonStringLiteral(password) else { return }

        let shouldSubmit = submit ? "true" : "false"
        let js = """
        (function() {
            var userVal = \(userJSON);
            var passVal = \(passJSON);
            var doSubmit = \(shouldSubmit);

            function setNativeValue(el, value) {
                if (!el) return;
                var proto = Object.getPrototypeOf(el);
                var desc = Object.getOwnPropertyDescriptor(proto, 'value')
                    || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
                if (desc && desc.set) {
                    desc.set.call(el, value);
                } else {
                    el.value = value;
                }
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
                el.dispatchEvent(new Event('blur', { bubbles: true }));
            }

            function findInDoc(doc) {
                if (!doc) return false;
                var passInput = doc.querySelector(
                    'input[type="password"]:not([disabled]), input[name="password"], input[name="pwd"], input#password, input#pwd'
                );
                if (!passInput) return false;

                var userInput = doc.querySelector(
                    'input#user, input#userid, input#username, input[name="user"], input[name="username"], input[name="userid"], input[name="login"], input[type="text"]:not([disabled]), input[type="email"]:not([disabled])'
                );

                if (userInput && userVal) setNativeValue(userInput, userVal);
                if (passInput && passVal) setNativeValue(passInput, passVal);

                if (doSubmit) {
                    var btn = doc.querySelector(
                        'button[type="submit"], input[type="submit"], button#btnOK, button#login_btn, button[name="btnOK"], .login-btn, button.btn-primary'
                    );
                    if (btn && !btn.disabled) {
                        setTimeout(function() { btn.click(); }, 180);
                    } else if (passInput.form) {
                        setTimeout(function() { passInput.form.submit(); }, 180);
                    }
                }
                return true;
            }

            if (!findInDoc(document)) {
                var frames = document.querySelectorAll('iframe, frame');
                for (var i = 0; i < frames.length; i++) {
                    try {
                        if (findInDoc(frames[i].contentDocument)) break;
                    } catch (e) {}
                }
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func jsonStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let arrStr = String(data: data, encoding: .utf8),
              arrStr.count >= 2 else { return nil }
        return String(arrStr.dropFirst().dropLast())
    }

    func presentAlert(message: String, completion: @escaping () -> Void) {
        alertCompletion = completion
        jsDialogKind = .alert
        jsDialogTitle = "Сообщение панели"
        jsDialogMessage = message
        showJSDialog = true
    }

    func presentConfirm(message: String, completion: @escaping (Bool) -> Void) {
        confirmCompletion = completion
        jsDialogKind = .confirm
        jsDialogTitle = "Подтверждение"
        jsDialogMessage = message
        showJSDialog = true
    }

    func presentPrompt(message: String, defaultText: String?, completion: @escaping (String?) -> Void) {
        promptCompletion = completion
        jsDialogKind = .prompt
        jsDialogTitle = "Ввод значения"
        jsDialogMessage = message
        jsPromptText = defaultText ?? ""
        showJSDialog = true
    }

    func completeJSDialog(accepted: Bool) {
        switch jsDialogKind {
        case .alert:
            alertCompletion?()
            alertCompletion = nil
        case .confirm:
            confirmCompletion?(accepted)
            confirmCompletion = nil
        case .prompt:
            promptCompletion?(accepted ? jsPromptText : nil)
            promptCompletion = nil
        }
        showJSDialog = false
    }
}

private struct ServerWKWebViewRepresentable: UIViewRepresentable {
    let server: ServerProfile
    let password: String
    let useDesktopUA: Bool
    @ObservedObject var controller: ServerWebConsoleController

    func makeCoordinator() -> Coordinator {
        Coordinator(server: server, password: password, controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.025, green: 0.042, blue: 0.082, alpha: 1.0)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        if useDesktopUA {
            webView.customUserAgent = ServerWebConsoleController.desktopUserAgent
        }

        context.coordinator.observe(webView: webView)
        controller.webView = webView

        if let url = server.normalizedURL {
            controller.initialURL = url
            controller.currentHostDisplay = server.displayAddress
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            req.setValue("ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
            webView.load(req)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Пользовательский переключатель UA управляется через controller.setDesktopMode(_:)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let server: ServerProfile
        let password: String
        let controller: ServerWebConsoleController
        private var didInitialAutofill = false
        private var progressObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?
        private var backObservation: NSKeyValueObservation?
        private var forwardObservation: NSKeyValueObservation?

        nonisolated init(server: ServerProfile, password: String, controller: ServerWebConsoleController) {
            self.server = server
            self.password = password
            self.controller = controller
        }

        func observe(webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                guard let progress = change.newValue else { return }
                Task { @MainActor [weak self] in
                    self?.controller.estimatedProgress = progress
                }
            }
            loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
                guard let loading = change.newValue else { return }
                Task { @MainActor [weak self] in
                    self?.controller.isLoading = loading
                }
            }
            backObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
                guard let can = change.newValue else { return }
                Task { @MainActor [weak self] in
                    self?.controller.canGoBack = can
                }
            }
            forwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
                guard let can = change.newValue else { return }
                Task { @MainActor [weak self] in
                    self?.controller.canGoForward = can
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            let method = challenge.protectionSpace.authenticationMethod
            let challengeHost = challenge.protectionSpace.host.lowercased()
            let expectedHost = server.host?.lowercased() ?? ""

            // Самоподписанный SSL принимается ТОЛЬКО для хоста этого сервера при включённой опции
            if method == NSURLAuthenticationMethodServerTrust,
               server.allowUntrustedSSL,
               !expectedHost.isEmpty,
               challengeHost == expectedHost,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }

            // Автоматический ответ на HTTP Basic / Digest Auth из Keychain (если панель требует его)
            if (method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest),
               challengeHost == expectedHost,
               challenge.previousFailureCount == 0,
               !server.username.isEmpty,
               !password.isEmpty {
                let credential = URLCredential(user: server.username, password: password, persistence: .forSession)
                completionHandler(.useCredential, credential)
                return
            }

            completionHandler(.performDefaultHandling, nil)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            controller.lastLoadError = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let hostText = webView.url?.host ?? server.displayAddress
            let shouldAutoFill = server.autoFillLogin && !didInitialAutofill && !server.username.isEmpty && !password.isEmpty
            if shouldAutoFill {
                didInitialAutofill = true
            }

            controller.currentHostDisplay = hostText
            controller.lastLoadError = nil

            if shouldAutoFill {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    // Задержка нужна для SPA-панелей Dell iDRAC 9 и AMI MegaRAC, которые рендерят форму после DOM load
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    self.controller.injectLoginAutofill(username: self.server.username, password: self.password, submit: false)
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsErr = error as NSError
            if nsErr.code == NSURLErrorCancelled { return }
            controller.lastLoadError = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsErr = error as NSError
            if nsErr.code == NSURLErrorCancelled { return }
            controller.lastLoadError = error.localizedDescription
        }

        // Открываем popup-окна (например, HTML5 KVM / Virtual Console в iDRAC и iRU) в этом же WebView
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // JS alert / confirm / prompt (критично для перезагрузки/подтверждений в iDRAC и IPMI)
        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            controller.presentAlert(message: message, completion: completionHandler)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            controller.presentConfirm(message: message, completion: completionHandler)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            controller.presentPrompt(message: prompt, defaultText: defaultText, completion: completionHandler)
        }
    }
}
