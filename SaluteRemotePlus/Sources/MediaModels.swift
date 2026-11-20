import Foundation
import SwiftUI

/// Элемент пользовательской видеотеки (прямая ссылка MP4/HLS, пункт M3U-плейлиста или локальный файл).
struct MediaItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var subtitle: String
    var streamURLString: String
    var posterURLString: String?
    var localFileName: String?
    var category: String
    var isFavorite: Bool
    var lastPosition: Double
    var duration: Double
    var addedAt: Date
    var lastPlayedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String = "",
        streamURLString: String,
        posterURLString: String? = nil,
        localFileName: String? = nil,
        category: String = "Видео",
        isFavorite: Bool = false,
        lastPosition: Double = 0,
        duration: Double = 0,
        addedAt: Date = Date(),
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.streamURLString = streamURLString
        self.posterURLString = posterURLString
        self.localFileName = localFileName
        self.category = category
        self.isFavorite = isFavorite
        self.lastPosition = lastPosition
        self.duration = duration
        self.addedAt = addedAt
        self.lastPlayedAt = lastPlayedAt
    }

    var isLocalFile: Bool {
        localFileName != nil
    }

    var progress: Double {
        guard duration > 1, lastPosition > 0 else { return 0 }
        return min(max(lastPosition / duration, 0), 1)
    }
}

struct ActiveDownload: Identifiable {
    let id: UUID
    let title: String
    var progress: Double
    var statusText: String
}

/// Локальное хранилище пользовательских видео, плейлистов, истории просмотра и офлайн-загрузок.
@MainActor
final class MediaLibraryStore: NSObject, ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var downloads: [ActiveDownload] = []
    @Published var statusMessage: String?

    private let storageFileName = "media_library_v1.json"
    private let mediaDirName = "OfflineMedia"
    private var downloadTasks: [UUID: URLSessionDownloadTask] = [:]
    private var taskItemMap: [Int: (downloadId: UUID, itemId: UUID?, title: String, sourceURL: String)] = [:]
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    override init() {
        super.init()
        ensureMediaDirectory()
        load()
    }

    var mediaDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(mediaDirName, isDirectory: true)
    }

    private var libraryFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(storageFileName)
    }

    var recentItems: [MediaItem] {
        items
            .filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    var favoriteItems: [MediaItem] {
        items.filter { $0.isFavorite }
    }

    var offlineItems: [MediaItem] {
        items.filter { item in
            guard let name = item.localFileName else { return false }
            return FileManager.default.fileExists(atPath: mediaDirectoryURL.appendingPathComponent(name).path)
        }
    }

    func playableURL(for item: MediaItem) -> URL? {
        if let local = item.localFileName {
            let fileURL = mediaDirectoryURL.appendingPathComponent(local)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }
        return URL(string: item.streamURLString)
    }

    func fileSizeString(for item: MediaItem) -> String? {
        guard let local = item.localFileName else { return nil }
        let fileURL = mediaDirectoryURL.appendingPathComponent(local)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let bytes = (attrs[.size] as? NSNumber)?.int64Value else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func addDirectURL(_ rawURL: String, title: String? = nil, category: String = "Ссылки") -> MediaItem? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            statusMessage = "Введите корректную ссылку http:// или https://"
            return nil
        }

        if let existing = items.first(where: { $0.streamURLString == trimmed }) {
            return existing
        }

        let cleanTitle: String
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let candidate = url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? ""
            cleanTitle = candidate.isEmpty || candidate == "/" ? (url.host ?? "Видеопоток") : candidate
        }

        let item = MediaItem(
            title: cleanTitle,
            subtitle: url.host ?? "",
            streamURLString: trimmed,
            category: category
        )
        items.insert(item, at: 0)
        save()
        statusMessage = nil
        return item
    }

    func importLocalFile(from sourceURL: URL, suggestedTitle: String? = nil) -> MediaItem? {
        let needsScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if needsScope { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = mediaDirectoryURL.appendingPathComponent(fileName)

        do {
            ensureMediaDirectory()
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            statusMessage = "Не удалось импортировать файл: \(error.localizedDescription)"
            return nil
        }

        let title = suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? suggestedTitle!
            : sourceURL.deletingPathExtension().lastPathComponent

        let item = MediaItem(
            title: title.isEmpty ? "Локальное видео" : title,
            subtitle: "На iPhone · \(ext.uppercased())",
            streamURLString: destination.absoluteString,
            localFileName: fileName,
            category: "Файлы"
        )
        items.insert(item, at: 0)
        save()
        statusMessage = "Файл добавлен в библиотеку"
        return item
    }

    /// Импорт стандартного M3U / M3U8-плейлиста (по URL или из текста).
    func importM3UPlaylist(from rawURL: String) async {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            statusMessage = "Некорректная ссылка на плейлист M3U"
            return
        }

        statusMessage = "Загружаем плейлист…"
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else {
                statusMessage = "Не удалось прочитать текст плейлиста"
                return
            }
            let added = parseAndAddM3U(text, defaultCategory: url.deletingPathExtension().lastPathComponent)
            statusMessage = added > 0 ? "Добавлено записей: \(added)" : "Плейлист не содержит новых потоков"
        } catch {
            statusMessage = "Ошибка загрузки плейлиста: \(error.localizedDescription)"
        }
    }

    func importM3UFile(from fileURL: URL) {
        let needsScope = fileURL.startAccessingSecurityScopedResource()
        defer { if needsScope { fileURL.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else {
            statusMessage = "Не удалось прочитать M3U-файл"
            return
        }
        let added = parseAndAddM3U(text, defaultCategory: fileURL.deletingPathExtension().lastPathComponent)
        statusMessage = added > 0 ? "Импортировано записей: \(added)" : "Новых потоков не найдено"
    }

    private func parseAndAddM3U(_ content: String, defaultCategory: String) -> Int {
        let lines = content.components(separatedBy: .newlines)
        var pendingTitle: String?
        var pendingPoster: String?
        var pendingGroup: String?
        var addedCount = 0

        let existingURLs = Set(items.map(\.streamURLString))
        var seen = existingURLs

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTINF:") {
                if let commaIdx = line.lastIndex(of: ",") {
                    let afterComma = String(line[line.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
                    if !afterComma.isEmpty { pendingTitle = afterComma }
                }
                pendingPoster = extractM3UAttribute("tvg-logo", from: line)
                pendingGroup = extractM3UAttribute("group-title", from: line)
            } else if !line.hasPrefix("#") {
                guard let url = URL(string: line),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https",
                      !seen.contains(line) else {
                    pendingTitle = nil
                    pendingPoster = nil
                    pendingGroup = nil
                    continue
                }
                seen.insert(line)
                let fallbackTitle = url.deletingPathExtension().lastPathComponent
                let item = MediaItem(
                    title: pendingTitle ?? (fallbackTitle.isEmpty ? "Видеопоток" : fallbackTitle),
                    subtitle: url.host ?? "",
                    streamURLString: line,
                    posterURLString: pendingPoster,
                    category: pendingGroup ?? (defaultCategory.isEmpty ? "Плейлист" : defaultCategory)
                )
                items.append(item)
                addedCount += 1
                pendingTitle = nil
                pendingPoster = nil
                pendingGroup = nil
            }
        }

        if addedCount > 0 { save() }
        return addedCount
    }

    private func extractM3UAttribute(_ name: String, from line: String) -> String? {
        let marker = "\(name)=\""
        guard let startRange = line.range(of: marker) else { return nil }
        let rest = line[startRange.upperBound...]
        guard let endQuote = rest.firstIndex(of: "\"") else { return nil }
        let value = String(rest[..<endQuote]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    func toggleFavorite(_ item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isFavorite.toggle()
        save()
    }

    func updatePlaybackProgress(itemId: UUID, position: Double, duration: Double) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[idx].lastPosition = max(0, position)
        if duration.isFinite && duration > 0 {
            items[idx].duration = duration
        }
        items[idx].lastPlayedAt = Date()
        save()
    }

    func deleteItem(_ item: MediaItem) {
        if let local = item.localFileName {
            let fileURL = mediaDirectoryURL.appendingPathComponent(local)
            try? FileManager.default.removeItem(at: fileURL)
        }
        items.removeAll { $0.id == item.id }
        save()
    }

    func removeOfflineCopy(for item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }),
              let local = items[idx].localFileName else { return }
        let fileURL = mediaDirectoryURL.appendingPathComponent(local)
        try? FileManager.default.removeItem(at: fileURL)

        if items[idx].streamURLString.hasPrefix("file://") {
            items.remove(at: idx)
        } else {
            items[idx].localFileName = nil
        }
        save()
    }

    // MARK: - Офлайн-загрузка прямого видеофайла (MP4/MOV)

    func startDownload(for item: MediaItem) {
        guard let url = URL(string: item.streamURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            statusMessage = "Для загрузки нужна прямая http/https-ссылка на файл"
            return
        }
        if url.pathExtension.lowercased() == "m3u8" {
            statusMessage = "Потоки HLS (.m3u8) воспроизводятся онлайн; офлайн-загрузка работает для MP4/MOV"
            return
        }

        let downloadId = UUID()
        let task = downloadSession.downloadTask(with: url)
        downloads.append(ActiveDownload(id: downloadId, title: item.title, progress: 0, statusText: "Загрузка…"))
        downloadTasks[downloadId] = task
        taskItemMap[task.taskIdentifier] = (downloadId, item.id, item.title, item.streamURLString)
        task.resume()
        statusMessage = "Загрузка «\(item.title)» начата"
    }

    func cancelDownload(_ id: UUID) {
        downloadTasks[id]?.cancel()
        downloadTasks.removeValue(forKey: id)
        downloads.removeAll { $0.id == id }
    }

    // MARK: - Persistence

    private func ensureMediaDirectory() {
        try? FileManager.default.createDirectory(at: mediaDirectoryURL, withIntermediateDirectories: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: libraryFileURL),
              let decoded = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: libraryFileURL, options: .atomic)
    }
}

extension MediaLibraryStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskId = downloadTask.taskIdentifier
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0

        Task { @MainActor [weak self] in
            guard let self, let meta = self.taskItemMap[taskId],
                  let idx = self.downloads.firstIndex(where: { $0.id == meta.downloadId }) else { return }
            self.downloads[idx].progress = min(max(progress, 0), 1)
            let pct = Int(self.downloads[idx].progress * 100)
            self.downloads[idx].statusText = totalBytesExpectedToWrite > 0 ? "\(pct)%" : "Загрузка…"
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskId = downloadTask.taskIdentifier
        let ext = downloadTask.originalRequest?.url?.pathExtension
        let safeExt = (ext?.isEmpty == false) ? ext! : "mp4"
        let fileName = "\(UUID().uuidString).\(safeExt)"

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("OfflineMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(fileName)

        let movedOK: Bool
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            movedOK = true
        } catch {
            movedOK = false
        }

        Task { @MainActor [weak self] in
            guard let self, let meta = self.taskItemMap.removeValue(forKey: taskId) else { return }
            self.downloadTasks.removeValue(forKey: meta.downloadId)
            self.downloads.removeAll { $0.id == meta.downloadId }

            guard movedOK else {
                self.statusMessage = "Не удалось сохранить загруженный файл"
                return
            }

            if let itemId = meta.itemId,
               let idx = self.items.firstIndex(where: { $0.id == itemId }) {
                self.items[idx].localFileName = fileName
            } else {
                let item = MediaItem(
                    title: meta.title,
                    subtitle: "Сохранено офлайн",
                    streamURLString: meta.sourceURL,
                    localFileName: fileName,
                    category: "Загрузки"
                )
                self.items.insert(item, at: 0)
            }
            self.save()
            self.statusMessage = "Видео «\(meta.title)» сохранено офлайн"
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let taskId = task.taskIdentifier
        let nsError = error as NSError
        Task { @MainActor [weak self] in
            guard let self, let meta = self.taskItemMap.removeValue(forKey: taskId) else { return }
            self.downloadTasks.removeValue(forKey: meta.downloadId)
            self.downloads.removeAll { $0.id == meta.downloadId }
            if nsError.code != NSURLErrorCancelled {
                self.statusMessage = "Ошибка загрузки: \(error.localizedDescription)"
            }
        }
    }
}
