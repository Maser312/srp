import SwiftUI
import AVKit
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

enum MediaHubTab: String, CaseIterable, Identifiable {
    case home
    case library
    case downloads
    case cast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Главная"
        case .library: return "Каталог"
        case .downloads: return "Офлайн"
        case .cast: return "Каст"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "play.tv.fill"
        case .library: return "rectangle.stack.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .cast: return "airplayvideo"
        }
    }
}

/// Чистый нативный медиахаб «Лифт»: локальные видео, прямые ссылки MP4/HLS, M3U-плейлисты,
/// офлайн-загрузки, встроенный AVPlayer (PiP / AirPlay) и DLNA-кастинг на ТВ в локальной сети.
struct MediaHubView: View {
    let onBackToMenu: () -> Void

    @StateObject private var store = MediaLibraryStore()
    @StateObject private var dlna = DLNACastEngine()
    @State private var selectedTab: MediaHubTab = .home

    @State private var quickURL = ""
    @State private var searchQuery = ""
    @State private var selectedCategory = "Все"

    private enum FileImportMode {
        case video
        case m3u
    }

    @State private var playingItem: MediaItem?
    @State private var showAddURLSheet = false
    @State private var showM3UImportSheet = false
    @State private var showFileImporter = false
    @State private var fileImportMode: FileImportMode = .video
    @State private var showPhotoVideoPicker = false
    @State private var pendingCastItem: MediaItem?

    var body: some View {
        VStack(spacing: 0) {
            // Верхняя панель модуля
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    onBackToMenu()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                        Text("Меню")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(LiquidGlassPanel(cornerRadius: 18))
                }
                .buttonStyle(RemotePressStyle())

                VStack(alignment: .leading, spacing: 1) {
                    Text("Лифт · Медиа")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(dlna.selectedDevice != nil ? "DLNA: \(dlna.selectedDevice!.name)" : "Плеер и кастинг")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(dlna.selectedDevice != nil ? SberPalette.brightGreen : .white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()

                AirPlayButtonView()
                    .frame(width: 36, height: 36)
                    .background(LiquidGlassCircle())

                Button {
                    Haptics.tap()
                    showAddURLSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SberPalette.lime)
                        .frame(width: 36, height: 36)
                        .background(LiquidGlassCircle())
                }
                .buttonStyle(RemotePressStyle())
                .accessibilityLabel("Добавить видео по ссылке")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            // Основное содержимое выбранной вкладки
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if let message = store.statusMessage, !message.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(SberPalette.lime)
                            Text(message)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Button {
                                store.statusMessage = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        .padding(12)
                        .background(LiquidGlassPanel(cornerRadius: 16))
                    }

                    switch selectedTab {
                    case .home:
                        homeTabContent
                    case .library:
                        libraryTabContent
                    case .downloads:
                        downloadsTabContent
                    case .cast:
                        castTabContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }

            // Нижняя стеклянная панель вкладок
            HStack(spacing: 6) {
                ForEach(MediaHubTab.allCases) { tab in
                    let active = tab == selectedTab
                    Button {
                        Haptics.tap()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTab = tab
                        }
                        if tab == .cast && dlna.devices.isEmpty && !dlna.isScanning {
                            dlna.startDiscovery()
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 16, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(active ? .white : .white.opacity(0.56))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            Group {
                                if active {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(SberPalette.accentButtonGradient)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(SberPalette.glassAccentBorder, lineWidth: 1)
                                        )
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(LiquidGlassPanel(cornerRadius: 22))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .padding(.top, 4)
        }
        .onDisappear {
            dlna.stopServer()
        }
        .fullScreenCover(item: $playingItem) { item in
            if let url = store.playableURL(for: item) {
                NativeVideoPlayerSheet(
                    item: item,
                    url: url,
                    onCastToTV: {
                        playingItem = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            pendingCastItem = item
                        }
                    },
                    onSaveProgress: { pos, dur in
                        store.updatePlaybackProgress(itemId: item.id, position: pos, duration: dur)
                    }
                )
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 14) {
                        Text("Не удалось открыть видео")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Button("Закрыть") {
                            playingItem = nil
                        }
                        .buttonStyle(SberPrimaryButtonStyle())
                    }
                }
            }
        }
        .sheet(isPresented: $showAddURLSheet) {
            AddMediaURLSheet(store: store) { created in
                playingItem = created
            }
        }
        .sheet(isPresented: $showM3UImportSheet) {
            ImportM3USheet(store: store) {
                fileImportMode = .m3u
                showFileImporter = true
            }
        }
        .sheet(isPresented: $showPhotoVideoPicker) {
            PhotoLibraryVideoPicker { tempURL, name in
                if let item = store.importLocalFile(from: tempURL, suggestedTitle: name) {
                    playingItem = item
                }
            }
        }
        .sheet(item: $pendingCastItem) { item in
            DLNACastPickerSheet(
                item: item,
                store: store,
                dlna: dlna
            )
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: fileImportMode == .video
                ? [.movie, .mpeg4Movie, .quickTimeMovie, .video]
                : [.m3uPlaylist, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                switch fileImportMode {
                case .video:
                    if let item = store.importLocalFile(from: url) {
                        playingItem = item
                    }
                case .m3u:
                    store.importM3UFile(from: url)
                }
            }
        }
    }

    // MARK: - Вкладка «Главная»

    private var homeTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Карточка быстрого запуска потока
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "link.circle.fill")
                        .font(.title3)
                        .foregroundStyle(SberPalette.brandGradient)
                    Text("Быстрый запуск видео")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                Text("Вставьте прямую ссылку на видео (MP4, MOV, HLS .m3u8) или откройте локальный файл.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))

                HStack(spacing: 8) {
                    TextField("https://…/video.mp4 или .m3u8", text: $quickURL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .font(.subheadline)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.26))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                                )
                        )

                    if !quickURL.isEmpty {
                        Button {
                            quickURL = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Haptics.medium()
                        if let item = store.addDirectURL(quickURL) {
                            quickURL = ""
                            playingItem = item
                        }
                    } label: {
                        Label("Смотреть", systemImage: "play.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(SberPrimaryButtonStyle(disabled: quickURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .disabled(quickURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        Haptics.tap()
                        if let item = store.addDirectURL(quickURL) {
                            quickURL = ""
                            pendingCastItem = item
                        }
                    } label: {
                        Label("На ТВ", systemImage: "airplayvideo")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 112)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(SberGlassButtonStyle(disabled: quickURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .disabled(quickURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .background(LiquidGlassPanel(cornerRadius: 24))

            // Быстрые источники: Файлы, Галерея, M3U-плейлист
            HStack(spacing: 10) {
                quickSourceCard(symbol: "folder.fill", title: "Файлы") {
                    fileImportMode = .video
                    showFileImporter = true
                }
                quickSourceCard(symbol: "photo.on.rectangle.angled", title: "Галерея") {
                    showPhotoVideoPicker = true
                }
                quickSourceCard(symbol: "list.bullet.rectangle.portrait.fill", title: "M3U") {
                    showM3UImportSheet = true
                }
            }

            // Продолжить просмотр
            if !store.recentItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Продолжить просмотр")
                        .font(.headline)
                        .foregroundStyle(.white)
                    ForEach(store.recentItems.prefix(4)) { item in
                        mediaRowCard(item)
                    }
                }
            }

            // Избранное
            if !store.favoriteItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Избранное")
                        .font(.headline)
                        .foregroundStyle(.white)
                    ForEach(store.favoriteItems.prefix(4)) { item in
                        mediaRowCard(item)
                    }
                }
            }

            if store.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "film.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(SberPalette.brandGradient)
                    Text("Ваша библиотека пока пуста")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Добавьте видеофайлы с iPhone, прямую ссылку на авторский поток или импортируйте свой M3U-плейлист.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(22)
                .background(LiquidGlassPanel(cornerRadius: 22))
            }
        }
    }

    private func quickSourceCard(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(SberPalette.brandGradient)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(LiquidGlassPanel(cornerRadius: 18))
        }
        .buttonStyle(RemotePressStyle())
    }

    // MARK: - Вкладка «Каталог / Библиотека»

    private var availableCategories: [String] {
        let unique = Array(Set(store.items.map(\.category))).sorted()
        return ["Все"] + unique
    }

    private var filteredLibraryItems: [MediaItem] {
        store.items.filter { item in
            let matchesCategory = selectedCategory == "Все" || item.category == selectedCategory
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesQuery = q.isEmpty
                || item.title.lowercased().contains(q)
                || item.subtitle.lowercased().contains(q)
                || item.category.lowercased().contains(q)
            return matchesCategory && matchesQuery
        }
    }

    private var libraryTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SberPalette.brightGreen)
                TextField("Поиск по библиотеке…", text: $searchQuery)
                    .font(.subheadline)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .padding(12)
            .background(LiquidGlassPanel(cornerRadius: 16))

            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    showAddURLSheet = true
                } label: {
                    Label("Ссылка", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(SberGlassButtonStyle())

                Button {
                    Haptics.tap()
                    showM3UImportSheet = true
                } label: {
                    Label("Импорт M3U", systemImage: "list.bullet")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(SberGlassButtonStyle())

                Button {
                    Haptics.tap()
                    fileImportMode = .video
                    showFileImporter = true
                } label: {
                    Label("Файл", systemImage: "folder.badge.plus")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(SberGlassButtonStyle())
            }

            if availableCategories.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableCategories, id: \.self) { cat in
                            let selected = cat == selectedCategory
                            Button {
                                Haptics.tap()
                                selectedCategory = cat
                            } label: {
                                Text(cat)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selected ? .white : .white.opacity(0.68))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(selected ? AnyShapeStyle(SberPalette.accentButtonGradient) : AnyShapeStyle(Color.white.opacity(0.08)))
                                            .overlay(
                                                Capsule().strokeBorder(selected ? SberPalette.glassAccentBorder : SberPalette.glassBorderGradient, lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if filteredLibraryItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Нет элементов в каталоге")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(LiquidGlassPanel(cornerRadius: 20))
            } else {
                ForEach(filteredLibraryItems) { item in
                    mediaRowCard(item)
                }
            }
        }
    }

    // MARK: - Вкладка «Офлайн / Загрузки»

    private var downloadsTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.downloads.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Активные загрузки")
                        .font(.headline)
                        .foregroundStyle(.white)
                    ForEach(store.downloads) { dl in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(dl.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text(dl.statusText)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(SberPalette.lime)
                                Button {
                                    store.cancelDownload(dl.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                            ProgressView(value: dl.progress)
                                .tint(SberPalette.brightGreen)
                        }
                        .padding(14)
                        .background(LiquidGlassPanel(cornerRadius: 18))
                    }
                }
            }

            HStack {
                Text("Сохранённые на iPhone")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    Haptics.tap()
                    fileImportMode = .video
                    showFileImporter = true
                } label: {
                    Label("Импорт", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SberPalette.lime)
                }
            }

            if store.offlineItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(SberPalette.brandGradient)
                    Text("Офлайн-видео пока нет")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Импортируйте файлы из «Файлов» или «Галереи», либо нажмите значок загрузки у любой MP4-ссылки в каталоге.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(LiquidGlassPanel(cornerRadius: 22))
            } else {
                ForEach(store.offlineItems) { item in
                    mediaRowCard(item, offlineMode: true)
                }
            }
        }
    }

    // MARK: - Вкладка «Каст на ТВ (DLNA + AirPlay)»

    private var castTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Панель поиска DLNA и AirPlay
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Трансляция на ТВ")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(dlna.statusText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    if dlna.isScanning {
                        ProgressView().tint(SberPalette.brightGreen)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        dlna.startDiscovery()
                    } label: {
                        Label("Найти DLNA ТВ", systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(SberPrimaryButtonStyle(disabled: dlna.isScanning))
                    .disabled(dlna.isScanning)

                    HStack(spacing: 6) {
                        AirPlayButtonView()
                            .frame(width: 24, height: 24)
                        Text("AirPlay")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(LiquidGlassPanel(cornerRadius: 16))
                }
            }
            .padding(16)
            .background(LiquidGlassPanel(cornerRadius: 22))

            // Активное управление воспроизведением на DLNA ТВ
            if let active = dlna.activeTitle, let device = dlna.selectedDevice {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "tv.fill")
                            .foregroundStyle(SberPalette.lime)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(active)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("На экране: \(device.name)")
                                .font(.caption2)
                                .foregroundStyle(SberPalette.teal)
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap()
                            Task {
                                if dlna.isPlaying { await dlna.pause() } else { await dlna.play() }
                            }
                        } label: {
                            Label(dlna.isPlaying ? "Пауза" : "Играть", systemImage: dlna.isPlaying ? "pause.fill" : "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(SberPrimaryButtonStyle())

                        Button {
                            Haptics.tap()
                            Task { await dlna.stop() }
                        } label: {
                            Label("Стоп", systemImage: "stop.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 100)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(SberGlassButtonStyle())
                    }
                }
                .padding(16)
                .background(LiquidGlassPanel(cornerRadius: 22, highlighted: false))
            }

            // Список найденных DLNA-устройств
            if !dlna.devices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Устройства DLNA в сети")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))

                    ForEach(dlna.devices) { device in
                        let selected = dlna.selectedDevice?.id == device.id
                        Button {
                            Haptics.tap()
                            dlna.selectedDevice = device
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tv")
                                    .font(.title3)
                                    .foregroundStyle(selected ? SberPalette.lime : .white.opacity(0.75))
                                    .frame(width: 40, height: 40)
                                    .background(LiquidGlassCircle(highlighted: selected))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(device.locationURL.host ?? "")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.52))
                                }
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(SberPalette.brightGreen)
                                }
                            }
                            .padding(12)
                            .background(LiquidGlassPanel(cornerRadius: 18, highlighted: false))
                        }
                        .buttonStyle(RemotePressStyle())
                    }
                }
            }

            // Быстрая отправка любого видео из библиотеки на выбранный ТВ
            if !store.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Отправить из библиотеки")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    ForEach(store.items.prefix(6)) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.isLocalFile ? "film.fill" : "play.rectangle.fill")
                                .foregroundStyle(SberPalette.brandGradient)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(item.isLocalFile ? "Локальный файл (через Wi-Fi сервер)" : item.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                Haptics.medium()
                                if let url = store.playableURL(for: item) {
                                    Task { await dlna.cast(item: item, playableURL: url) }
                                }
                            } label: {
                                Text("На ТВ")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(SberPrimaryButtonStyle(disabled: dlna.selectedDevice == nil))
                            .disabled(dlna.selectedDevice == nil)
                        }
                        .padding(12)
                        .background(LiquidGlassPanel(cornerRadius: 18))
                    }
                }
            }
        }
    }

    // MARK: - Карточка видео

    private func mediaRowCard(_ item: MediaItem, offlineMode: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    playingItem = item
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(SberPalette.accentButtonGradient)
                                .opacity(0.28)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(SberPalette.glassAccentBorder, lineWidth: 1)
                                        .opacity(0.5)
                                )
                            Image(systemName: item.isLocalFile ? "film.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(SberPalette.lime)
                        }
                        .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                Text(item.category)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(SberPalette.teal)
                                if let size = store.fileSizeString(for: item) {
                                    Text("· \(size)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.5))
                                } else if !item.subtitle.isEmpty {
                                    Text("· \(item.subtitle)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer(minLength: 4)
                    }
                }
                .buttonStyle(.plain)

                // Действия: Каст, Офлайн, Избранное, Удалить
                HStack(spacing: 6) {
                    Button {
                        Haptics.tap()
                        pendingCastItem = item
                    } label: {
                        Image(systemName: "airplayvideo")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SberPalette.teal)
                            .frame(width: 32, height: 32)
                            .background(LiquidGlassCircle())
                    }
                    .buttonStyle(RemotePressStyle())

                    if !item.isLocalFile {
                        Button {
                            Haptics.tap()
                            store.startDownload(for: item)
                        } label: {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SberPalette.brightGreen)
                                .frame(width: 32, height: 32)
                                .background(LiquidGlassCircle())
                        }
                        .buttonStyle(RemotePressStyle())
                    }

                    Button {
                        Haptics.tap()
                        store.toggleFavorite(item)
                    } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(item.isFavorite ? SberPalette.lime : .white.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .background(LiquidGlassCircle())
                    }
                    .buttonStyle(RemotePressStyle())

                    Button {
                        Haptics.tap()
                        if offlineMode {
                            store.removeOfflineCopy(for: item)
                        } else {
                            store.deleteItem(item)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SberPalette.coral.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .background(LiquidGlassCircle())
                    }
                    .buttonStyle(RemotePressStyle())
                }
            }

            if item.progress > 0.02 {
                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(SberPalette.brandGradient)
                            .frame(width: barGeo.size.width * CGFloat(item.progress))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(12)
        .background(LiquidGlassPanel(cornerRadius: 18))
    }
}

// MARK: - Нативный полноэкранный видеоплеер (AVPlayerViewController + PiP + AirPlay + Скорость)

struct NativeVideoPlayerSheet: View {
    let item: MediaItem
    let url: URL
    let onCastToTV: () -> Void
    let onSaveProgress: (Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var speed: Float = 1.0
    @State private var timeObserver: Any?

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                AVPlayerControllerRepresentable(player: player)
                    .ignoresSafeArea()
            }

            // Компактная верхняя стеклянная полоска с названием, скоростью, DLNA, AirPlay и закрытием
            VStack {
                HStack(spacing: 8) {
                    Button {
                        saveCurrentProgress()
                        player?.pause()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(LiquidGlassCircle())
                    }

                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        cycleSpeed()
                    } label: {
                        Text(speedLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SberPalette.lime)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(LiquidGlassPanel(cornerRadius: 16))
                    }

                    Button {
                        saveCurrentProgress()
                        player?.pause()
                        onCastToTV()
                    } label: {
                        Image(systemName: "tv")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SberPalette.teal)
                            .frame(width: 36, height: 36)
                            .background(LiquidGlassCircle())
                    }
                    .accessibilityLabel("Отправить на DLNA ТВ")

                    AirPlayButtonView()
                        .frame(width: 36, height: 36)
                        .background(LiquidGlassCircle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            configureAudioSession()
            let newPlayer = AVPlayer(url: url)
            newPlayer.allowsExternalPlayback = true
            if item.lastPosition > 3, (item.duration == 0 || item.lastPosition < item.duration - 10) {
                let target = CMTime(seconds: item.lastPosition, preferredTimescale: 600)
                newPlayer.seek(to: target)
            }
            newPlayer.play()
            let interval = CMTime(seconds: 2.0, preferredTimescale: 600)
            timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                let dur = newPlayer.currentItem?.duration.seconds ?? 0
                if time.seconds.isFinite {
                    onSaveProgress(time.seconds, dur.isFinite ? dur : 0)
                }
            }
            player = newPlayer
        }
        .onDisappear {
            saveCurrentProgress()
            if let obs = timeObserver {
                player?.removeTimeObserver(obs)
                timeObserver = nil
            }
            player?.pause()
            player = nil
        }
    }

    private var speedLabel: String {
        speed == 1.0 ? "1×" : String(format: "%.2g×", speed)
    }

    private func cycleSpeed() {
        let idx = speeds.firstIndex(of: speed) ?? 1
        let next = speeds[(idx + 1) % speeds.count]
        speed = next
        if player?.rate != 0 {
            player?.rate = next
        }
    }

    private func saveCurrentProgress() {
        guard let player else { return }
        let pos = player.currentTime().seconds
        let dur = player.currentItem?.duration.seconds ?? 0
        if pos.isFinite {
            onSaveProgress(pos, dur.isFinite ? dur : 0)
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }
}

private struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.showsPlaybackControls = true
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

/// Нативная кнопка выбора AirPlay-устройства.
struct AirPlayButtonView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.activeTintColor = UIColor(red: 0.184, green: 0.839, blue: 0.361, alpha: 1.0)
        picker.tintColor = UIColor.white
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}

// MARK: - Вспомогательные листы (добавление ссылки, M3U, выбор DLNA ТВ, галерея видео)

private struct AddMediaURLSheet: View {
    @ObservedObject var store: MediaLibraryStore
    let onPlayCreated: (MediaItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var urlText = ""
    @State private var category = "Видео"

    var body: some View {
        ZStack {
            SberLiquidBackdrop()

            VStack(spacing: 16) {
                Capsule()
                    .fill(.white.opacity(0.24))
                    .frame(width: 40, height: 4)
                    .padding(.top, 10)

                Text("Добавить видео по ссылке")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                TextField("Название (необязательно)", text: $title)
                    .padding(14)
                    .background(LiquidGlassPanel(cornerRadius: 16))

                TextField("https://…/video.mp4 или .m3u8", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .padding(14)
                    .background(LiquidGlassPanel(cornerRadius: 16))

                TextField("Категория (например: Авторские)", text: $category)
                    .padding(14)
                    .background(LiquidGlassPanel(cornerRadius: 16))

                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        if store.addDirectURL(urlText, title: title, category: category.isEmpty ? "Видео" : category) != nil {
                            dismiss()
                        }
                    } label: {
                        Text("Сохранить")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(SberGlassButtonStyle(disabled: urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        Haptics.medium()
                        if let item = store.addDirectURL(urlText, title: title, category: category.isEmpty ? "Видео" : category) {
                            dismiss()
                            onPlayCreated(item)
                        }
                    } label: {
                        Text("Смотреть")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(SberPrimaryButtonStyle(disabled: urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
    }
}

private struct ImportM3USheet: View {
    @ObservedObject var store: MediaLibraryStore
    let onPickFile: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var playlistURL = ""
    @State private var loading = false

    var body: some View {
        ZStack {
            SberLiquidBackdrop()

            VStack(spacing: 16) {
                Capsule()
                    .fill(.white.opacity(0.24))
                    .frame(width: 40, height: 4)
                    .padding(.top, 10)

                Text("Импорт M3U-плейлиста")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text("Загрузите стандартный плейлист .m3u / .m3u8 по ссылке или выберите файл с iPhone.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)

                TextField("https://…/playlist.m3u", text: $playlistURL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .padding(14)
                    .background(LiquidGlassPanel(cornerRadius: 16))

                Button {
                    Haptics.medium()
                    loading = true
                    Task {
                        await store.importM3UPlaylist(from: playlistURL)
                        loading = false
                        dismiss()
                    }
                } label: {
                    if loading {
                        ProgressView().tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Label("Загрузить по ссылке", systemImage: "arrow.down.doc.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .buttonStyle(SberPrimaryButtonStyle(disabled: playlistURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading))
                .disabled(playlistURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)

                Button {
                    Haptics.tap()
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onPickFile()
                    }
                } label: {
                    Label("Выбрать .m3u файл на iPhone", systemImage: "folder.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(SberGlassButtonStyle())

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
    }
}

private struct DLNACastPickerSheet: View {
    let item: MediaItem
    @ObservedObject var store: MediaLibraryStore
    @ObservedObject var dlna: DLNACastEngine

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            SberLiquidBackdrop()

            VStack(spacing: 16) {
                Capsule()
                    .fill(.white.opacity(0.24))
                    .frame(width: 40, height: 4)
                    .padding(.top, 10)

                Text("Отправить на ТВ")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SberPalette.teal)
                    .lineLimit(1)

                HStack {
                    Text(dlna.statusText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    if dlna.isScanning {
                        ProgressView().tint(SberPalette.brightGreen)
                    } else {
                        Button("Обновить") {
                            dlna.startDiscovery()
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SberPalette.lime)
                    }
                }
                .padding(12)
                .background(LiquidGlassPanel(cornerRadius: 16))

                if dlna.devices.isEmpty && !dlna.isScanning {
                    Text("Убедитесь, что телевизор в той же Wi-Fi сети и поддерживает DLNA, или используйте AirPlay.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 10)
                } else {
                    ForEach(dlna.devices) { device in
                        Button {
                            Haptics.medium()
                            dlna.selectedDevice = device
                            if let url = store.playableURL(for: item) {
                                Task {
                                    await dlna.cast(item: item, playableURL: url)
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tv.fill")
                                    .foregroundStyle(SberPalette.lime)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(device.locationURL.host ?? "")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(SberPalette.brightGreen)
                            }
                            .padding(14)
                            .background(LiquidGlassPanel(cornerRadius: 18))
                        }
                        .buttonStyle(RemotePressStyle())
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if dlna.devices.isEmpty && !dlna.isScanning {
                dlna.startDiscovery()
            }
        }
    }
}

private struct PhotoLibraryVideoPicker: UIViewControllerRepresentable {
    let onPicked: (URL, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) { }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (URL, String) -> Void

        init(onPicked: @escaping (URL, String) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { return }
            let suggestedName = provider.suggestedName ?? "Видео из галереи"

            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url else { return }
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)")
                do {
                    try FileManager.default.copyItem(at: url, to: tmp)
                    DispatchQueue.main.async {
                        self.onPicked(tmp, suggestedName)
                    }
                } catch { }
            }
        }
    }
}
