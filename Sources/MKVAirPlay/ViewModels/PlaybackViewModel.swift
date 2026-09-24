import Foundation
import SwiftUI
import Combine

@MainActor
public final class PlaybackViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published public var selectedFileURL: URL?
    @Published public var selectedFileName: String = ""
    @Published public var selectedFileSize: String = ""
    @Published public var selectedFileFormat: String = ""

    @Published public var discoveredDevices: [DLNADevice] = []
    @Published public var selectedDevice: DLNADevice?
    @Published public var isSearchingDevices: Bool = false

    @Published public var isStreaming: Bool = false
    @Published public var playbackState: TransportState = .stopped
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0

    @Published public var isUserScrubbing: Bool = false
    @Published public var scrubPosition: Double = 0

    @Published public var isDropTargeted: Bool = false
    @Published public var showingManualIPSheet: Bool = false
    @Published public var manualIPText: String = ""

    @Published public var statusMessage: String = "Select a video file to begin"
    @Published public var errorMessage: String?
    @Published public var activeStreamURL: String?

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private let discovery = SSDPDiscovery.shared
    private let server = LocalStreamingServer.shared
    private let dlna = DLNAController.shared

    public init() {
        setupSubscriptions()
        startDiscovery()
    }

    // MARK: - Setup
    private func setupSubscriptions() {
        discovery.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self = self else { return }
                self.discoveredDevices = devices
                if self.selectedDevice == nil, let first = devices.first {
                    self.selectedDevice = first
                }
            }
            .store(in: &cancellables)

        discovery.$isSearching
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSearchingDevices)
    }

    public func startDiscovery() {
        discovery.startDiscovery()
    }

    public func refreshDiscovery() {
        discovery.refresh()
    }

    public func addManualDevice(ipOrHost: String, port: Int = 1500) {
        discovery.addManualDevice(ipOrHost: ipOrHost, port: port)
    }

    // MARK: - File Selection
    public func selectFile(url: URL) {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            errorMessage = "File not found at \(path)"
            return
        }

        selectedFileURL = url
        selectedFileName = url.lastPathComponent
        selectedFileFormat = url.pathExtension.uppercased()

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            selectedFileSize = TimeHelper.formatBytes(size)
        } else {
            selectedFileSize = ""
        }

        errorMessage = nil
        statusMessage = "Ready to stream \"\(selectedFileName)\""
    }

    // MARK: - Streaming
    public func startStreaming() {
        guard let fileURL = selectedFileURL else {
            errorMessage = "Please choose a video file first."
            return
        }
        guard let device = selectedDevice else {
            errorMessage = "No TV device selected. Ensure your TV is on the same Wi-Fi network."
            return
        }

        errorMessage = nil
        statusMessage = "Starting local stream for \(device.displayName)..."
        playbackState = .transitioning

        Task {
            do {
                // 1. Start local byte-range HTTP server
                let streamURL = try server.start(filePath: fileURL.path)
                activeStreamURL = streamURL.absoluteString

                // 2. Instruct TV to load media URI
                statusMessage = "Connecting to \(device.displayName)..."
                try await dlna.setAVTransportURI(device: device, mediaURL: streamURL, title: fileURL.deletingPathExtension().lastPathComponent)

                // Small delay to allow TV to buffer initial header
                try await Task.sleep(nanoseconds: 500_000_000)

                // 3. Command TV to play
                try await dlna.play(device: device)

                isStreaming = true
                playbackState = .playing
                statusMessage = "Streaming to \(device.displayName)"

                startPolling(device: device)
            } catch {
                server.stop()
                isStreaming = false
                playbackState = .error(error.localizedDescription)
                errorMessage = "Streaming error: \(error.localizedDescription)"
                statusMessage = "Streaming failed"
            }
        }
    }

    public func togglePlayPause() {
        guard let device = selectedDevice, isStreaming else { return }

        Task {
            do {
                if playbackState == .playing {
                    try await dlna.pause(device: device)
                    playbackState = .paused
                    statusMessage = "Paused on \(device.displayName)"
                } else {
                    try await dlna.play(device: device)
                    playbackState = .playing
                    statusMessage = "Playing on \(device.displayName)"
                }
            } catch {
                errorMessage = "Playback command failed: \(error.localizedDescription)"
            }
        }
    }

    public func stop() {
        stopPolling()
        guard let device = selectedDevice else {
            finishStop()
            return
        }

        Task {
            try? await dlna.stop(device: device)
            finishStop()
        }
    }

    private func finishStop() {
        server.stop()
        isStreaming = false
        playbackState = .stopped
        currentTime = 0
        activeStreamURL = nil
        statusMessage = selectedFileURL != nil ? "Ready to stream" : "Select a video file to begin"
    }

    // MARK: - Seeking
    public func seek(to seconds: Double) {
        guard let device = selectedDevice, isStreaming else { return }
        let target = max(0, min(duration > 0 ? duration : seconds, seconds))
        currentTime = target

        Task {
            do {
                try await dlna.seek(device: device, toSeconds: target)
            } catch {
                errorMessage = "Seek failed: \(error.localizedDescription)"
            }
        }
    }

    public func skip(by delta: Double) {
        let target = currentTime + delta
        seek(to: target)
    }

    public func onScrubbingBegan() {
        isUserScrubbing = true
        scrubPosition = currentTime
    }

    public func onScrubbingChanged(to position: Double) {
        scrubPosition = position
    }

    public func onScrubbingEnded() {
        isUserScrubbing = false
        seek(to: scrubPosition)
    }

    // MARK: - Position & State Polling
    private func startPolling(device: DLNADevice) {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isStreaming else { return }
                await self.pollStatus(device: device)
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollStatus(device: DLNADevice) async {
        do {
            let info = try await dlna.getPositionInfo(device: device)

            if !isUserScrubbing {
                if info.currentTime > 0 || currentTime == 0 {
                    currentTime = info.currentTime
                }
                if info.duration > 0 {
                    duration = info.duration
                }
            }

            if info.state != .unknown && info.state != playbackState {
                playbackState = info.state
            }

            // If stopped unexpectedly on TV
            if info.state == .stopped && currentTime > 0 && currentTime >= (duration - 2) {
                statusMessage = "Playback finished"
                stop()
            }
        } catch {
            // Polling error non-fatal, will retry next second
        }
    }
}
