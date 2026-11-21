import SwiftUI

// MARK: - Автопоиск Dell iDRAC и iRU BMC в локальной сети / Kerio VPN

struct ServerDiscoverySheet: View {
    @ObservedObject var manager: ServerManager
    let onSaveDiscovered: (ServerEditorPrefill) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var subnetInput: String = ""
    @State private var includeHTTP: Bool = false
    @State private var showAllWebHosts: Bool = false

    private var visibleResults: [DiscoveredBMC] {
        if showAllWebHosts {
            return manager.discoveredBMCs
        }
        let confirmed = manager.discoveredBMCs.filter { $0.isConfirmedBMC }
        return confirmed
    }

    private var otherHostsCount: Int {
        manager.discoveredBMCs.filter { !$0.isConfirmedBMC }.count
    }

    var body: some View {
        NativeNavigationContainer {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    scannerConfigCard

                    if manager.isScanningNetwork || !manager.scanStatusText.isEmpty {
                        scanProgressCard
                    }

                    resultsSection

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .nativeGlassSheetContainerBackground()
            .navigationTitle("Поиск iDRAC / BMC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Закрыть") {
                        manager.stopNetworkScan()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Text(manager.networkRoute.shortBadge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ServerPalette.bgTop)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(manager.networkRoute.indicatorColor))
                }
            }
        }
        .nativePresentationSheet()
        .preferredColorScheme(.dark)
        .onAppear {
            manager.refreshSuggestedSubnets()
            if subnetInput.isEmpty {
                subnetInput = manager.suggestedSubnets.first ?? "192.168.1.0/24"
            }
        }
        .onDisappear {
            manager.stopNetworkScan()
        }
    }

    // MARK: - Настройка подсети и запуск сканера

    private var scannerConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ПОДСЕТЬ ДЛЯ СКАНИРОВАНИЯ (LAN / KERIO VPN)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ServerPalette.iruCyan)

            TextField("192.168.1.0/24 или 10.0.0.1-50", text: $subnetInput)
                .keyboardType(.numbersAndPunctuation)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .nativeLiquidGlass(
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                    interactive: true
                )

            if !manager.suggestedSubnets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    NativeGlassContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(manager.suggestedSubnets, id: \.self) { cidr in
                                let selected = (subnetInput == cidr)
                                Button {
                                    Haptics.light()
                                    subnetInput = cidr
                                } label: {
                                    Text(cidr)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.76))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 7)
                                        .nativeLiquidGlass(
                                            in: Capsule(),
                                            tint: selected ? ServerPalette.dellBlue.opacity(0.65) : nil,
                                            interactive: true
                                        )
                                }
                                .buttonStyle(RemotePressStyle())
                            }
                        }
                    }
                }
            }

            Toggle(isOn: $includeHTTP) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Проверять порт 80 (HTTP)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Для старых iDRAC и BMC без HTTPS (сканирование немного дольше)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .tint(ServerPalette.iruCyan)

            Button {
                Haptics.medium()
                if manager.isScanningNetwork {
                    manager.stopNetworkScan()
                } else {
                    manager.startNetworkScan(subnetInput: subnetInput, includeHTTP: includeHTTP)
                }
            } label: {
                Label(
                    manager.isScanningNetwork ? "Остановить сканирование" : "Найти iDRAC и iRU BMC",
                    systemImage: manager.isScanningNetwork ? "stop.fill" : "dot.radiowaves.left.and.right"
                )
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .nativeGlassButton(
                prominent: true,
                tint: manager.isScanningNetwork ? ServerPalette.dangerRed : ServerPalette.dellBlue
            )
            .controlSize(.large)
        }
        .padding(14)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Прогресс сканирования

    private var scanProgressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if manager.isScanningNetwork {
                    ProgressView()
                        .tint(ServerPalette.iruCyan)
                        .scaleEffect(0.8)
                }
                Text(manager.scanStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                Spacer()
                Text("\(Int((manager.scanProgress * 100).rounded()))%")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(ServerPalette.iruCyan)
            }

            ProgressView(value: min(max(manager.scanProgress, 0.0), 1.0))
                .progressViewStyle(.linear)
                .tint(ServerPalette.iruCyan)
        }
        .padding(13)
        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Найденные контроллеры

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if otherHostsCount > 0 {
                Toggle(isOn: $showAllWebHosts) {
                    Text("Показать прочие HTTPS/HTTP хосты (\(otherHostsCount))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .tint(ServerPalette.iruCyan)
                .padding(.horizontal, 6)
            }

            if visibleResults.isEmpty {
                if !manager.isScanningNetwork && manager.discoveredBMCs.isEmpty {
                    NativeEmptyStateView(
                        title: "Поиск контроллеров в сети",
                        systemImage: "magnifyingglass.circle",
                        description: "Сканер определяет Dell iDRAC (7/8/9), iRU AMI MegaRAC и OpenBMC по Redfish и заголовкам веб-интерфейса. Работает как по локальному Wi-Fi, так и через Kerio VPN."
                    ) {
                        EmptyView()
                    }
                    .padding(12)
                    .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else if !manager.isScanningNetwork && otherHostsCount > 0 && !showAllWebHosts {
                    Text("Подтверждённые iDRAC/BMC не обнаружены, но найдено \(otherHostsCount) веб-хостов — включите переключатель выше, чтобы увидеть их.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            } else {
                ForEach(visibleResults) { item in
                    discoveredCard(item)
                }
            }
        }
    }

    private func discoveredCard(_ item: DiscoveredBMC) -> some View {
        let alreadySaved = manager.isAlreadySaved(ip: item.ip)

        return HStack(spacing: 12) {
            Image(systemName: item.vendor.symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .nativeLiquidGlass(
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    tint: item.vendor.accentColor.opacity(0.62)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.suggestedName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if item.isConfirmedBMC {
                        Text(item.bmcFamily.shortBadge)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(item.vendor.accentColor.opacity(0.45)))
                    }
                }

                Text("\(item.addressURLString) · \(item.latencyMs) мс")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))

                HStack(spacing: 6) {
                    if item.redfishSupported {
                        Text(item.redfishVersion.map { "Redfish \($0)" } ?? "Redfish API")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ServerPalette.onlineGreen)
                    } else if let title = item.detectedTitle, !title.isEmpty {
                        Text(title)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.54))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            if alreadySaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("В списке")
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(ServerPalette.onlineGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(ServerPalette.onlineGreen.opacity(0.16))
                )
            } else {
                Button {
                    Haptics.medium()
                    manager.stopNetworkScan()
                    let prefill = ServerEditorPrefill(
                        name: item.suggestedName,
                        vendor: item.vendor,
                        address: item.addressURLString,
                        username: item.vendor.defaultUsername,
                        redfishEnabled: item.redfishSupported || item.isConfirmedBMC,
                        notes: item.detectedTitle ?? ""
                    )
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                        onSaveDiscovered(prefill)
                    }
                } label: {
                    Text("Сохранить")
                        .font(.caption.weight(.bold))
                }
                .nativeGlassButton(prominent: true, tint: ServerPalette.dellBlue)
                .controlSize(.small)
            }
        }
        .padding(13)
        .nativeLiquidGlass(
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            tint: item.isConfirmedBMC ? item.vendor.accentColor.opacity(0.14) : nil
        )
    }
}
