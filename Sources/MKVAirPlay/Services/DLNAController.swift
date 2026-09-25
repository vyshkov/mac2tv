import Foundation

public final class DLNAController: Sendable {
    public static let shared = DLNAController()

    private init() {}

    // MARK: - Set AV Transport URI
    public func setAVTransportURI(device: DLNADevice, mediaURL: URL, title: String, subtitleURL: URL? = nil) async throws {
        // Step 1: Ensure any previous playback is stopped so the TV transitions cleanly
        try? await stop(device: device)
        try? await Task.sleep(nanoseconds: 300_000_000)

        let ext = mediaURL.pathExtension
        let mime = NetworkHelper.mimeType(for: ext)
        let dlnaProtocolInfo = "http-get:*:\(mime):*;DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000"
        let escapedTitle = escapeXML(title)
        let escapedURL = escapeXML(mediaURL.absoluteString)

        var subtitleTags = ""
        if let subURL = subtitleURL {
            let escapedSub = escapeXML(subURL.absoluteString)
            subtitleTags = "&lt;sec:CaptionInfo sec:type=\"srt\"&gt;\(escapedSub)&lt;/sec:CaptionInfo&gt;&lt;sec:CaptionInfoEx sec:type=\"srt\"&gt;\(escapedSub)&lt;/sec:CaptionInfoEx&gt;&lt;res protocolInfo=\"http-get:*:text/srt:*\"&gt;\(escapedSub)&lt;/res&gt;&lt;res protocolInfo=\"http-get:*:smi/caption:*\"&gt;\(escapedSub)&lt;/res&gt;"
        }

        let didl = "&lt;DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" xmlns:dlna=\"urn:schemas-dlna-org:metadata-1-0/\" xmlns:sec=\"http://www.sec.co.kr/\"&gt;&lt;item id=\"0\" parentID=\"-1\" restricted=\"1\"&gt;&lt;dc:title&gt;\(escapedTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.videoItem.movie&lt;/upnp:class&gt;&lt;res protocolInfo=\"\(dlnaProtocolInfo)\"&gt;\(escapedURL)&lt;/res&gt;\(subtitleTags)&lt;/item&gt;&lt;/DIDL-Lite&gt;"

        let action = "SetAVTransportURI"
        let body = """
        <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <InstanceID>0</InstanceID>
          <CurrentURI>\(escapedURL)</CurrentURI>
          <CurrentURIMetaData>\(didl)</CurrentURIMetaData>
        </u:SetAVTransportURI>
        """

        _ = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body)
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

    // MARK: - Play
    public func play(device: DLNADevice) async throws {
        let action = "Play"
        let body = """
        <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <InstanceID>0</InstanceID>
          <Speed>1</Speed>
        </u:Play>
        """

        var lastError: Error?
        for attempt in 1...6 {
            do {
                _ = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body)
                return
            } catch {
                lastError = error
                let desc = error.localizedDescription
                if attempt < 6 && (desc.contains("Transition not available") || desc.contains("701")) {
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

    // MARK: - Pause
    public func pause(device: DLNADevice) async throws {
        let action = "Pause"
        let body = """
        <u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <InstanceID>0</InstanceID>
        </u:Pause>
        """
        _ = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body)
    }

    // MARK: - Stop
    public func stop(device: DLNADevice) async throws {
        let action = "Stop"
        let body = """
        <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <InstanceID>0</InstanceID>
        </u:Stop>
        """
        _ = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body)
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
        for attempt in 1...6 {
            do {
                _ = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body)
                return
            } catch {
                lastError = error
                let desc = error.localizedDescription
                if attempt < 6 && (desc.contains("Transition not available") || desc.contains("701")) {
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
        let xml = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body)
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
        let xml = try await sendSOAP(to: device.avTransportControlURL, serviceType: "urn:schemas-upnp-org:service:AVTransport:1", action: action, body: body)

        let relTimeStr = extractXMLValue(from: xml, tag: "RelTime") ?? "00:00:00"
        let durationStr = extractXMLValue(from: xml, tag: "TrackDuration") ?? "00:00:00"

        let current = TimeHelper.parseHHMMSS(relTimeStr)
        let duration = TimeHelper.parseHHMMSS(durationStr)

        // Also fetch transport info for complete state
        let state = (try? await getTransportInfo(device: device)) ?? .unknown

        return (currentTime: current, duration: duration, state: state)
    }

    // MARK: - Private SOAP Request Helper
    private func sendSOAP(to controlURL: URL, serviceType: String, action: String, body: String) async throws -> String {
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
        request.timeoutInterval = 5.0

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

    private func extractXMLValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
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
}
