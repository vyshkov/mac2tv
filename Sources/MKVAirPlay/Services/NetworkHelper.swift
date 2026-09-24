import Foundation
import Darwin

public enum NetworkHelper {
    public static func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidateIPs: [(name: String, ip: String)] = []

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            guard isUp && isRunning && !isLoopback else { continue }
            guard let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let ifName = String(cString: ptr.pointee.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: hostname)
                candidateIPs.append((name: ifName, ip: ip))
            }
        }

        // Prioritize en0 (standard primary interface on macOS)
        if let en0 = candidateIPs.first(where: { $0.name == "en0" }) {
            return en0.ip
        }

        // Otherwise prefer 192.168.x or 10.x
        if let lan = candidateIPs.first(where: { $0.ip.starts(with: "192.168.") || $0.ip.starts(with: "10.") || $0.ip.starts(with: "172.") }) {
            return lan.ip
        }

        return candidateIPs.first?.ip
    }

    public static func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "mkv":
            return "video/x-matroska"
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "avi":
            return "video/x-msvideo"
        case "webm":
            return "video/webm"
        case "ts":
            return "video/mp2t"
        case "mp3":
            return "audio/mpeg"
        case "aac":
            return "audio/aac"
        case "flac":
            return "audio/flac"
        default:
            return "video/x-matroska"
        }
    }
}
