import Foundation

public struct SubtitleTrack: Identifiable, Hashable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let language: String?
    public let streamIndex: Int?
    public let externalURL: URL?
    public let isOff: Bool

    public static let off = SubtitleTrack(
        id: "off",
        title: "Off",
        language: nil,
        streamIndex: nil,
        externalURL: nil,
        isOff: true
    )

    public init(
        id: String,
        title: String,
        language: String? = nil,
        streamIndex: Int? = nil,
        externalURL: URL? = nil,
        isOff: Bool = false
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.streamIndex = streamIndex
        self.externalURL = externalURL
        self.isOff = isOff
    }

    public var displayName: String {
        if isOff { return "Off" }

        var label = ""
        if let lang = language, !lang.isEmpty {
            label = lang.uppercased()
        }

        if !title.isEmpty && title.lowercased() != language?.lowercased() {
            if label.isEmpty {
                label = title
            } else {
                label += " - \(title)"
            }
        }

        if label.isEmpty {
            if let idx = streamIndex {
                label = "Track \(idx)"
            } else if let ext = externalURL {
                label = ext.lastPathComponent
            } else {
                label = "Subtitle"
            }
        } else {
            if let ext = externalURL {
                label += " [\(ext.lastPathComponent)]"
            }
        }

        return label
    }
}
