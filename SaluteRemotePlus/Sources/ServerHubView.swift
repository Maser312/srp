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

struct ServerHubView: View {
    @ObservedObject var manager: ServerManager
    let onExit: () -> Void

    @State private var editingProfile: ServerProfile?
    @State private var isCreatingNew = false
    @State private var newServerDefaultVendor: ServerVendor = .dellIDRAC
    @State private var activeConsoleServer: ServerProfile?
    @State private var powerMenuServer: ServerProfile?
    @State private var pendingConfirmAction: (server: ServerProfile, action: ServerPowerAction)?
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
                        .background(
                            Capsule()
                                .fill(Color(red: 0.05, green: 0.12, blue: 0.22).opacity(0.95))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(ServerPalette.glassAccentBorder, lineWidth: 1)
                                )
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 10, y: 4)
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
                defaultVendor: newServerDefaultVendor
            )
        }
        .sheet(item: $editingProfile) { profile in
            ServerEditorSheet(
                manager: manager,
                existing: profile,
                defaultVendor: profile.vendor
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
                Button("Включить сервер (Redfish Power On)") {
                    Task { await manager.sendPowerAction(.on, to: server) }
                }
                Button("Мягкое выключение (ACPI Shutdown)") {
                    pendingConfirmAction = (server, .gracefulShutdown)
                }
                Button("Мягкая перезагрузка (Graceful Restart)") {
                    pendingConfirmAction = (server, .gracefulRestart)
                }
                Button("Жёсткая перезагрузка (Force Reset)", role: .destructive) {
                    pendingConfirmAction = (server, .forceRestart)
                }
                Button("Принудительно обесточить (Force Off)", role: .destructive) {
                    pendingConfirmAction = (server, .forceOff)
                }
                Button("Переключить индикатор локатора LED") {
                    Task { await manager.toggleLocatorLED(for: server) }
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
            Button("Выполнить", role: item.action.isDestructive ? .destructive : nil) {
                let targetServer = item.server
                let targetAction = item.action
                Task { await manager.sendPowerAction(targetAction, to: targetServer) }
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
                HStack(spacing: 10) {
                    Image(systemName: "lock.open.fill")
                        .font(.body.weight(.bold))
                    Text("Разблокировать")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(ServerPalette.accentButtonGradient)
                        .overlay(Capsule().strokeBorder(ServerPalette.glassAccentBorder, lineWidth: 1))
                )
            }
            .buttonStyle(RemotePressStyle())

            Spacer()
        }
    }

    // MARK: - Основной интерфейс

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerBar

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
                                hasPassword: !manager.password(for: server).isEmpty,
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
                                    Task { await manager.checkServer(server) }
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

                        quickAddRow
                    }

                    Spacer(minLength: 26)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                onExit()
            } label: {
                ZStack {
                    ServerGlassCircle()
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(RemotePressStyle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ServerPalette.iruCyan)
                    Text("СЕРВЕРЫ")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text("Dell iDRAC · iRU BMC · Kerio VPN")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Переключатель защиты Face ID
            Button {
                Haptics.light()
                manager.requireBiometricLock.toggle()
                manager.showNotice(
                    manager.requireBiometricLock
                        ? "Защита входа по Face ID включена"
                        : "Защита входа по Face ID отключена"
                )
            } label: {
                ZStack {
                    ServerGlassCircle()
                    Image(systemName: manager.requireBiometricLock ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(manager.requireBiometricLock ? ServerPalette.iruCyan : .white.opacity(0.75))
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(RemotePressStyle())

            // Обновить статус всех серверов
            Button {
                Haptics.light()
                manager.refreshAllServers()
            } label: {
                ZStack {
                    ServerGlassCircle()
                    if manager.isRefreshingAll {
                        ProgressView()
                            .tint(ServerPalette.iruCyan)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(RemotePressStyle())

            // Добавить новый сервер
            Button {
                Haptics.medium()
                newServerDefaultVendor = .dellIDRAC
                isCreatingNew = true
            } label: {
                ZStack {
                    ServerGlassCircle(accent: true)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(RemotePressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
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
        VStack(spacing: 18) {
            ZStack {
                ServerGlassCircle(accent: true)
                    .frame(width: 68, height: 68)
                Image(systemName: "server.rack")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("Добавьте серверы Dell и iRU")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Адреса, логины и пароли хранятся локально в защищённом iOS Keychain. Поддерживается авто-вход, самоподписанный SSL, десктопный режим и Redfish-телеметрия.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button {
                    Haptics.medium()
                    newServerDefaultVendor = .dellIDRAC
                    isCreatingNew = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "server.rack")
                            .font(.body.weight(.bold))
                        Text("Добавить сервер Dell (iDRAC)")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [ServerVendor.dellIDRAC.accentColor, ServerVendor.dellIDRAC.secondaryAccentColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(ServerPalette.glassAccentBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(RemotePressStyle())

                Button {
                    Haptics.medium()
                    newServerDefaultVendor = .iruBMC
                    isCreatingNew = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cpu")
                            .font(.body.weight(.bold))
                        Text("Добавить сервер iRU (BMC / IPMI)")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [ServerVendor.iruBMC.accentColor, ServerVendor.iruBMC.secondaryAccentColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(ServerPalette.glassAccentBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(RemotePressStyle())

                Button {
                    Haptics.light()
                    newServerDefaultVendor = .genericWeb
                    isCreatingNew = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                            .font(.body.weight(.semibold))
                        Text("Другая веб-панель (Proxmox, ESXi, роутер)")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Image(systemName: "plus")
                            .font(.footnote.weight(.bold))
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(ServerPalette.glassBorderGradient, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(RemotePressStyle())
            }
        }
        .padding(20)
        .background(ServerGlassPanel(cornerRadius: 24, accentGlow: ServerPalette.dellBlue))
    }

    private var quickAddRow: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                newServerDefaultVendor = .dellIDRAC
                isCreatingNew = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                    Text("Dell iDRAC")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(ServerGlassPanel(cornerRadius: 16, accentGlow: ServerVendor.dellIDRAC.accentColor))
            }
            .buttonStyle(RemotePressStyle())

            Button {
                Haptics.light()
                newServerDefaultVendor = .iruBMC
                isCreatingNew = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                    Text("iRU BMC")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(ServerGlassPanel(cornerRadius: 16, accentGlow: ServerVendor.iruBMC.accentColor))
            }
            .buttonStyle(RemotePressStyle())
        }
    }
}

// MARK: - Карточка сервера на дашборде

private struct ServerDashboardCard: View {
    let server: ServerProfile
    let telemetry: ServerTelemetry
    let hasPassword: Bool
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

                        Text(server.vendor.shortBadge)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
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
                        .font(.caption.monospaced())
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
                            if let on = telemetry.isPoweredOn {
                                telemetryChip(
                                    symbol: "power",
                                    text: on ? "ВКЛ" : "ВЫКЛ",
                                    color: on ? ServerPalette.onlineGreen : ServerPalette.warnAmber
                                )
                            }
                            if let health = telemetry.health {
                                telemetryChip(
                                    symbol: health.lowercased() == "ok" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                    text: health.uppercased(),
                                    color: telemetry.healthColor
                                )
                            }
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

            // Основные действия: Открыть панель + Питание / WoL
            HStack(spacing: 10) {
                Button(action: onOpenConsole) {
                    HStack(spacing: 8) {
                        Image(systemName: "desktopcomputer")
                            .font(.subheadline.weight(.bold))
                        Text("Открыть веб-панель")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [server.vendor.accentColor, server.vendor.secondaryAccentColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .strokeBorder(ServerPalette.glassAccentBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(RemotePressStyle())

                Button(action: onPowerMenu) {
                    HStack(spacing: 5) {
                        Image(systemName: "power")
                            .font(.subheadline.weight(.bold))
                        Text("Питание")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .strokeBorder(ServerPalette.glassBorderGradient, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(RemotePressStyle())
            }
        }
        .padding(16)
        .background(ServerGlassPanel(cornerRadius: 22, accentGlow: server.vendor.accentColor))
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
        ZStack {
            ServerLiquidBackdrop()

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 40, height: 4)
                    .padding(.top, 10)

                HStack {
                    Button("Отмена") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.70))

                    Spacer()

                    Text(existing == nil ? "Новый сервер" : "Настройки сервера")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button("Сохранить") { save() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ServerPalette.iruCyan)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Выбор типа сервера
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("Тип панели управления")
                            HStack(spacing: 8) {
                                ForEach(ServerVendor.allCases) { item in
                                    Button {
                                        Haptics.light()
                                        let wasDefaultUser = username.isEmpty || username == vendor.defaultUsername
                                        vendor = item
                                        if wasDefaultUser {
                                            username = item.defaultUsername
                                        }
                                    } label: {
                                        VStack(spacing: 5) {
                                            Image(systemName: item.symbol)
                                                .font(.system(size: 16, weight: .bold))
                                            Text(item.shortBadge)
                                                .font(.system(size: 10, weight: .bold))
                                                .lineLimit(1)
                                        }
                                        .foregroundStyle(vendor == item ? .white : .white.opacity(0.65))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(vendor == item ? item.accentColor.opacity(0.45) : Color.white.opacity(0.06))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .strokeBorder(
                                                            vendor == item ? item.accentColor : Color.white.opacity(0.12),
                                                            lineWidth: vendor == item ? 1.4 : 1
                                                        )
                                                )
                                        )
                                    }
                                    .buttonStyle(RemotePressStyle())
                                }
                            }
                        }
                        .padding(14)
                        .background(ServerGlassPanel(cornerRadius: 20))

                        // Основные поля
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("Подключение и учётные данные")

                            editorField(label: "Название", placeholder: vendor == .dellIDRAC ? "Dell PowerEdge R740" : (vendor == .iruBMC ? "iRU Rock S2108" : "Основной сервер"), text: $name)
                            editorField(label: "Адрес (IP или URL)", placeholder: vendor.addressPlaceholder, text: $address, keyboard: .URL, disableAutocap: true)
                            editorField(label: "Логин", placeholder: vendor.defaultUsername, text: $username, disableAutocap: true)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Пароль (сохраняется в iOS Keychain)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.68))
                                HStack(spacing: 8) {
                                    Group {
                                        if showPassword {
                                            TextField("Введите пароль", text: $password)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                        } else {
                                            SecureField("Введите пароль", text: $password)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                        }
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.white)

                                    Button {
                                        showPassword.toggle()
                                    } label: {
                                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.65))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.black.opacity(0.32))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                        )
                                )
                            }

                            editorField(label: "MAC-адрес для Wake-on-LAN (необязательно)", placeholder: "AA:BB:CC:DD:EE:FF", text: $macAddress, disableAutocap: true)
                            editorField(label: "Заметка (стойка, роль, порт)", placeholder: "Стойка 1 · Виртуализация", text: $notes)
                        }
                        .padding(14)
                        .background(ServerGlassPanel(cornerRadius: 20))

                        // Параметры совместимости Dell iDRAC / iRU BMC
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("Параметры веб-панели и BMC")

                            toggleRow(
                                title: "Доверять самоподписанному SSL",
                                subtitle: "Нужно для локальных сертификатов Dell iDRAC и iRU BMC",
                                isOn: $allowUntrustedSSL
                            )
                            Divider().background(Color.white.opacity(0.10))
                            toggleRow(
                                title: "Десктопный режим (Desktop UA)",
                                subtitle: "Предотвращает поломку вёрстки iDRAC / MegaRAC на iPhone",
                                isOn: $desktopMode
                            )
                            Divider().background(Color.white.opacity(0.10))
                            toggleRow(
                                title: "Автозаполнение логина и пароля",
                                subtitle: "Автоматически подставляет данные из Keychain на странице входа",
                                isOn: $autoFillLogin
                            )
                            Divider().background(Color.white.opacity(0.10))
                            toggleRow(
                                title: "Опрос Redfish API (питание, °C, статус)",
                                subtitle: "Показывает состояние железа прямо на карточке сервера",
                                isOn: $redfishEnabled
                            )
                        }
                        .padding(14)
                        .background(ServerGlassPanel(cornerRadius: 20))

                        if let err = validationError {
                            Text(err)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ServerPalette.dangerRed)
                                .padding(.horizontal, 6)
                        }

                        Button(action: save) {
                            Text(existing == nil ? "Добавить сервер" : "Сохранить изменения")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(ServerPalette.accentButtonGradient)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(ServerPalette.glassAccentBorder, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(RemotePressStyle())
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
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
            } else {
                vendor = defaultVendor
                username = defaultVendor.defaultUsername
                redfishEnabled = (defaultVendor != .genericWeb)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(ServerPalette.iruCyan)
    }

    private func editorField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        disableAutocap: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocapitalization(disableAutocap ? .none : .sentences)
                .disableAutocorrection(disableAutocap)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.32))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
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
                    .foregroundStyle(.white.opacity(0.56))
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
                            .foregroundStyle(controller.canGoBack ? .white : .white.opacity(0.28))
                            .frame(width: 30, height: 34)
                    }
                    .disabled(!controller.canGoBack)

                    Button {
                        controller.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(controller.canGoForward ? .white : .white.opacity(0.28))
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

                // Индикатор загрузки
                if controller.isLoading {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Color.white.opacity(0.08)
                            Rectangle()
                                .fill(ServerPalette.iruCyan)
                                .frame(width: geo.size.width * CGFloat(max(0.08, controller.estimatedProgress)))
                                .animation(.easeOut(duration: 0.2), value: controller.estimatedProgress)
                        }
                    }
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
                        VStack(spacing: 14) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(ServerPalette.warnAmber)
                            Text("Не удалось открыть веб-панель")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                            Text(loadError)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.68))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Text("Убедитесь, что вы подключены к локальной Wi-Fi сети или включили Kerio VPN.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Button {
                                Haptics.medium()
                                controller.reload()
                            } label: {
                                Text("Повторить")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(ServerPalette.accentButtonGradient))
                            }
                            .buttonStyle(RemotePressStyle())
                        }
                        .padding(24)
                        .background(ServerGlassPanel(cornerRadius: 22))
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
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.35))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                            )
                    }
                    HStack(spacing: 10) {
                        if controller.jsDialogKind == .confirm || controller.jsDialogKind == .prompt {
                            Button {
                                controller.completeJSDialog(accepted: false)
                            } label: {
                                Text("Отмена")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.white.opacity(0.10))
                                    )
                            }
                            .buttonStyle(RemotePressStyle())
                        }
                        Button {
                            controller.completeJSDialog(accepted: true)
                        } label: {
                            Text("ОК")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(ServerPalette.accentButtonGradient)
                                )
                        }
                        .buttonStyle(RemotePressStyle())
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

    static let desktopUserAgent =
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let server: ServerProfile
        let password: String
        let controller: ServerWebConsoleController
        private var didInitialAutofill = false
        private var progressObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?
        private var backObservation: NSKeyValueObservation?
        private var forwardObservation: NSKeyValueObservation?

        init(server: ServerProfile, password: String, controller: ServerWebConsoleController) {
            self.server = server
            self.password = password
            self.controller = controller
        }

        func observe(webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                let progress = view.estimatedProgress
                Task { @MainActor [weak self] in
                    self?.controller.estimatedProgress = progress
                }
            }
            loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                let loading = view.isLoading
                Task { @MainActor [weak self] in
                    self?.controller.isLoading = loading
                }
            }
            backObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                let can = view.canGoBack
                Task { @MainActor [weak self] in
                    self?.controller.canGoBack = can
                }
            }
            forwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                let can = view.canGoForward
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
            Task { @MainActor [weak self] in
                self?.controller.lastLoadError = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let hostText = webView.url?.host ?? server.displayAddress
            let shouldAutoFill = server.autoFillLogin && !didInitialAutofill && !server.username.isEmpty && !password.isEmpty
            if shouldAutoFill {
                didInitialAutofill = true
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.controller.currentHostDisplay = hostText
                self.controller.lastLoadError = nil

                if shouldAutoFill {
                    // Задержка нужна для SPA-панелей Dell iDRAC 9 и AMI MegaRAC, которые рендерят форму после DOM load
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    self.controller.injectLoginAutofill(username: self.server.username, password: self.password, submit: false)
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsErr = error as NSError
            if nsErr.code == NSURLErrorCancelled { return }
            Task { @MainActor [weak self] in
                self?.controller.lastLoadError = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsErr = error as NSError
            if nsErr.code == NSURLErrorCancelled { return }
            Task { @MainActor [weak self] in
                self?.controller.lastLoadError = error.localizedDescription
            }
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
            Task { @MainActor [weak self] in
                self?.controller.presentAlert(message: message, completion: completionHandler)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            Task { @MainActor [weak self] in
                self?.controller.presentConfirm(message: message, completion: completionHandler)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            Task { @MainActor [weak self] in
                self?.controller.presentPrompt(message: prompt, defaultText: defaultText, completion: completionHandler)
            }
        }
    }
}
