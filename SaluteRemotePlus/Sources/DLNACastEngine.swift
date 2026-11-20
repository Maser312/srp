import Foundation
import Network
import Darwin

/// Найденный в локальной Wi-Fi сети DLNA / UPnP MediaRenderer (телевизор, приставка, Kodi и т. д.).
struct DLNADevice: Identifiable, Equatable {
    let id: String
    let name: String
    let locationURL: URL
    let controlURL: URL
    let serviceType: String
}

/// Минималистичный локальный HTTP-сервер на `Network.framework` с поддержкой `Range` (HTTP 206),
/// чтобы транслировать локальные видеофайлы с iPhone на ТВ по DLNA в домашней Wi-Fi сети.
final class LocalMediaHTTPServer {
    private let queue = DispatchQueue(label: "SaluteRemotePlus.LocalMediaHTTPServer")
    private var listener: NWListener?
    private var servedFileURL: URL?
    private var token: String = UUID().uuidString
    private var port: UInt16 = 0

    func serve(fileURL: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async {
                self.servedFileURL = fileURL
                self.token = UUID().uuidString.replacingOccurrences(of: "-", with: "")

                if let listener = self.listener, case .ready = listener.state, self.port > 0,
                   let ip = Self.wifiIPv4Address() {
                    let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension
                    let url = URL(string: "http://\(ip):\(self.port)/\(self.token).\(ext)")
                    continuation.resume(returning: url)
                    return
                }

                self.listener?.cancel()
                self.listener = nil

                guard let newListener = try? NWListener(using: .tcp, on: .any) else {
                    continuation.resume(returning: nil)
                    return
                }
                self.listener = newListener
                var finished = false

                newListener.newConnectionHandler = { [weak self] conn in
                    self?.handleConnection(conn)
                }

                newListener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.port = newListener.port?.rawValue ?? 0
                        guard !finished else { return }
                        finished = true
                        if self.port > 0, let ip = Self.wifiIPv4Address() {
                            let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension
                            let url = URL(string: "http://\(ip):\(self.port)/\(self.token).\(ext)")
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    case .failed, .cancelled:
                        guard !finished else { return }
                        finished = true
                        continuation.resume(returning: nil)
                    default:
                        break
                    }
                }
                newListener.start(queue: self.queue)
            }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            self.servedFileURL = nil
            self.port = 0
        }
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self, error == nil, let data, let request = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            self.respond(to: request, on: conn)
        }
    }

    private func respond(to request: String, on conn: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { conn.cancel(); return }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { conn.cancel(); return }
        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        guard let fileURL = servedFileURL,
              path.contains(token),
              let handle = try? FileHandle(forReadingFrom: fileURL),
              let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = (attrs[.size] as? NSNumber)?.uint64Value else {
            let resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
            return
        }

        let mime = Self.mimeType(for: fileURL.pathExtension)
        var start: UInt64 = 0
        var end: UInt64 = fileSize > 0 ? fileSize - 1 : 0
        var isPartial = false

        if let rangeLine = lines.first(where: { $0.lowercased().hasPrefix("range:") }),
           let bytesRange = rangeLine.range(of: "bytes=") {
            let spec = rangeLine[bytesRange.upperBound...].trimmingCharacters(in: .whitespaces)
            let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
            if let s = UInt64(bounds.first ?? "") {
                start = min(s, end)
                isPartial = true
                if bounds.count > 1, let e = UInt64(bounds[1]) {
                    end = min(e, fileSize - 1)
                }
            }
        }

        let contentLength = fileSize == 0 ? 0 : (end - start + 1)
        var header = isPartial ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(mime)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Content-Length: \(contentLength)\r\n"
        if isPartial {
            header += "Content-Range: bytes \(start)-\(end)/\(fileSize)\r\n"
        }
        header += "Connection: close\r\n\r\n"

        if method == "HEAD" {
            try? handle.close()
            conn.send(content: Data(header.utf8), completion: .contentProcessed { _ in conn.cancel() })
            return
        }

        conn.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] err in
            guard let self, err == nil else {
                try? handle.close()
                conn.cancel()
                return
            }
            do {
                try handle.seek(toOffset: start)
            } catch {
                try? handle.close()
                conn.cancel()
                return
            }
            self.streamChunks(handle: handle, remaining: contentLength, on: conn)
        })
    }

    private func streamChunks(handle: FileHandle, remaining: UInt64, on conn: NWConnection) {
        guard remaining > 0 else {
            try? handle.close()
            conn.cancel()
            return
        }
        let chunkSize = Int(min(remaining, 65_536))
        let chunk: Data
        do {
            chunk = try handle.read(upToCount: chunkSize) ?? Data()
        } catch {
            try? handle.close()
            conn.cancel()
            return
        }
        guard !chunk.isEmpty else {
            try? handle.close()
            conn.cancel()
            return
        }
        let nextRemaining = remaining - UInt64(chunk.count)
        conn.send(content: chunk, completion: .contentProcessed { [weak self] err in
            guard let self, err == nil else {
                try? handle.close()
                conn.cancel()
                return
            }
            self.streamChunks(handle: handle, remaining: nextRemaining, on: conn)
        })
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "ts": return "video/mp2t"
        case "m3u8": return "application/vnd.apple.mpegurl"
        default: return "application/octet-stream"
        }
    }

    private static func wifiIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var fallback: String?
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && isRunning && !isLoopback,
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostBuffer)
                    let name = String(cString: current.pointee.ifa_name)
                    if name == "en0" { return ip }
                    if fallback == nil { fallback = ip }
                }
            }
            ptr = current.pointee.ifa_next
        }
        return fallback
    }
}

/// Движок обнаружения и управления DLNA / UPnP телевизорами и медиаплеерами в локальной сети.
@MainActor
final class DLNACastEngine: ObservableObject {
    @Published private(set) var devices: [DLNADevice] = []
    @Published private(set) var isScanning = false
    @Published var selectedDevice: DLNADevice?
    @Published private(set) var statusText = "Нажмите «Найти ТВ» для поиска DLNA-устройств"
    @Published private(set) var activeTitle: String?
    @Published private(set) var isPlaying = false

    private let httpServer = LocalMediaHTTPServer()
    private var scanTask: Task<Void, Never>?

    func startDiscovery() {
        scanTask?.cancel()
        isScanning = true
        statusText = "Ищем DLNA-устройства в Wi-Fi сети…"

        scanTask = Task { [weak self] in
            let locations = await Self.discoverSSDPLocations(timeoutSeconds: 2.8)
            guard !Task.isCancelled else { return }

            var found: [DLNADevice] = []
            for loc in locations {
                if let device = await Self.fetchDeviceDescription(location: loc) {
                    if !found.contains(where: { $0.id == device.id }) {
                        found.append(device)
                    }
                }
            }

            guard let self, !Task.isCancelled else { return }
            self.devices = found
            self.isScanning = false
            if let current = self.selectedDevice, !found.contains(current) {
                self.selectedDevice = found.first
            } else if self.selectedDevice == nil {
                self.selectedDevice = found.first
            }
            self.statusText = found.isEmpty
                ? "DLNA-устройства не найдены. Проверьте Wi-Fi или используйте AirPlay."
                : "Найдено устройств: \(found.count)"
        }
    }

    func cast(item: MediaItem, playableURL: URL) async {
        guard let device = selectedDevice ?? devices.first else {
            statusText = "Сначала выберите DLNA-телевизор"
            return
        }

        let targetURL: URL
        if playableURL.isFileURL {
            statusText = "Запускаем локальную передачу файла…"
            guard let served = await httpServer.serve(fileURL: playableURL) else {
                statusText = "Не удалось открыть локальный сервер на Wi-Fi"
                return
            }
            targetURL = served
        } else {
            targetURL = playableURL
        }

        statusText = "Отправляем «\(item.title)» на \(device.name)…"
        let uriBody = """
        <u:SetAVTransportURI xmlns:u="\(device.serviceType)">
            <InstanceID>0</InstanceID>
            <CurrentURI>\(Self.xmlEscape(targetURL.absoluteString))</CurrentURI>
            <CurrentURIMetaData></CurrentURIMetaData>
        </u:SetAVTransportURI>
        """
        let setOK = await sendSOAP(device: device, action: "SetAVTransportURI", body: uriBody)
        guard setOK else {
            statusText = "ТВ отклонил ссылку (проверьте формат видео)"
            return
        }

        let playBody = """
        <u:Play xmlns:u="\(device.serviceType)">
            <InstanceID>0</InstanceID>
            <Speed>1</Speed>
        </u:Play>
        """
        let playOK = await sendSOAP(device: device, action: "Play", body: playBody)
        if playOK {
            activeTitle = item.title
            isPlaying = true
            statusText = "Воспроизводится на \(device.name)"
        } else {
            statusText = "Ссылка отправлена, но ТВ не запустил воспроизведение"
        }
    }

    func play() async {
        guard let device = selectedDevice else { return }
        let body = """
        <u:Play xmlns:u="\(device.serviceType)">
            <InstanceID>0</InstanceID>
            <Speed>1</Speed>
        </u:Play>
        """
        if await sendSOAP(device: device, action: "Play", body: body) {
            isPlaying = true
            statusText = "Воспроизведение на \(device.name)"
        }
    }

    func pause() async {
        guard let device = selectedDevice else { return }
        let body = """
        <u:Pause xmlns:u="\(device.serviceType)">
            <InstanceID>0</InstanceID>
        </u:Pause>
        """
        if await sendSOAP(device: device, action: "Pause", body: body) {
            isPlaying = false
            statusText = "Пауза на \(device.name)"
        }
    }

    func stop() async {
        guard let device = selectedDevice else { return }
        let body = """
        <u:Stop xmlns:u="\(device.serviceType)">
            <InstanceID>0</InstanceID>
        </u:Stop>
        """
        _ = await sendSOAP(device: device, action: "Stop", body: body)
        isPlaying = false
        activeTitle = nil
        httpServer.stop()
        statusText = "Остановлено"
    }

    func stopServer() {
        scanTask?.cancel()
        httpServer.stop()
    }

    // MARK: - SOAP & SSDP

    private func sendSOAP(device: DLNADevice, action: String, body: String) async -> Bool {
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                \(body)
            </s:Body>
        </s:Envelope>
        """
        var req = URLRequest(url: device.controlURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(device.serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = Data(envelope.utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                return (200...299).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    private static func discoverSSDPLocations(timeoutSeconds: Double) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard fd >= 0 else {
                    continuation.resume(returning: [])
                    return
                }
                defer { close(fd) }

                var reuse: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

                var tv = timeval(tv_sec: 0, tv_usec: 350_000)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                var dest = sockaddr_in()
                dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                dest.sin_family = sa_family_t(AF_INET)
                dest.sin_port = in_port_t(1900).bigEndian
                inet_pton(AF_INET, "239.255.255.250", &dest.sin_addr)

                let searchTargets = [
                    "urn:schemas-upnp-org:service:AVTransport:1",
                    "urn:schemas-upnp-org:device:MediaRenderer:1"
                ]

                for st in searchTargets {
                    let payload = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(st)\r\n\r\n"
                    let bytes = Array(payload.utf8)
                    withUnsafePointer(to: &dest) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            _ = sendto(fd, bytes, bytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }

                var locations = Set<String>()
                let deadline = Date().addingTimeInterval(timeoutSeconds)
                var buffer = [UInt8](repeating: 0, count: 4096)

                while Date() < deadline {
                    let received = recv(fd, &buffer, buffer.count, 0)
                    if received <= 0 { continue }
                    if let text = String(bytes: buffer[0..<received], encoding: .utf8) {
                        for line in text.components(separatedBy: .newlines) {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.lowercased().hasPrefix("location:") {
                                let raw = trimmed.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                                if !raw.isEmpty { locations.insert(raw) }
                            }
                        }
                    }
                }

                let urls = locations.compactMap { URL(string: $0) }
                continuation.resume(returning: urls)
            }
        }
    }

    private static func fetchDeviceDescription(location: URL) async -> DLNADevice? {
        var req = URLRequest(url: location)
        req.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let xml = String(data: data, encoding: .utf8) else { return nil }

        let friendlyName = extractTag("friendlyName", from: xml) ?? location.host ?? "DLNA ТВ"
        let udn = extractTag("UDN", from: xml) ?? location.absoluteString

        // Ищем сервис AVTransport в XML описании устройства
        let serviceBlocks = xml.components(separatedBy: "<service>")
        for block in serviceBlocks.dropFirst() {
            guard let serviceType = extractTag("serviceType", from: block),
                  serviceType.contains("AVTransport"),
                  let controlPath = extractTag("controlURL", from: block),
                  let controlURL = URL(string: controlPath, relativeTo: location)?.absoluteURL else {
                continue
            }
            return DLNADevice(
                id: udn,
                name: friendlyName,
                locationURL: location,
                controlURL: controlURL,
                serviceType: serviceType
            )
        }
        return nil
    }

    private static func extractTag(_ tag: String, from xml: String) -> String? {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex) else {
            return nil
        }
        let value = String(xml[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
