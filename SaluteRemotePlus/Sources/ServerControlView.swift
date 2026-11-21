import SwiftUI

// MARK: - Нативный адаптивный пульт управления Dell iDRAC / iRU BMC

private enum ServerControlTab: String, Identifiable {
    case controls
    case sensors
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controls: return "Пульт"
        case .sensors: return "Датчики"
        case .logs: return "Журналы"
        }
    }

    var symbol: String {
        switch self {
        case .controls: return "slider.horizontal.3"
        case .sensors: return "thermometer"
        case .logs: return "list.bullet.rectangle.portrait"
        }
    }
}

private struct ControlPowerConfirm: Identifiable {
    let id = UUID()
    let action: ServerPowerAction
}

struct ServerControlView: View {
    @ObservedObject var manager: ServerManager
    let server: ServerProfile
    let onOpenWebConsole: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: ServerControlTab = .controls
    @State private var selectedBootTarget: ServerBootTarget = .biosSetup
    @State private var selectedLogServiceId: String?
    @State private var pendingPowerConfirm: ControlPowerConfirm?
    @State private var showBMCResetConfirm = false
    @State private var pendingClearLog: ServerLogServiceInfo?
    @State private var isProbingBMC = false

    private var liveServer: ServerProfile {
        manager.servers.first(where: { $0.id == server.id }) ?? server
    }

    private var telemetry: ServerTelemetry {
        manager.telemetry[liveServer.id] ?? ServerTelemetry()
    }

    private var caps: ServerCapabilities {
        manager.capabilities(for: liveServer) ?? ServerCapabilities()
    }

    private var availableTabs: [ServerControlTab] {
        var tabs: [ServerControlTab] = [.controls]
        let hasSensors = caps.hasAnySensors
            || !telemetry.temperatures.isEmpty
            || !telemetry.fans.isEmpty
            || !telemetry.powerSupplies.isEmpty
            || !telemetry.drives.isEmpty
        if caps.redfishSupported && hasSensors {
            tabs.append(.sensors)
        }
        if caps.redfishSupported && caps.hasLogs {
            tabs.append(.logs)
        }
        return tabs
    }

    private var activeLogService: ServerLogServiceInfo? {
        if let id = selectedLogServiceId,
           let match = caps.logServices.first(where: { $0.id == id }) {
            return match
        }
        return caps.logServices.first
    }

    var body: some View {
        NativeNavigationContainer {
            ZStack {
                ServerLiquidBackdrop()

                VStack(spacing: 0) {
                    if availableTabs.count > 1 {
                        tabBar
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .padding(.bottom, 10)
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            bmcIdentityCard

                            switch selectedTab {
                            case .controls:
                                controlsTabContent
                            case .sensors:
                                sensorsTabContent
                            case .logs:
                                logsTabContent
                            }

                            Spacer(minLength: 28)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }
                    .refreshable {
                        await manager.checkServer(liveServer, deepProbe: true)
                        if selectedTab == .sensors {
                            await manager.loadDetailedSensors(for: liveServer)
                        } else if selectedTab == .logs, let svc = activeLogService {
                            await manager.loadLogs(for: liveServer, service: svc)
                        }
                    }
                }

                if let notice = manager.actionNotice {
                    noticeOverlay(notice)
                }
            }
            .navigationTitle(liveServer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Haptics.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Закрыть")
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.light()
                        Task {
                            isProbingBMC = true
                            await manager.checkServer(liveServer, deepProbe: true)
                            isProbingBMC = false
                            if selectedTab == .logs, let svc = activeLogService {
                                await manager.loadLogs(for: liveServer, service: svc)
                            }
                        }
                    } label: {
                        if isProbingBMC {
                            ProgressView()
                                .tint(ServerPalette.iruCyan)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Обновить")

                    Button {
                        Haptics.medium()
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            onOpenWebConsole()
                        }
                    } label: {
                        Label("Веб", systemImage: "globe")
                    }
                    .tint(ServerPalette.iruCyan)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let firstBoot = caps.allowedBootTargets.first(where: { $0 != .none }) {
                selectedBootTarget = firstBoot
            }
            if selectedLogServiceId == nil {
                selectedLogServiceId = caps.logServices.first?.id
            }
            Task {
                await initialLoad()
            }
        }
        .onChange(of: availableTabs) { newTabs in
            if !newTabs.contains(selectedTab) {
                selectedTab = .controls
            }
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .sensors {
                Task { await manager.loadDetailedSensors(for: liveServer) }
            } else if newTab == .logs, let svc = activeLogService {
                Task { await manager.loadLogs(for: liveServer, service: svc) }
            }
        }
        .alert(
            "Подтвердите действие",
            isPresented: Binding(
                get: { pendingPowerConfirm != nil },
                set: { if !$0 { pendingPowerConfirm = nil } }
            ),
            presenting: pendingPowerConfirm
        ) { item in
            if item.action.isDestructive {
                Button("Выполнить", role: .destructive) {
                    let act = item.action
                    Task { await manager.sendPowerAction(act, to: liveServer) }
                }
            } else {
                Button("Выполнить") {
                    let act = item.action
                    Task { await manager.sendPowerAction(act, to: liveServer) }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { item in
            Text("Отправить «\(item.action.title)» на «\(liveServer.name)»?")
        }
        .alert("Перезагрузить контроллер \(caps.bmcFamily.shortBadge)?", isPresented: $showBMCResetConfirm) {
            Button("Перезагрузить BMC", role: .destructive) {
                Task { await manager.resetBMCManager(for: liveServer) }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будет перезагружен только контроллер управления (iDRAC / BMC). Сам сервер и ОС продолжат работать без остановки.")
        }
        .alert(
            "Очистить журнал?",
            isPresented: Binding(
                get: { pendingClearLog != nil },
                set: { if !$0 { pendingClearLog = nil } }
            ),
            presenting: pendingClearLog
        ) { svc in
            Button("Очистить", role: .destructive) {
                Task { await manager.clearLog(for: liveServer, service: svc) }
            }
            Button("Отмена", role: .cancel) {}
        } message: { svc in
            Text("Все записи в «\(svc.name)» на сервере «\(liveServer.name)» будут удалены.")
        }
    }

    private func initialLoad() async {
        let needsProbe = (liveServer.detectedCapabilities == nil) || !telemetry.redfishAvailable
        if needsProbe {
            isProbingBMC = true
            await manager.checkServer(liveServer, deepProbe: true)
            isProbingBMC = false
        } else if telemetry.temperatures.isEmpty && telemetry.powerSupplies.isEmpty && caps.hasAnySensors {
            await manager.loadDetailedSensors(for: liveServer)
        }
        if let firstBoot = caps.allowedBootTargets.first(where: { $0 != .none }),
           !caps.allowedBootTargets.contains(selectedBootTarget) {
            selectedBootTarget = firstBoot
        }
        if selectedLogServiceId == nil {
            selectedLogServiceId = caps.logServices.first?.id
        }
    }

    // MARK: - Нативный переключатель вкладок (Liquid Glass Segmented Picker iOS 26–27)

    private var tabBar: some View {
        Picker("Раздел", selection: $selectedTab) {
            ForEach(availableTabs) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Карточка автоопределённой версии iDRAC / BMC

    private var bmcIdentityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: liveServer.vendor.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .nativeLiquidGlass(
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous),
                        tint: liveServer.vendor.accentColor.opacity(0.62)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(caps.fullDescriptor)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let model = telemetry.model, !model.isEmpty {
                        Text([telemetry.manufacturer, model].compactMap { $0 }.joined(separator: " "))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    } else if let bmcModel = caps.bmcModel, !bmcModel.isEmpty {
                        Text(bmcModel)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if let powerTitle = telemetry.powerStatusTitle {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(telemetry.powerStatusColor)
                            .frame(width: 7, height: 7)
                            .shadow(color: telemetry.powerStatusColor.opacity(0.8), radius: 3)
                        Text(powerTitle)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(telemetry.powerStatusColor)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(telemetry.powerStatusColor.opacity(0.18))
                            .overlay(Capsule().strokeBorder(telemetry.powerStatusColor.opacity(0.50), lineWidth: 0.9))
                    )
                }
            }

            if telemetry.biosVersion != nil || telemetry.serialNumber != nil || telemetry.cpuCount != nil || telemetry.memoryGiB != nil || telemetry.health != nil || telemetry.systemState != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        if let healthTitle = telemetry.healthTitle {
                            miniInfoChip(label: "Здоровье", value: healthTitle, tint: telemetry.healthColor)
                        }
                        if let stateTitle = telemetry.systemStateTitle {
                            miniInfoChip(label: "Состояние", value: stateTitle, tint: .white.opacity(0.90))
                        }
                        if let cpus = telemetry.cpuCount {
                            miniInfoChip(label: "CPU", value: "\(cpus)", tint: ServerPalette.iruCyan)
                        }
                        if let ram = telemetry.memoryGiB {
                            miniInfoChip(label: "RAM", value: "\(ram) ГБ", tint: ServerPalette.iruCyan)
                        }
                        if let watts = telemetry.powerConsumedWatts {
                            miniInfoChip(label: "Мощность", value: "\(watts) Вт", tint: ServerPalette.onlineGreen)
                        }
                        if let bios = telemetry.biosVersion, !bios.isEmpty {
                            miniInfoChip(label: "BIOS", value: bios, tint: .white.opacity(0.85))
                        }
                        if let sn = telemetry.serialNumber, !sn.isEmpty {
                            miniInfoChip(label: "S/N", value: sn, tint: .white.opacity(0.85))
                        }
                    }
                }
            }
        }
        .padding(14)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Вкладка 1: Динамический пульт управления

    @ViewBuilder
    private var controlsTabContent: some View {
        if caps.redfishSupported {
            powerControlsSection

            if caps.supportsBootOverride && !caps.allowedBootTargets.isEmpty {
                oneTimeBootSection
            }

            serviceActionsSection
        } else {
            legacyBMCFallbackCard
        }
    }

    private var powerControlsSection: some View {
        let actions = caps.allowedResetTypes.isEmpty
            ? [ServerPowerAction.on, .gracefulShutdown, .gracefulRestart, .forceRestart, .forceOff]
            : caps.allowedResetTypes
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Питание сервера",
                badge: "\(actions.count) доступно"
            )

            NativeGlassContainer(spacing: 10) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(actions) { action in
                        Button {
                            if action.requiresConfirmation {
                                Haptics.medium()
                                pendingPowerConfirm = ControlPowerConfirm(action: action)
                            } else {
                                Haptics.medium()
                                Task { await manager.sendPowerAction(action, to: liveServer) }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: action.symbol)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(action.tintColor)
                                    .frame(width: 24)
                                Text(action.shortTitle)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 13)
                            .nativeLiquidGlass(
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous),
                                tint: action.tintColor.opacity(0.24),
                                interactive: true
                            )
                        }
                        .buttonStyle(RemotePressStyle())
                    }
                }
            }
        }
        .padding(14)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var oneTimeBootSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                sectionHeader(title: "Разовая загрузка (One-Time Boot)", badge: nil)
                Spacer()
                if let current = telemetry.bootOverrideTarget,
                   current.lowercased() != "none",
                   let enabled = telemetry.bootOverrideEnabled,
                   enabled.lowercased() != "disabled" {
                    statusPill(text: current, color: ServerPalette.iruCyan)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                NativeGlassContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(caps.allowedBootTargets) { target in
                            let isSelected = (selectedBootTarget == target)
                            Button {
                                Haptics.light()
                                selectedBootTarget = target
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: target.symbol)
                                        .font(.system(size: 11, weight: .bold))
                                    Text(target.title)
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.76))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .nativeLiquidGlass(
                                    in: Capsule(),
                                    tint: isSelected ? liveServer.vendor.accentColor.opacity(0.65) : nil,
                                    interactive: true
                                )
                            }
                            .buttonStyle(RemotePressStyle())
                        }
                    }
                }
            }

            NativeGlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        Haptics.medium()
                        Task { await manager.setOneTimeBoot(selectedBootTarget, for: liveServer, rebootNow: false) }
                    } label: {
                        Text("Назначить")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .nativeGlassButton(prominent: false)

                    if selectedBootTarget != .none {
                        Button {
                            Haptics.medium()
                            Task { await manager.setOneTimeBoot(selectedBootTarget, for: liveServer, rebootNow: true) }
                        } label: {
                            Text("Назначить + Ребут")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .nativeGlassButton(prominent: true, tint: liveServer.vendor.accentColor)
                    }
                }
            }
        }
        .padding(14)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var serviceActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Сервис контроллера", badge: caps.bmcFamily.shortBadge)

            if caps.supportsIndicatorLED {
                let isLit = telemetry.isLocatorLit
                actionRowButton(
                    symbol: isLit ? "lightbulb.fill" : "lightbulb",
                    title: isLit ? "Выключить локатор LED" : "Включить локатор LED (найти в стойке)",
                    subtitle: isLit ? "Синий индикатор на корпусе активен" : "Подсветит сервер в стойке",
                    tint: ServerPalette.iruCyan
                ) {
                    Haptics.light()
                    Task { await manager.toggleLocatorLED(for: liveServer) }
                }
            }

            if caps.supportsManagerReset {
                actionRowButton(
                    symbol: "arrow.triangle.2.circlepath.circle.fill",
                    title: "Перезапустить \(caps.bmcFamily.shortBadge)",
                    subtitle: "Перезапуск контроллера без остановки сервера и ОС",
                    tint: ServerPalette.warnAmber
                ) {
                    Haptics.medium()
                    showBMCResetConfirm = true
                }
            }

            if liveServer.hasValidMAC {
                actionRowButton(
                    symbol: "bolt.horizontal.circle.fill",
                    title: "Отправить Wake-on-LAN",
                    subtitle: "MAC: \(liveServer.macAddress)",
                    tint: ServerPalette.onlineGreen
                ) {
                    Haptics.medium()
                    manager.sendWakeOnLAN(to: liveServer)
                }
            }

            actionRowButton(
                symbol: "desktopcomputer",
                title: "Открыть веб-панель и KVM",
                subtitle: "Полный интерфейс \(caps.bmcFamily.displayName) с авто-входом",
                tint: liveServer.vendor.accentColor
            ) {
                Haptics.medium()
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    onOpenWebConsole()
                }
            }
        }
        .padding(14)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var legacyBMCFallbackCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(ServerPalette.warnAmber)

            VStack(spacing: 5) {
                Text("Redfish API не обнаружен")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Этот контроллер (\(caps.bmcFamily.displayName)) работает в режиме веб-панели или Redfish отключён в настройках BMC. Вы можете управлять сервером через встроенную веб-панель или повторить определение.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
            }

            if liveServer.hasValidMAC {
                actionRowButton(
                    symbol: "bolt.horizontal.circle.fill",
                    title: "Wake-on-LAN (\(liveServer.macAddress))",
                    subtitle: "Разбудить сервер по локальной сети",
                    tint: ServerPalette.onlineGreen
                ) {
                    Haptics.medium()
                    manager.sendWakeOnLAN(to: liveServer)
                }
            }

            Button {
                Haptics.medium()
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    onOpenWebConsole()
                }
            } label: {
                Label("Открыть веб-панель", systemImage: "desktopcomputer")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .nativeGlassButton(prominent: true, tint: ServerPalette.dellBlue)
            .controlSize(.large)
        }
        .padding(18)
        .nativeLiquidGlass(
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            tint: ServerPalette.warnAmber.opacity(0.14)
        )
    }

    // MARK: - Вкладка 2: Датчики (адаптивно по доступным метрикам)

    private var sensorsTabContent: some View {
        VStack(spacing: 14) {
            if manager.loadingSensorsFor.contains(liveServer.id) {
                HStack(spacing: 10) {
                    ProgressView().tint(ServerPalette.iruCyan)
                    Text("Опрос датчиков \(caps.bmcFamily.shortBadge)…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity)
                .padding(14)
                .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if telemetry.powerConsumedWatts != nil || !telemetry.powerSupplies.isEmpty {
                powerSensorsCard
            }

            if !telemetry.temperatures.isEmpty {
                temperatureSensorsCard
            }

            if !telemetry.fans.isEmpty {
                fanSensorsCard
            }

            if !telemetry.drives.isEmpty {
                drivesSensorsCard
            }

            if !telemetry.voltages.isEmpty {
                voltageSensorsCard
            }
        }
    }

    private var powerSensorsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Электропитание и БП",
                badge: telemetry.powerConsumedWatts.map { "\($0) Вт" }
            )

            if let consumed = telemetry.powerConsumedWatts {
                NativeLabeledRow(title: "Текущее потребление") {
                    Text(
                        telemetry.powerCapacityWatts.map { "\(consumed) / \($0) Вт" } ?? "\(consumed) Вт"
                    )
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(ServerPalette.onlineGreen)
                }
                .font(.caption)
            }

            ForEach(telemetry.powerSupplies) { psu in
                HStack(spacing: 10) {
                    Circle()
                        .fill(healthColor(psu.health))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(psu.name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                        if let model = psu.model, !model.isEmpty {
                            Text(model)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.54))
                        }
                    }
                    Spacer()
                    if let out = psu.powerOutputWatts {
                        Text("\(out) Вт")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(ServerPalette.iruCyan)
                    } else if let cap = psu.capacityWatts {
                        Text("\(cap) Вт")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.70))
                    }
                    if let h = psu.health {
                        statusPill(text: h.uppercased(), color: healthColor(h))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var temperatureSensorsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Температуры",
                badge: "\(telemetry.temperatures.count) датч."
            )

            ForEach(telemetry.temperatures) { sensor in
                let tempColor = temperatureColor(sensor)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(sensor.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(sensor.readingC.rounded()))°C")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(tempColor)
                        if let crit = sensor.upperCriticalC {
                            Text("/ \(Int(crit.rounded()))°")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }

                    let maxVal = max(sensor.upperCriticalC ?? 95.0, 95.0)
                    ProgressView(value: min(max(sensor.readingC, 0), maxVal), total: maxVal)
                        .progressViewStyle(.linear)
                        .tint(tempColor)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var fanSensorsCard: some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Вентиляторы", badge: "\(telemetry.fans.count)")

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(telemetry.fans) { fan in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(healthColor(fan.health))
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fan.name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                            Text("\(fan.reading) \(fan.units)")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(.white)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.26))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(14)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var drivesSensorsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Диски и хранилище", badge: "\(telemetry.drives.count)")

            ForEach(telemetry.drives) { drive in
                HStack(spacing: 10) {
                    Image(systemName: (drive.mediaType?.uppercased() == "SSD") ? "memorychip" : "internaldrive.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(healthColor(drive.health))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drive.name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        let subtitle = [
                            drive.mediaType,
                            drive.capacityGiB.map { formatCapacity(gib: $0) },
                            drive.model
                        ].compactMap { $0 }.joined(separator: " · ")
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.56))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if let h = drive.health {
                        statusPill(text: h.uppercased(), color: healthColor(h))
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .padding(14)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var voltageSensorsCard: some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Напряжения", badge: "\(telemetry.voltages.count)")

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(telemetry.voltages.prefix(16)) { volt in
                    HStack {
                        Text(volt.name)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(String(format: "%.2f В", volt.readingVolts))
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(healthColor(volt.health))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.24))
                    )
                }
            }
        }
        .padding(14)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Вкладка 3: Журналы (SEL / Lifecycle Log / FaultList / EventLog)

    private var logsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                NativeGlassContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(caps.logServices) { svc in
                            let isSelected = (activeLogService?.id == svc.id)
                            Button {
                                Haptics.light()
                                selectedLogServiceId = svc.id
                                Task { await manager.loadLogs(for: liveServer, service: svc) }
                            } label: {
                                Text(svc.name)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.74))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .nativeLiquidGlass(
                                        in: Capsule(),
                                        tint: isSelected ? liveServer.vendor.accentColor.opacity(0.65) : nil,
                                        interactive: true
                                    )
                            }
                            .buttonStyle(RemotePressStyle())
                        }
                    }
                }
            }

            if let svc = activeLogService {
                let loadingKey = "\(liveServer.id.uuidString)::\(svc.id)"
                let isLoading = manager.loadingLogsFor.contains(loadingKey)
                let entries = manager.logsByServer[liveServer.id]?[svc.id] ?? []

                HStack {
                    Text("\(svc.name) · \(entries.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()

                    Button {
                        Haptics.light()
                        Task { await manager.loadLogs(for: liveServer, service: svc) }
                    } label: {
                        Label("Обновить", systemImage: "arrow.clockwise")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(ServerPalette.iruCyan)
                    }

                    if svc.canClear {
                        Button {
                            Haptics.medium()
                            pendingClearLog = svc
                        } label: {
                            Label("Очистить", systemImage: "trash")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(ServerPalette.dangerRed)
                        }
                        .padding(.leading, 8)
                    }
                }
                .padding(.horizontal, 4)

                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView().tint(ServerPalette.iruCyan)
                        Text("Загрузка записей журнала…")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.70))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else if entries.isEmpty {
                    NativeEmptyStateView(
                        title: "Журнал пуст",
                        systemImage: "list.bullet.rectangle.portrait",
                        description: "Записи в журнале отсутствуют или не возвращены этим контроллером."
                    ) {
                        EmptyView()
                    }
                    .padding(14)
                    .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        ForEach(entries) { entry in
                            logEntryRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func logEntryRow(_ entry: ServerLogEntry) -> some View {
        let sevColor = healthColor(entry.severity)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(sevColor)
                    .frame(width: 7, height: 7)
                if let sev = entry.severity, !sev.isEmpty {
                    Text(sev.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(sevColor)
                }
                if let sensor = entry.sensorType, !sensor.isEmpty {
                    Text("· \(sensor)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer()
                if let ts = entry.created {
                    Text(formatLogTimestamp(ts))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }

            Text(entry.message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(sevColor.opacity(0.24), lineWidth: 1)
                )
        )
    }

    // MARK: - Вспомогательные компоненты

    private func sectionHeader(title: String, badge: String?) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ServerPalette.iruCyan)
            Spacer()
            if let badge = badge {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    private func actionRowButton(
        symbol: String,
        title: String,
        subtitle: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(0.20))
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(11)
            .nativeLiquidGlass(
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                interactive: true
            )
        }
        .buttonStyle(RemotePressStyle())
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.16))
                    .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 0.8))
            )
    }

    private func miniInfoChip(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.30))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
        )
    }

    private func noticeOverlay(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .nativeLiquidGlass(in: Capsule(), tint: ServerPalette.dellBlue.opacity(0.32))
                .padding(.bottom, 22)
        }
        .allowsHitTesting(false)
    }

    private func healthColor(_ raw: String?) -> Color {
        switch raw?.lowercased() {
        case "ok": return ServerPalette.onlineGreen
        case "warning": return ServerPalette.warnAmber
        case "critical": return ServerPalette.dangerRed
        default: return ServerPalette.iruCyan
        }
    }

    private func temperatureColor(_ sensor: ServerTempSensor) -> Color {
        if let crit = sensor.upperCriticalC, sensor.readingC >= crit - 5 {
            return ServerPalette.dangerRed
        }
        if let warn = sensor.upperWarningC, sensor.readingC >= warn {
            return ServerPalette.warnAmber
        }
        if sensor.readingC >= 78 { return ServerPalette.dangerRed }
        if sensor.readingC >= 62 { return ServerPalette.warnAmber }
        return ServerPalette.iruCyan
    }

    private func formatCapacity(gib: Int) -> String {
        if gib >= 1024 {
            let tb = Double(gib) / 1024.0
            return String(format: "%.1f ТБ", tb)
        }
        return "\(gib) ГБ"
    }

    private func formatLogTimestamp(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: "Z", with: "")
        if cleaned.count >= 16 {
            return String(cleaned.prefix(16))
        }
        return cleaned
    }
}
