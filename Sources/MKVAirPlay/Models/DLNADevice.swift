import Foundation

public struct DLNADevice: Identifiable, Hashable, Equatable, Sendable {
    public let id: String
    public let friendlyName: String
    public let modelName: String
    public let baseURL: URL
    public let avTransportControlURL: URL
    public let renderingControlURL: URL?

    public var displayName: String {
        friendlyName.isEmpty ? "Smart TV (\(baseURL.host ?? "Unknown"))" : friendlyName
    }

    public init(
        id: String,
        friendlyName: String,
        modelName: String,
        baseURL: URL,
        avTransportControlURL: URL,
        renderingControlURL: URL? = nil
    ) {
        self.id = id
        self.friendlyName = friendlyName
        self.modelName = modelName
        self.baseURL = baseURL
        self.avTransportControlURL = avTransportControlURL
        self.renderingControlURL = renderingControlURL
    }

    public static func == (lhs: DLNADevice, rhs: DLNADevice) -> Bool {
        lhs.id == rhs.id || lhs.avTransportControlURL == rhs.avTransportControlURL
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
