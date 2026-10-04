import Foundation

public struct AudioTrack: Identifiable, Hashable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let language: String?
    public let streamIndex: Int?
    public let codec: String?
    public let channels: Int?
    public let channelLayout: String?
    public let isDefault: Bool
    public let externalURL: URL?

    public init(
        id: String,
        title: String,
        language: String? = nil,
        streamIndex: Int? = nil,
        codec: String? = nil,
        channels: Int? = nil,
        channelLayout: String? = nil,
        isDefault: Bool = false,
        externalURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.streamIndex = streamIndex
        self.codec = codec
        self.channels = channels
        self.channelLayout = channelLayout
        self.isDefault = isDefault
        self.externalURL = externalURL
    }

    public var localizedLanguage: String? {
        guard let lang = language, !lang.isEmpty else { return nil }
        if let localized = Locale.current.localizedString(forLanguageCode: lang) {
            return localized.capitalized
        }
        return lang.uppercased()
    }

    public var layoutBadge: String? {
        if let layout = channelLayout, !layout.isEmpty {
            if layout.lowercased() == "stereo" { return "Stereo" }
            if layout.lowercased() == "mono" { return "Mono" }
            return layout
        }
        if let ch = channels, ch > 0 {
            if ch == 1 { return "Mono" }
            if ch == 2 { return "Stereo" }
            if ch == 6 { return "5.1" }
            if ch == 8 { return "7.1" }
            return "\(ch) ch"
        }
        return nil
    }

    public var displayName: String {
        var components: [String] = []

        if let l = localizedLanguage {
            components.append(l)
        }

        if !title.isEmpty && title.lowercased() != language?.lowercased() && title.lowercased() != localizedLanguage?.lowercased() {
            components.append(title)
        }

        if components.isEmpty {
            if let idx = streamIndex {
                components.append("Track \(idx)")
            } else if let ext = externalURL {
                components.append(ext.deletingPathExtension().lastPathComponent)
            } else {
                components.append("Audio")
            }
        }

        var label = components.joined(separator: " - ")

        var technicalDetails: [String] = []
        if let codec = codec, !codec.isEmpty {
            technicalDetails.append(codec.uppercased())
        }
        if let badge = layoutBadge {
            technicalDetails.append(badge)
        }

        if !technicalDetails.isEmpty {
            label += " (\(technicalDetails.joined(separator: " ")))"
        }

        if let ext = externalURL {
            label += " [\(ext.lastPathComponent)]"
        }

        return label
    }

    public var shortDisplayName: String {
        let base = localizedLanguage ?? (!title.isEmpty ? title : (streamIndex != nil ? "Track \(streamIndex!)" : "Audio"))
        if let badge = layoutBadge {
            return "\(base) (\(badge))"
        }
        return base
    }
}
