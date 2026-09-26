import Foundation

public final class DLNAController: Sendable {
    public static let shared = DLNAController()

    private init() {}

    // MARK: - Set AV Transport URI
    public func setAVTransportURI(
        device: DLNADevice,
        mediaURL: URL,
        title: String,
        subtitleURL: URL? = nil,
        onRetry: (@Sendable (_ attempt: Int, _ maxAttempts: Int, _ error: Error) -> Void)? = nil
    ) async throws {
        // Step 1: Ensure any previous playback is stopped so the TV transitions cleanly.
        // Use a short timeout (2.5s) for best-effort pre-stop so we don't stall if the TV app is cold.
        try? await stop(device: device, timeout: 2.5)
        try? await Task.sleep(nanoseconds: 300_000_000)

        let ext = mediaURL.pathExtension
        let mime = NetworkHelper.mimeType(for: ext)
        let dlnaProtocolInfo = "http-get:*:\(mime):*;DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000"
        let escapedTitle = escapeDIDL(title)
        let escapedURL = escapeXML(mediaURL.absoluteString)
        let didlMediaURL = escapeDIDL(mediaURL.absoluteString)

        var subtitleTags = ""
        if let subURL = subtitleURL {
            let didlSubURL = escapeDIDL(subURL.absoluteString)
            subtitleTags = "&lt;sec:CaptionInfo sec:type=\"srt\"&gt;\(didlSubURL)&lt;/sec:CaptionInfo&gt;&lt;sec:CaptionInfoEx sec:type=\"srt\"&gt;\(didlSubURL)&lt;/sec:CaptionInfoEx&gt;&lt;res protocolInfo=\"http-get:*:text/srt:*\"&gt;\(didlSubURL)&lt;/res&gt;&lt;res protocolInfo=\"http-get:*:smi/caption:*\"&gt;\(didlSubURL)&lt;/res&gt;&lt;res protocolInfo=\"http-get:*:application/x-subrip:*\"&gt;\(didlSubURL)&lt;/res&gt;&lt;res protocolInfo=\"http-get:*:text/plain:*\"&gt;\(didlSubURL)&lt;/res&gt;"
        }

        let didl = "&lt;DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" xmlns:dlna=\"urn:schemas-dlna-org:metadata-1-0/\" xmlns:sec=\"http://www.sec.co.kr/\"&gt;&lt;item id=\"0\" parentID=\"-1\" restricted=\"1\"&gt;&lt;dc:title&gt;\(escapedTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.videoItem.movie&lt;/upnp:class&gt;&lt;res protocolInfo=\"\(dlnaProtocolInfo)\"&gt;\(didlMediaURL)&lt;/res&gt;\(subtitleTags)&lt;/item&gt;&lt;/DIDL-Lite&gt;"

        let action = "SetAVTransportURI"
        let body = """
        <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <InstanceID>0</InstanceID>
          <CurrentURI>\(escapedURL)</CurrentURI>
          <CurrentURIMetaData>\(didl)</CurrentURIMetaData>
        </u:SetAVTransportURI>
        """

        var lastError: Error?
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                _ = try await sendSOAP(
                    to: device.avTransportControlURL,
                    serviceType: "urn:schemas-upnp-org:service:AVTransport:1",
                    action: action,
                    body: body,
                    timeout: 12.0
                )
                return
            } catch {
                lastError = error
                NSLog("[DLNAController] SetAVTransportURI attempt %d/%d failed: %@", attempt, maxAttempts, error.localizedDescription)
                if attempt < maxAttempts && isRetryableError(error) {
                    onRetry?(attempt, maxAttempts, error)
                    // If timeout or connection issue, give the TV extra time to finish loading its app
                    let delay = isTimeoutError(error) ? 1_500_000_000 : 800_000_000
                    try? await Task.sleep(nanoseconds: UInt64(delay))
                } else {
                    throw error
                }
            }
        }
        if let err = lastError {
            throw err
        }
    }

    // MARK: - Set Subtitle Display (Optional UPnP RenderingControl)
    public func setSubtitleDisplay(device: DLNADevice, enabled: Bool) async {
        guard let rcURL = device.renderingControlURL else { return }
        let action = "X_SetSubtitle"
        let body = """
        <u:X_SetSubtitle xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
          <InstanceID>0</InstanceID>
          <DesiredSubtitle>\(enabled ? "ON" : "OFF")</DesiredSubtitle>
        </u:X_SetSubtitle>
        """
        _ = try? await sendSOAP(to: rcURL, serviceType: "urn:schemas-upnp-org:service:RenderingControl:1", action: action, body: body)
    }

    // MARK: - Rendering Control (Volume & Mute)
    public func getVolume(device: DLNADevice) async throws -> Int {
        guard let rcURL = device.renderingControlURL else {
            throw NSError(domain: "DLNAController", code: 404, userInfo: [NSLocalizedDescriptionKey: "TV does not support volume control (RenderingControl service missing)"])
        }
        let action = "GetVolume"
        let body = """
        <u:GetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
          <InstanceID>0</InstanceID>
          <Channel>Master</Channel>
        </u:GetVolume>
        """
        let xml = try await sendSOAP(to: rcURL, serviceType: "urn:schemas-upnp-org:service:RenderingControl:1", action: action, body: body)
        if let volStr = extractXMLValue(from: xml, tag: "CurrentVolume"), let vol = Int(volStr) {
            return max(0, min(100, vol))
        }
        throw NSError(domain: "DLNAController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse TV volume"])
    }

    public func setVolume(device: DLNADevice, volume: Int) async throws {
        guard let rcURL = device.renderingControlURL else {
            throw NSError(domain: "DLNAController", code: 404, userInfo: [NSLocalizedDescriptionKey: "TV does not support volume control (RenderingControl service missing)"])
        }
        let clamped = max(0, min(100, volume))
        let action = "SetVolume"
        let body = """
        <u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
          <InstanceID>0</InstanceID>
          <Channel>Master</Channel>
          <DesiredVolume>\(clamped)</DesiredVolume>
        </u:SetVolume>
        """
        _ = try await sendSOAP(to: rcURL, serviceType: "urn:schemas-upnp-org:service:RenderingControl:1", action: action, body: body)
    }

    public func getMute(device: DLNADevice) async throws -> Bool {
        guard let rcURL = device.renderingControlURL else {
            throw NSError(domain: "DLNAController", code: 404, userInfo: [NSLocalizedDescriptionKey: "TV does not support volume control (RenderingControl service missing)"])
        }
        let action = "GetMute"
        let body = """
        <u:GetMute xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
          <InstanceID>0</InstanceID>
          <Channel>Master</Channel>
        </u:GetMute>
        """
        let xml = try await sendSOAP(to: rcURL, serviceType: "urn:schemas-upnp-org:service:RenderingControl:1", action: action, body: body)
        if let muteStr = extractXMLValue(from: xml, tag: "CurrentMute") {
            return muteStr == "1" || muteStr.lowercased() == "true"
        }
        return false
    }

    public func setMute(device: DLNADevice, isMuted: Bool) async throws {
        guard let rcURL = device.renderingControlURL else {
            throw NSError(domain: "DLNAController", code: 404, userInfo: [NSLocalizedDescriptionKey: "TV does not support volume control (RenderingControl service missing)"])
        }
        let action = "SetMute"
        let body = """
        <u:SetMute xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
          <InstanceID>0</InstanceID>
          <Channel>Master</Channel>
          <DesiredMute>\(isMuted ? "1" : "0")</DesiredMute>
        </u:SetMute>
        """
        _ = try await sendSOAP(to: rcURL, serviceType: "urn:schemas-upnp-org:service:RenderingControl:1", action: action, body: body)
    }

    // MARK: - Play
    public func play(
        device: DLNADevice,
        onRetry: (@Sendable (_ attempt: Int, _ maxAttempts: Int, _ error: Error) -> Void)? = nil
    ) async throws {
        let action = "Play"
        let body = """
        <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <InstanceID>0</InstanceID>
          <Speed>1</Speed>
        </u:Play>
        """

        var lastError: Error?
        let maxAttempts = 5
        for attempt in 1...maxAttempts {
            do {
                _ = try await sendSOAP(
                    to: device.avTransportControlURL,
                    serviceType: "urn:schemas-upnp-org:service:AVTransport:1",
                    action: action,
                    body: body,
                    timeout: 10.0
                )
                return
            } catch {
                lastError = error
                NSLog("[DLNAController] Play attempt %d/%d failed: %@", attempt, maxAttempts, error.localizedDescription)
                if attempt < maxAttempts && isRetryableError(error) {
                    onRetry?(attempt, maxAttempts, error)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                } else {
                    throw error
                }
            }
        }
        if let err = lastError {
            throw err
        }
    }

    // MARK: - Pause
    public func pause(device: DLNADevice) async throws {
        let action = "Pause"
        let body = """
        <u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <InstanceID>0</InstanceID>
        </u:Pause>
        """
        _ = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body, timeout: 5.0)
    }

    // MARK: - Stop
    public func stop(device: DLNADevice, timeout: TimeInterval = 4.0) async throws {
        let action = "Stop"
        let body = """
        <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <InstanceID>0</InstanceID>
        </u:Stop>
        """
        _ = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body, timeout: timeout)
    }

    // MARK: - Seek
    public func seek(device: DLNADevice, toSeconds seconds: Double) async throws {
        let formattedTime = TimeHelper.formatHHMMSS(seconds: seconds)
        let action = "Seek"
        let body = """
        <u:Seek xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <InstanceID>0</InstanceID>
          <Unit>REL_TIME</Unit>
          <Target>\(formattedTime)</Target>
        </u:Seek>
        """

        var lastError: Error?
        for attempt in 1...8 {
            do {
                _ = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body, timeout: 8.0)
                return
            } catch {
                lastError = error
                if attempt < 8 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                } else {
                    throw error
                }
            }
        }
        if let err = lastError {
            throw err
        }
    }

    // MARK: - Get Transport Info
    public func getTransportInfo(device: DLNADevice) async throws -> TransportState {
        let action = "GetTransportInfo"
        let body = """
        <u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <InstanceID>0</InstanceID>
        </u:GetTransportInfo>
        """
        let xml = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body, timeout: 3.5)
        if let stateStr = extractXMLValue(from: xml, tag: "CurrentTransportState") {
            return TransportState(rawState: stateStr)
        }
        return .unknown
    }

    // MARK: - Get Position Info
    public func getPositionInfo(device: DLNADevice) async throws -> (currentTime: Double, duration: Double, state: TransportState) {
        let action = "GetPositionInfo"
        let body = """
        <u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <InstanceID>0</InstanceID>
        </u:GetPositionInfo>
        """
        let xml = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body, timeout: 3.5)

        let relTimeStr = extractXMLValue(from: xml, tag: "RelTime") ?? "00:00:00"
        let durationStr = extractXMLValue(from: xml, tag: "TrackDuration") ?? "00:00:00"

        let current = TimeHelper.parseHHMMSS(relTimeStr)
        let duration = TimeHelper.parseHHMMSS(durationStr)

        // Also fetch transport info for complete state
        let state = (try? await getTransportInfo(device: device)) ?? .unknown

        return (currentTime: current, duration: duration, state: state)
    }

    // MARK: - Private SOAP Request Helper
    private func sendSOAP(
        to controlURL: URL,
        serviceType: String,
        action: String,
        body: String,
        timeout: TimeInterval = 10.0
    ) async throws -> String {
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            \(body)
          </s:Body>
        </s:Envelope>
        """

        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPAction")
        request.httpBody = envelope.data(using: .utf8)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "DLNAController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }

        let respString = String(data: data, encoding: .utf8) ?? ""

        guard httpResponse.statusCode == 200 else {
            let errorDesc = extractXMLValue(from: respString, tag: "errorDescription") ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "DLNAController", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "UPnP Action Failed: \(errorDesc)"])
        }

        return respString
    }

    // MARK: - Retry & Error Classification Helpers
    private func isTimeoutError(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
            return true
        }
        let desc = error.localizedDescription.lowercased()
        return desc.contains("timed out") || desc.contains("timeout")
    }

    private func isRetryableError(_ error: Error) -> Bool {
        if isTimeoutError(error) {
            return true
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .cannotFindHost, .notConnectedToInternet:
                return true
            default:
                break
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            if nsError.code == NSURLErrorCannotConnectToHost ||
               nsError.code == NSURLErrorNetworkConnectionLost ||
               nsError.code == NSURLErrorCannotFindHost ||
               nsError.code == NSURLErrorNotConnectedToInternet {
                return true
            }
        }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("transition not available") ||
           desc.contains("701") ||
           desc.contains("action failed") ||
           desc.contains("501") ||
           desc.contains("connection refused") ||
           desc.contains("connection reset") ||
           desc.contains("reset by peer") ||
           desc.contains("broken pipe") {
            return true
        }
        return false
    }

    private func extractXMLValue(from xml: String, tag: String) -> String? {
        // Match optional XML namespace prefixes (e.g. <u:CurrentVolume> or <CurrentVolume>) and any tag attributes
        let pattern = "<(?:[a-zA-Z0-9_-]+:)?\(tag)(?:\\s+[^>]*)?>(.*?)</(?:[a-zA-Z0-9_-]+:)?\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              let r = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func escapeXML(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func escapeDIDL(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;amp;")
            .replacingOccurrences(of: "<", with: "&amp;lt;")
            .replacingOccurrences(of: ">", with: "&amp;gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
