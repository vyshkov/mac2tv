import Foundation
import Darwin

public final class LocalStreamingServer: @unchecked Sendable {
    public static let shared = LocalStreamingServer()

    private var serverSocket: Int32 = -1
    private var isRunning: Bool = false
    private let queue = DispatchQueue(label: "com.mkvairplay.httpServer", attributes: .concurrent)
    private var activeConnections: [Int32] = []
    private let connectionLock = NSLock()

    public private(set) var currentURL: URL?
    public private(set) var activeFilePath: String?
    public private(set) var activeSubtitlePath: String?
    public private(set) var activePort: UInt16 = 0

    public private(set) var currentSubtitleURL: URL?

    public func subtitleURL(forTrack track: SubtitleTrack, version: String) -> URL? {
        guard !track.isOff, activeSubtitlePath != nil, let localIP = NetworkHelper.getLocalIPAddress(), activePort > 0 else {
            self.currentSubtitleURL = nil
            return nil
        }
        let subURL = URL(string: "http://\(localIP):\(activePort)/stream_\(version).srt")
        self.currentSubtitleURL = subURL
        return subURL
    }

    public func streamURL(version: String) -> URL {
        guard let localIP = NetworkHelper.getLocalIPAddress(), activePort > 0, let path = activeFilePath else {
            return currentURL ?? URL(string: "http://127.0.0.1:8089/stream.mkv")!
        }
        let fileExt = URL(fileURLWithPath: path).pathExtension
        let ext = fileExt.isEmpty ? "mkv" : fileExt
        let safeName = "stream_\(version).\(ext)"
        let generatedURL = URL(string: "http://\(localIP):\(activePort)/\(safeName)")!
        self.currentURL = generatedURL
        return generatedURL
    }

    public func setSubtitleFile(path: String?) {
        self.activeSubtitlePath = path
        if path == nil {
            self.currentSubtitleURL = nil
        }
        NSLog("[LocalStreamingServer] Active subtitle set to: %@", path ?? "None")
    }

    private init() {}

    public func start(filePath: String, preferredPort: UInt16 = 8089) throws -> URL {
        stop()

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw NSError(domain: "LocalStreamingServer", code: 404, userInfo: [NSLocalizedDescriptionKey: "File does not exist: \(filePath)"])
        }

        guard let localIP = NetworkHelper.getLocalIPAddress() else {
            throw NSError(domain: "LocalStreamingServer", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not find a valid local network IP address"])
        }

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw NSError(domain: "LocalStreamingServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }

        var opt: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(preferredPort).bigEndian
        addr.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY

        var bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        var boundPort = preferredPort
        if bindRes < 0 {
            // Fallback: pick any available OS-allocated port
            addr.sin_port = 0
            bindRes = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindRes >= 0 else {
                close(sock)
                throw NSError(domain: "LocalStreamingServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to bind server port"])
            }
            var assignedAddr = sockaddr_in()
            var assignedLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            withUnsafeMutablePointer(to: &assignedAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = getsockname(sock, $0, &assignedLen)
                }
            }
            boundPort = assignedAddr.sin_port.byteSwapped
        }

        guard listen(sock, 32) >= 0 else {
            close(sock)
            throw NSError(domain: "LocalStreamingServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to listen on socket"])
        }

        self.serverSocket = sock
        self.isRunning = true
        self.activeFilePath = filePath
        self.activePort = boundPort

        let fileExt = URL(fileURLWithPath: filePath).pathExtension
        let safeName = "stream." + (fileExt.isEmpty ? "mkv" : fileExt)
        let streamURL = URL(string: "http://\(localIP):\(boundPort)/\(safeName)")!
        self.currentURL = streamURL

        NSLog("[LocalStreamingServer] Started on %@", streamURL.absoluteString)

        // Accept loop in background
        queue.async { [weak self] in
            self?.acceptLoop(socket: sock)
        }

        return streamURL
    }

    public func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        closeActiveConnections()

        currentURL = nil
        activeFilePath = nil
        activeSubtitlePath = nil
        currentSubtitleURL = nil
        activePort = 0
    }

    public func closeActiveConnections() {
        connectionLock.lock()
        for client in activeConnections {
            shutdown(client, SHUT_RDWR)
            close(client)
        }
        activeConnections.removeAll()
        connectionLock.unlock()
    }

    private func acceptLoop(socket: Int32) {
        while isRunning {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let clientSock = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(socket, $0, &clientLen)
                }
            }

            guard clientSock >= 0 else {
                if !isRunning { break }
                usleep(10000)
                continue
            }

            var opt: Int32 = 1
            setsockopt(clientSock, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

            connectionLock.lock()
            activeConnections.append(clientSock)
            connectionLock.unlock()

            queue.async { [weak self] in
                self?.handleClient(clientSock)
            }
        }
    }

    private func handleClient(_ clientSock: Int32) {
        defer {
            connectionLock.lock()
            if let idx = activeConnections.firstIndex(of: clientSock) {
                activeConnections.remove(at: idx)
            }
            connectionLock.unlock()
            close(clientSock)
        }

        var headerBuffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(clientSock, &headerBuffer, 4096)
        guard bytesRead > 0 else { return }

        let requestString = String(bytes: headerBuffer[0..<bytesRead], encoding: .utf8) ?? ""
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }

        NSLog("[LocalStreamingServer] Incoming: %@", requestLine)

        let isHead = requestLine.uppercased().starts(with: "HEAD")

        // Handle Subtitle requests (e.g. GET /stream_*.srt, GET /subtitles*.srt or *.srt)
        if requestLine.contains(".srt") || requestLine.contains("subtitles") {
            guard let subPath = activeSubtitlePath,
                  let fileData = try? Data(contentsOf: URL(fileURLWithPath: subPath)),
                  !fileData.isEmpty else {
                NSLog("[LocalStreamingServer] Subtitle requested but activeSubtitlePath is nil or empty: %@", requestLine)
                let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                _ = notFound.withCString { write(clientSock, $0, strlen($0)) }
                return
            }

            NSLog("[LocalStreamingServer] Serving subtitles (%ld bytes) for: %@", fileData.count, requestLine)
            let subHeaders = "HTTP/1.1 200 OK\r\n" +
                             "Server: MKVAirPlay/1.0\r\n" +
                             "Content-Type: text/srt; charset=utf-8\r\n" +
                             "Accept-Ranges: bytes\r\n" +
                             "Content-Length: \(fileData.count)\r\n" +
                             "Cache-Control: no-cache, no-store, must-revalidate\r\n" +
                             "Connection: close\r\n\r\n"
            _ = subHeaders.withCString { write(clientSock, $0, strlen($0)) }
            if !isHead {
                fileData.withUnsafeBytes { ptr in
                    guard let base = ptr.baseAddress else { return }
                    var totalWritten = 0
                    while totalWritten < fileData.count {
                        let res = write(clientSock, base + totalWritten, fileData.count - totalWritten)
                        if res <= 0 { break }
                        totalWritten += res
                    }
                }
            }
            return
        }

        guard let filePath = activeFilePath,
              let fileAttrs = try? FileManager.default.attributesOfItem(atPath: filePath),
              let fileSize = fileAttrs[.size] as? Int64 else {
            let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            _ = notFound.withCString { write(clientSock, $0, strlen($0)) }
            return
        }

        let ext = URL(fileURLWithPath: filePath).pathExtension
        let contentType = NetworkHelper.mimeType(for: ext)

        // Parse Range header if present
        var startOffset: Int64 = 0
        var endOffset: Int64 = fileSize - 1
        var isPartial = false

        for line in lines {
            let lower = line.lowercased()
            if lower.starts(with: "range: bytes=") {
                let rangeValue = line.dropFirst("range: bytes=".count).trimmingCharacters(in: .whitespaces)
                let parts = rangeValue.split(separator: "-", omittingEmptySubsequences: false)
                if parts.count >= 1, !parts[0].isEmpty, let start = Int64(parts[0]) {
                    startOffset = max(0, min(start, fileSize - 1))
                    isPartial = true
                }
                if parts.count >= 2, !parts[1].isEmpty, let end = Int64(parts[1]) {
                    endOffset = max(startOffset, min(end, fileSize - 1))
                    isPartial = true
                } else if isPartial {
                    endOffset = fileSize - 1
                }
                break
            }
        }

        let contentLength = endOffset - startOffset + 1
        let statusCode = isPartial ? "206 Partial Content" : "200 OK"
        var responseHeaders = "HTTP/1.1 \(statusCode)\r\n"
        responseHeaders += "Server: MKVAirPlay/1.0\r\n"
        responseHeaders += "Accept-Ranges: bytes\r\n"
        responseHeaders += "Content-Type: \(contentType)\r\n"
        responseHeaders += "Content-Length: \(contentLength)\r\n"
        if isPartial {
            responseHeaders += "Content-Range: bytes \(startOffset)-\(endOffset)/\(fileSize)\r\n"
        }
        responseHeaders += "Connection: keep-alive\r\n"
        responseHeaders += "Cache-Control: no-cache\r\n"
        responseHeaders += "transferMode.dlna.org: Streaming\r\n"
        responseHeaders += "contentFeatures.dlna.org: DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000\r\n"
        if let subPath = activeSubtitlePath, !subPath.isEmpty, let subURL = currentSubtitleURL {
            responseHeaders += "CaptionInfo.sec: \(subURL.absoluteString)\r\n"
        }
        responseHeaders += "\r\n"

        let headerWriteRes = responseHeaders.withCString { ptr in
            write(clientSock, ptr, strlen(ptr))
        }
        guard headerWriteRes > 0, !isHead else { return }

        // Stream file content in chunks
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else { return }
        defer { try? fileHandle.close() }

        do {
            try fileHandle.seek(toOffset: UInt64(startOffset))
        } catch {
            return
        }

        var bytesRemaining = contentLength
        let chunkSize = 131072 // 128 KB buffer

        while bytesRemaining > 0 && isRunning {
            let toRead = Int(min(bytesRemaining, Int64(chunkSize)))
            let data = fileHandle.readData(ofLength: toRead)
            if data.isEmpty { break }

            let written = data.withUnsafeBytes { rawBuffer in
                write(clientSock, rawBuffer.baseAddress!, data.count)
            }

            guard written > 0 else {
                // Client closed socket (e.g. seeked or stopped)
                break
            }
            bytesRemaining -= Int64(written)
        }
    }
}
