import SwiftUI

// MARK: - Хаб управления телевизорами (Сбер Салют / Android TV & Google TV / YaOS) — нативный Liquid Glass

struct TVHubConnectionView: View {
    @ObservedObject var remote: UniversalTVRemoteManager
    var isPresentedAsSheet: Bool = false
    let onClose: () -> Void

    @State private var showAddSheet = false
    @State private var editingProfile: SavedTVProfile?

    var body: some View {
        ZStack {
            if !isPresentedAsSheet {
                NativeDarkBackdrop()
            }

            VStack(spacing: 0) {
                // Верхняя нативная стеклянная панель
                NativeGlassContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap()
                            onClose()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isPresentedAsSheet ? "xmark" : "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                Text(isPresentedAsSheet ? "Закрыть" : "Меню")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .nativeLiquidGlass(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())

                        Spacer()

                        Text("Телевизоры")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        Spacer()

                        Button {
                            Haptics.tap()
                            remote.refreshDiscovery()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .nativeLiquidGlass(in: Circle(), interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())
                        .accessibilityLabel("Обновить поиск ТВ")

                        Button {
                            Haptics.tap()
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 40, height: 40)
                                .nativeLiquidGlass(in: Circle(), tint: Color.white.opacity(0.90), interactive: true)
                        }
                        .buttonStyle(RemotePressStyle())
                        .accessibilityLabel("Добавить телевизор вручную")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, isPresentedAsSheet ? 20 : 12)
                .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    NativeGlassContainer(spacing: 16) {
                        VStack(spacing: 18) {
                            // Карточка статуса поиска
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(remote.errorText == nil ? SberPalette.brightGreen : SberPalette.coral)
                                    .frame(width: 9, height: 9)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(remote.errorText ?? "Поиск ТВ в сети Wi-Fi")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text("Сбер Салют · Android TV / Google TV · YaOS")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.56))
                                }

                                Spacer()

                                if remote.isScanning || remote.discoveredTVs.isEmpty {
                                    ProgressView()
                                        .tint(.white.opacity(0.78))
                                }
                            }
                            .padding(14)
                            .nativeLiquidGlass(
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                                tint: remote.errorText != nil ? SberPalette.coral.opacity(0.25) : nil
                            )

                            // Раздел 1: Сохранённые телевизоры (мульти-пульт)
                            if !remote.savedTVs.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Мои телевизоры")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white.opacity(0.62))
                                        Spacer()
                                        Text("\(remote.savedTVs.count)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white.opacity(0.45))
                                    }
                                    .padding(.horizontal, 4)

                                    ForEach(remote.savedTVs) { profile in
                                        savedTVRow(profile)
                                    }
                                }
                            }

                            // Раздел 2: Автопоиск по Wi-Fi
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Найденные в сети Wi-Fi")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.62))
                                    Spacer()
                                }
                                .padding(.horizontal, 4)

                                if remote.discoveredTVs.isEmpty {
                                    VStack(spacing: 10) {
                                        Image(systemName: "tv.and.mediabox")
                                            .font(.system(size: 30, weight: .regular))
                                            .foregroundStyle(.white.opacity(0.38))
                                        Text("Телевизоры пока не найдены")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white.opacity(0.82))
                                        Text("Убедитесь, что iPhone и ТВ в одной сети Wi-Fi, или нажмите «+» справа сверху, чтобы добавить Android TV / Google TV / YaOS по IP-адресу.")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.50))
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                                    .padding(.horizontal, 16)
                                    .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                } else {
                                    ForEach(remote.discoveredTVs) { device in
                                        discoveredTVRow(device)
                                    }
                                }
                            }

                            // Подсказка по подключению платформ
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Поддержка платформ")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.72))
                                platformHintRow(
                                    badge: "Салют ТВ",
                                    color: TVPlatform.sberSalute.accentColor,
                                    text: "Автопоиск по Wi-Fi (SberBox, SberPortal, Салют ТВ) + 4-значный PIN."
                                )
                                platformHintRow(
                                    badge: "Android TV",
                                    color: TVPlatform.androidTV.accentColor,
                                    text: "Протокол Remote v2 (порт 6466/6467) с 6-значным HEX-кодом на экране."
                                )
                                platformHintRow(
                                    badge: "YaOS",
                                    color: TVPlatform.yaOS.accentColor,
                                    text: "Яндекс ТВ / ТВ Станция: Remote v2 или ADB по Wi-Fi (порт 5555)."
                                )
                            }
                            .padding(14)
                            .nativeLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
            }
        }
        .preferredColorScheme(.dark)
        .modifier(TVHubSheetModifier(isPresentedAsSheet: isPresentedAsSheet))
        .sheet(isPresented: $showAddSheet) {
            TVProfileEditorSheet(existingProfile: nil) { saved in
                remote.upsertProfile(saved, makeActive: false)
                remote.switchToProfile(saved)
                if isPresentedAsSheet {
                    onClose()
                }
            }
        }
        .sheet(item: $editingProfile) { profile in
            TVProfileEditorSheet(existingProfile: profile) { saved in
                remote.upsertProfile(saved, makeActive: remote.activeProfile?.id == saved.id)
                if remote.activeProfile?.id == saved.id {
                    remote.switchToProfile(saved)
                }
            }
        }
    }

    private func savedTVRow(_ profile: SavedTVProfile) -> some View {
        let isActive = remote.activeProfile?.id == profile.id && remote.isShowingRemotePad

        return HStack(spacing: 12) {
            Button {
                Haptics.medium()
                remote.switchToProfile(profile)
                if isPresentedAsSheet {
                    onClose()
                }
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: profile.platform.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(profile.platform.accentColor)
                        .frame(width: 44, height: 44)
                        .nativeLiquidGlass(
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                            tint: profile.platform.accentColor.opacity(0.22)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(profile.name)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if isActive {
                                Text("Активен")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.white))
                            }
                        }
                        Text(profile.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.56))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    remote.switchToProfile(profile)
                    if isPresentedAsSheet { onClose() }
                } label: {
                    Label("Подключиться", systemImage: "play.fill")
                }

                Button {
                    editingProfile = profile
                } label: {
                    Label("Изменить", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    remote.deleteProfile(profile)
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .nativeLiquidGlass(in: Circle(), interactive: true)
            }
        }
        .padding(13)
        .nativeLiquidGlass(
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            tint: isActive ? profile.platform.accentColor.opacity(0.22) : nil,
            interactive: true
        )
    }

    private func discoveredTVRow(_ device: DiscoveredTVDevice) -> some View {
        Button {
            Haptics.medium()
            remote.connectDiscovered(device)
            if isPresentedAsSheet {
                onClose()
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: device.platform.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(device.platform.accentColor)
                    .frame(width: 44, height: 44)
                    .nativeLiquidGlass(
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                        tint: device.platform.accentColor.opacity(0.20)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(device.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(13)
            .nativeLiquidGlass(
                in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                interactive: true
            )
        }
        .buttonStyle(RemotePressStyle())
    }

    private func platformHintRow(badge: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(badge)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.32)))
                .frame(width: 78, alignment: .leading)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TVHubSheetModifier: ViewModifier {
    let isPresentedAsSheet: Bool

    func body(content: Content) -> some View {
        if isPresentedAsSheet {
            content
                .nativeGlassSheetContainerBackground()
                .nativePresentationSheet()
        } else {
            content
        }
    }
}

// MARK: - Редактор / добавление телевизора вручную (Android TV / Google TV / YaOS / Сбер)

struct TVProfileEditorSheet: View {
    let existingProfile: SavedTVProfile?
    let onSave: (SavedTVProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var platform: TVPlatform = .androidTV
    @State private var method: TVConnectionMethod = .androidTVRemoteV2
    @State private var host: String = ""
    @State private var remotePortText: String = "6466"
    @State private var pairingPortText: String = "6467"

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        if platform == .sberSalute {
            return true
        }
        return !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NativeNavigationContainer {
            Form {
                Section("Платформа телевизора") {
                    Picker("Платформа", selection: $platform) {
                        ForEach(TVPlatform.allCases) { p in
                            Text(p.shortBadge).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Название (например, Гостиная ТВ)", text: $name)
                }

                if platform != .sberSalute {
                    Section("Подключение по Wi-Fi") {
                        Picker("Протокол", selection: $method) {
                            ForEach(platform.supportedMethods) { m in
                                Text(m.title).tag(m)
                            }
                        }

                        TextField("IP-адрес ТВ (например, 192.168.1.55)", text: $host)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        HStack {
                            Text("Порт управления")
                            Spacer()
                            TextField("6466", text: $remotePortText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }

                        if method == .androidTVRemoteV2 {
                            HStack {
                                Text("Порт сопряжения")
                                Spacer()
                                TextField("6467", text: $pairingPortText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                            }
                        }
                    }

                    Section {
                        if method == .androidTVRemoteV2 {
                            Text("Android TV Remote v2 работает на Android TV, Google TV и новых версиях YaOS без отладки. При первом подключении на экране ТВ появится 6-символьный код (0–9, A–F).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("ADB по Wi-Fi (порт 5555) подходит для всех телевизоров с YaOS (Яндекс ТВ, ТВ Станция, Tuvio, Hartens) и Android TV. Включите «Отладка по сети / USB» на ТВ и подтвердите запрос на экране.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        Text("Телевизоры Сбер Салют (SberBox, SberPortal, Салют ТВ) находятся автоматически в сети Wi-Fi. Просто сохраните или выберите ТВ из списка найденных.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(existingProfile == nil ? "Добавить телевизор" : "Настройки ТВ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveProfile()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
        .nativePresentationSheet()
        .onAppear {
            if let existing = existingProfile {
                name = existing.name
                platform = existing.platform
                method = existing.connectionMethod
                host = existing.host
                remotePortText = existing.remotePort > 0 ? "\(existing.remotePort)" : "\(existing.connectionMethod.defaultPort)"
                pairingPortText = existing.pairingPort > 0 ? "\(existing.pairingPort)" : "\(existing.connectionMethod.defaultPairingPort)"
            }
        }
        .onChange(of: platform) { newPlatform in
            if !newPlatform.supportedMethods.contains(method) {
                method = newPlatform.defaultConnectionMethod
            }
            applyDefaultPorts(for: method)
        }
        .onChange(of: method) { newMethod in
            applyDefaultPorts(for: newMethod)
        }
    }

    private func applyDefaultPorts(for connectionMethod: TVConnectionMethod) {
        if existingProfile == nil || remotePortText.isEmpty || remotePortText == "6466" || remotePortText == "5555" || remotePortText == "0" {
            remotePortText = "\(connectionMethod.defaultPort)"
        }
        if connectionMethod == .androidTVRemoteV2 {
            if pairingPortText.isEmpty || pairingPortText == "0" {
                pairingPortText = "6467"
            }
        }
    }

    private func saveProfile() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let rPort = Int(remotePortText) ?? method.defaultPort
        let pPort = Int(pairingPortText) ?? method.defaultPairingPort

        let profile = SavedTVProfile(
            id: existingProfile?.id ?? UUID().uuidString,
            name: trimmedName,
            platform: platform,
            connectionMethod: platform == .sberSalute ? .sberCast : method,
            host: platform == .sberSalute ? "" : trimmedHost,
            remotePort: platform == .sberSalute ? 0 : rPort,
            pairingPort: method == .androidTVRemoteV2 ? pPort : 0,
            sberDeviceId: existingProfile?.sberDeviceId,
            isPaired: (existingProfile?.host == trimmedHost && existingProfile?.connectionMethod == method) ? (existingProfile?.isPaired ?? false) : false,
            lastConnectedAt: existingProfile?.lastConnectedAt
        )
        Haptics.medium()
        onSave(profile)
        dismiss()
    }
}
