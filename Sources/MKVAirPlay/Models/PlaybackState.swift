import Foundation
import SwiftUI

public enum TransportState: Equatable, Sendable {
    case stopped
    case playing
    case paused
    case transitioning
    case error(String)
    case unknown

    public init(rawState: String) {
        let normalized = rawState.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "PLAYING":
            self = .playing
        case "PAUSED_PLAYBACK", "PAUSED":
            self = .paused
        case "STOPPED":
            self = .stopped
        case "TRANSITIONING", "BUFFERING":
            self = .transitioning
        default:
            self = .unknown
        }
    }

    public var title: String {
        switch self {
        case .stopped: return "Stopped"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .transitioning: return "Buffering"
        case .error(let msg): return "Error: \(msg)"
        case .unknown: return "Ready"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .stopped: return "stop.fill"
        case .playing: return "play.fill"
        case .paused: return "pause.fill"
        case .transitioning: return "antenna.radiowaves.left.and.right"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "tv"
        }
    }

    public var color: Color {
        switch self {
        case .playing: return .green
        case .paused: return .orange
        case .transitioning: return .blue
        case .stopped: return .secondary
        case .error: return .red
        case .unknown: return .secondary
        }
    }
}

public enum TimeHelper {
    public static func format(seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else {
            return "00:00"
        }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    public static func formatHHMMSS(seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else {
            return "00:00:00"
        }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    public static func parseHHMMSS(_ str: String) -> Double {
        let parts = str.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ":")
            .compactMap { Double($0) }
        switch parts.count {
        case 3:
            return parts[0] * 3600.0 + parts[1] * 60.0 + parts[2]
        case 2:
            return parts[0] * 60.0 + parts[1]
        case 1:
            return parts[0]
        default:
            return 0.0
        }
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
