import Foundation
import Darwin
import Combine

public final class SSDPDiscovery: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = SSDPDiscovery()

    @Published public private(set) var devices: [DLNADevice] = []
    @Published public private(set) var isSearching: Bool = false

    private var discoveredLocationURLs = Set<URL>()
    private let discoveryQueue = DispatchQueue(label: "com.mkvairplay.ssdpDiscovery", attributes: .concurrent)
    private var searchTimer: Timer?

    public override init() {
        super.init()
    }

    public func startDiscovery() {
        guard !isSearching else { return }
        isSearching = true
        discoveredLocationURLs.removeAll()

        discoveryQueue.async { [weak self] in
            self?.performSSDPSearch()
        }

        // Schedule periodic refresh every 15 seconds
        DispatchQueue.main.async { [weak self] in
            self?.searchTimer?.invalidate()
            self?.searchTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
                self?.discoveryQueue.async {
                    self?.performSSDPSearch()
                }
            }
        }
    }

    public func refresh() {
        discoveryQueue.async { [weak self] in
            self?.performSSDPSearch()
        }
    }

    public func stopDiscovery() {
        isSearching = false
        searchTimer?.invalidate()
        searchTimer = nil
    }

    private func performSSDPSearch() {
        guard let localIP = NetworkHelper.getLocalIPAddress() else {
            NSLog("[SSDPDiscovery] No local IP found")
            return
        }

        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return }
        defer { close(sock) }

        var inAddr = in_addr()
        inet_aton(localIP, &inAddr)
        setsockopt(sock, IPPROTO_IP, IP_MULTICAST_IF, &inAddr, socklen_t(MemoryLayout<in_addr>.size))

        var tv = timeval(tv_sec: 2, tv_usec: 500000) // 2.5s timeout
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var destAddr = sockaddr_in()
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = in_port_t(1900).bigEndian
        inet_aton("239.255.255.250", &destAddr.sin_addr)

        let targets = [
            "urn:schemas-upnp-org:device:MediaRenderer:1",
            "urn:schemas-upnp-org:service:AVTransport:1"
        ]

        for target in targets {
            let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(target)\r\n\r\n"
            msg.withCString { ptr in
                withUnsafePointer(to: &destAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        _ = sendto(sock, ptr, strlen(ptr), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var buf = [UInt8](repeating: 0, count: 8192)
        var fromAddr = sockaddr_in()
        var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        while isSearching {
            let r = withUnsafeMutablePointer(to: &fromAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(sock, &buf, 8192, 0, $0, &fromLen)
                }
            }
            if r <= 0 { break }

            guard let resp = String(bytes: buf[0..<r], encoding: .utf8) else { continue }
            for line in resp.components(separatedBy: "\r\n") {
                if line.lowercased().starts(with: "location:") {
                    let locStr = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                    if let locURL = URL(string: locStr) {
                        handleDiscoveredLocation(locURL)
                    }
                }
            }
        }
    }

    public func handleDiscoveredLocation(_ url: URL) {
        if discoveredLocationURLs.contains(url) { return }
        discoveredLocationURLs.insert(url)

        discoveryQueue.async { [weak self] in
            self?.fetchDeviceDescription(from: url)
        }
    }

    public func fetchDeviceDescription(from url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }

            let parser = UPnPDeviceXMLParser(data: data, baseURL: url)
            if let device = parser.parse() {
                DispatchQueue.main.async {
                    if !self.devices.contains(where: { $0.id == device.id || $0.avTransportControlURL == device.avTransportControlURL }) {
                        self.devices.append(device)
                        NSLog("[SSDPDiscovery] Discovered: %@ (%@)", device.friendlyName, device.avTransportControlURL.absoluteString)
                    }
                }
            }
        }
        task.resume()
    }

    public func addManualDevice(ipOrHost: String, port: Int = 1500) {
        let cleanHost = ipOrHost.replacingOccurrences(of: "http://", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: "http://\(cleanHost):\(port)/") {
            handleDiscoveredLocation(url)
        }
    }
}

// MARK: - UPnP Device Description XML Parser
final class UPnPDeviceXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private let baseURL: URL

    private var currentElement: String = ""
    private var currentText: String = ""

    private var friendlyName: String = ""
    private var modelName: String = ""
    private var udn: String = ""

    private var currentServiceType: String = ""
    private var currentControlURL: String = ""

    private var avTransportControlURL: URL?
    private var renderingControlURL: URL?

    init(data: Data, baseURL: URL) {
        self.parser = XMLParser(data: data)
        self.baseURL = baseURL
        super.init()
        self.parser.delegate = self
    }

    func parse() -> DLNADevice? {
        parser.parse()

        guard let avTransportURL = avTransportControlURL else { return nil }

        let deviceID = udn.isEmpty ? baseURL.absoluteString : udn
        let name = friendlyName.isEmpty ? (baseURL.host ?? "Unknown Smart TV") : friendlyName

        return DLNADevice(
            id: deviceID,
            friendlyName: name,
            modelName: modelName.isEmpty ? "MediaRenderer" : modelName,
            baseURL: baseURL,
            avTransportControlURL: avTransportURL,
            renderingControlURL: renderingControlURL
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName.lowercased() {
        case "friendlyname":
            if friendlyName.isEmpty { friendlyName = trimmed }
        case "modelname":
            if modelName.isEmpty { modelName = trimmed }
        case "udn":
            if udn.isEmpty { udn = trimmed }
        case "servicetype":
            currentServiceType = trimmed
        case "controlurl":
            currentControlURL = trimmed
        case "service":
            if currentServiceType.contains("AVTransport") {
                if let url = resolveURL(currentControlURL) {
                    avTransportControlURL = url
                }
            } else if currentServiceType.contains("RenderingControl") {
                if let url = resolveURL(currentControlURL) {
                    renderingControlURL = url
                }
            }
            currentServiceType = ""
            currentControlURL = ""
        default:
            break
        }
    }

    private func resolveURL(_ path: String) -> URL? {
        if path.starts(with: "http://") || path.starts(with: "https://") {
            return URL(string: path)
        }
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: cleanPath, relativeTo: baseURL)?.absoluteURL
    }
}
