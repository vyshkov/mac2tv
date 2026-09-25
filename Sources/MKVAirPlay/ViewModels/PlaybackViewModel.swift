import Foundation
import SwiftUI
import Combine

@MainActor
public final class PlaybackViewModel: ObservableObject {
    public static let shared = PlaybackViewModel()

    // MARK: - Published Properties
    @Published public var selectedFileURL: URL?
    @Published public var selectedFileName: String = ""
    @Published public var selectedFileSize: String = ""
    @Published public var selectedFileFormat: String = ""

    @Published public var discoveredDevices: [DLNADevice] = []
    @Published public var selectedDevice: DLNADevice? {
        didSet {
            supportsVolumeControl = selectedDevice?.renderingControlURL != nil
            if supportsVolumeControl {
                fetchVolume()
            }
        }
    }
    @Published public var isSearchingDevices: Bool = false

    @Published public var volume: Double = 50.0
    @Published public var isMuted: Bool = false
    @Published public var supportsVolumeControl: Bool = false
    private var volumeDebounceTask: Task<Void, Never>?

    @Published public var isStreaming: Bool = false {
        didSet {
            updateSleepPrevention()
        }
    }
    @Published public var isConnecting: Bool = false
    @Published public var playbackState: TransportState = .stopped {
        didSet {
            updateSleepPrevention()
        }
    }
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0

    @Published public var isUserScrubbing: Bool = false
    @Published public var scrubPosition: Double = 0

    @Published public var availableSubtitles: [SubtitleTrack] = [SubtitleTrack.off]
    @Published public var selectedSubtitle: SubtitleTrack = SubtitleTrack.off

    @Published public var preventSleepOnLidClose: Bool = (UserDefaults.standard.object(forKey: "preventSleepOnLidClose") as? Bool) ?? false {
        didSet {
            UserDefaults.standard.set(preventSleepOnLidClose, forKey: "preventSleepOnLidClose")
            refreshPowerAndAuthStatus()
            updateSleepPrevention()
        }
    }

    @Published public var isBatteryLidSleepAuthorized: Bool = SleepManager.checkBatteryAuthorization()
    @Published public var isOnBattery: Bool = SleepManager.getPowerStatus().isOnBattery
    @Published public var batteryLevel: Int? = SleepManager.getPowerStatus().batteryPercentage
    @Published public var batteryAuthErrorMessage: String? = nil

    @Published public var isDropTargeted: Bool = false
    @Published public var showingManualIPSheet: Bool = false
    @Published public var showingVolumePopover: Bool = false
    @Published public var manualIPText: String = ""

    @Published public var statusMessage: String = "Select a video file to begin"
    @Published public var errorMessage: String?
    @Published public var activeStreamURL: String?

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private var subtitleSwitchTask: Task<Void, Never>?
    private var hasStartedPlaying: Bool = false
    private var consecutivePollErrors: Int = 0
    private let discovery = SSDPDiscovery.shared
    private let server = LocalStreamingServer.shared
    private let dlna = DLNAController.shared

    public init() {
        setupSubscriptions()
        startDiscovery()
        refreshPowerAndAuthStatus()
        setupBatterySafeguard()
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
                    self.isSearchingDevices = false
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
        let standardized = url.standardizedFileURL
        let path = standardized.path
        guard FileManager.default.fileExists(atPath: path) else {
            errorMessage = "File not found at \(path)"
            return
        }

        if selectedFileURL?.standardizedFileURL == standardized && !isStreaming {
            return
        }

        if isStreaming {
            stop()
        }

        selectedFileURL = standardized
        selectedFileName = standardized.lastPathComponent
        selectedFileFormat = standardized.pathExtension.uppercased()

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            selectedFileSize = TimeHelper.formatBytes(size)
        } else {
            selectedFileSize = ""
        }

        errorMessage = nil
        isConnecting = false
        statusMessage = "Ready to stream \"\(selectedFileName)\""

        // Reset and probe for subtitles (embedded & external)
        availableSubtitles = [SubtitleTrack.off]
        selectedSubtitle = SubtitleTrack.off

        Task {
            let tracks = await SubtitleHelper.probeSubtitleTracks(for: standardized)
            self.availableSubtitles = tracks
            // Default to first subtitle if available, or keep Off
            if let firstTrack = tracks.first(where: { !$0.isOff }) {
                NSLog("[PlaybackViewModel] Found subtitle: %@", firstTrack.displayName)
            }
        }
    }

    // MARK: - Subtitles Management
    public func selectSubtitle(_ track: SubtitleTrack) {
        selectedSubtitle = track
        guard let fileURL = selectedFileURL else { return }

        subtitleSwitchTask?.cancel()
        subtitleSwitchTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                if !track.isOff {
                    self.statusMessage = "Preparing subtitles for \(track.displayName)..."
                }
                let subFileURL = try await SubtitleHelper.prepareSubtitleFile(track: track, for: fileURL)
                guard !Task.isCancelled else { return }

                self.server.setSubtitleFile(path: subFileURL?.path)

                if self.isStreaming, let device = self.selectedDevice {
                    // 1. Temporarily pause position polling to prevent SOAP command collision on TV
                    self.stopPolling()

                    let resumeTime = self.currentTime
                    self.lastSeekTime = Date()
                    let switchStartTime = Date()
                    self.statusMessage = "Updating subtitles to \(track.displayName)..."

                    let safeTrackId = track.isOff ? "off" : track.id
                        .replacingOccurrences(of: "/", with: "_")
                        .replacingOccurrences(of: " ", with: "_")
                        .replacingOccurrences(of: "&", with: "_")
                        .replacingOccurrences(of: "?", with: "_")
                    let version = "\(Int(Date().timeIntervalSince1970))_\(safeTrackId)"
                    let subStreamURL = track.isOff ? nil : self.server.subtitleURL(forTrack: track, version: version)
                    let streamURL = self.server.streamURL(version: version)
                    self.activeStreamURL = streamURL.absoluteString

                    NSLog("[PlaybackViewModel] Switching stream to: %@, sub: %@", streamURL.absoluteString, subStreamURL?.absoluteString ?? "nil")

                    // 2. Command TV to cleanly stop first
                    try? await self.dlna.stop(device: device)
                    try? await Task.sleep(nanoseconds: 200_000_000)

                    guard !Task.isCancelled else { return }

                    // 3. Disconnect existing TCP connection so TV starts fresh
                    self.server.closeActiveConnections()

                    // 4. Update AVTransportURI with new stream & subtitle endpoints
                    try await self.dlna.setAVTransportURI(
                        device: device,
                        mediaURL: streamURL,
                        title: fileURL.deletingPathExtension().lastPathComponent,
                        subtitleURL: subStreamURL
                    )

                    guard !Task.isCancelled else { return }

                    // Small buffer for TV to parse DIDL metadata
                    try await Task.sleep(nanoseconds: 300_000_000)

                    guard !Task.isCancelled else { return }

                    // 5. Command TV to play
                    try await self.dlna.play(device: device)

                    guard !Task.isCancelled else { return }

                    // 6. Set subtitle display state AFTER play has begun (not while stopped!)
                    await self.dlna.setSubtitleDisplay(device: device, enabled: !track.isOff)

                    // 7. Wait for TV to fetch subtitles before issuing Seek
                    if !track.isOff {
                        let maxWaitMs = 1800
                        let pollIntervalMs = 100
                        var waitedMs = 0
                        while waitedMs < maxWaitMs && !Task.isCancelled {
                            if let servedAt = self.server.lastSubtitleServedAt, servedAt >= switchStartTime {
                                NSLog("[PlaybackViewModel] Subtitle confirmed served to TV after %d ms", waitedMs)
                                // Give TV brief settling time to finish parsing downloaded subtitles
                                try? await Task.sleep(nanoseconds: 250_000_000)
                                break
                            }
                            try? await Task.sleep(nanoseconds: UInt64(pollIntervalMs) * 1_000_000)
                            waitedMs += pollIntervalMs
                        }
                    } else {
                        // When subtitles are off, allow video pipeline 500ms to stabilize
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }

                    guard !Task.isCancelled else { return }

                    // 8. Seek back to previous position
                    if resumeTime > 1 {
                        try await self.dlna.seek(device: device, toSeconds: resumeTime)
                        self.lastSeekTime = Date()

                        // Re-assert subtitle display after seek so TV keeps rendering it
                        if !track.isOff {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            await self.dlna.setSubtitleDisplay(device: device, enabled: true)
                        }
                    }

                    self.statusMessage = "Subtitles: \(track.displayName)"

                    // 9. Resume position polling
                    self.startPolling(device: device)
                }
            } catch {
                if !Task.isCancelled {
                    NSLog("[PlaybackViewModel] Failed to update subtitles: %@", error.localizedDescription)
                    self.errorMessage = "Failed to update subtitles: \(error.localizedDescription)"
                    if self.isStreaming, let device = self.selectedDevice {
                        self.startPolling(device: device)
                    }
                }
            }
        }
    }

    public func loadExternalSubtitleFile(url: URL) {
        let track = SubtitleTrack(
            id: "manual_\(url.path)",
            title: url.lastPathComponent,
            language: url.pathExtension.uppercased(),
            streamIndex: nil,
            externalURL: url
        )
        if !availableSubtitles.contains(where: { $0.id == track.id }) {
            availableSubtitles.append(track)
        }
        selectSubtitle(track)
    }

    // MARK: - Streaming
    public func startStreaming() {
        guard !isConnecting && !isStreaming else { return }
        guard let fileURL = selectedFileURL else {
            errorMessage = "Please choose a video file first."
            return
        }
        guard let device = selectedDevice else {
            errorMessage = "No TV device selected. Ensure your TV is on the same Wi-Fi network."
            return
        }

        errorMessage = nil
        isConnecting = true
        statusMessage = "Starting local stream for \(device.displayName)..."
        playbackState = .transitioning

        Task {
            do {
                // 1. Prepare subtitle file if selected
                if !selectedSubtitle.isOff {
                    statusMessage = "Preparing subtitles for \(selectedSubtitle.displayName)..."
                }
                let subFileURL = try await SubtitleHelper.prepareSubtitleFile(track: selectedSubtitle, for: fileURL)
                server.setSubtitleFile(path: subFileURL?.path)

                // 2. Start local byte-range HTTP server
                _ = try server.start(filePath: fileURL.path)
                let safeTrackId = selectedSubtitle.isOff ? "off" : selectedSubtitle.id
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "&", with: "_")
                    .replacingOccurrences(of: "?", with: "_")
                let version = "\(Int(Date().timeIntervalSince1970))_\(safeTrackId)"
                let streamURL = server.streamURL(version: version)
                let subStreamURL = selectedSubtitle.isOff ? nil : server.subtitleURL(forTrack: selectedSubtitle, version: version)
                activeStreamURL = streamURL.absoluteString

                // 3. Instruct TV to load media URI + Subtitles
                statusMessage = "Connecting to \(device.displayName)..."
                try await dlna.setAVTransportURI(
                    device: device,
                    mediaURL: streamURL,
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    subtitleURL: subStreamURL
                )

                // Small delay to allow TV to buffer initial header
                try await Task.sleep(nanoseconds: 500_000_000)

                // 4. Command TV to play
                try await dlna.play(device: device)
                await dlna.setSubtitleDisplay(device: device, enabled: !selectedSubtitle.isOff)

                // Brief pause for TV to initialize media audio subsystem
                try? await Task.sleep(nanoseconds: 300_000_000)

                // Synchronize actual TV volume BEFORE showing playback controls
                await syncVolume(device: device)

                hasStartedPlaying = false
                consecutivePollErrors = 0
                isStreaming = true
                isConnecting = false
                playbackState = .playing
                statusMessage = "Streaming to \(device.displayName)"

                updateSleepPrevention()
                startPolling(device: device)
            } catch {
                server.stop()
                isStreaming = false
                isConnecting = false
                playbackState = .error(error.localizedDescription)
                errorMessage = "Streaming error: \(error.localizedDescription)"
                statusMessage = "Streaming failed"
                if preventSleepOnLidClose {
                    preventSleepOnLidClose = false
                }
                updateSleepPrevention()
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
                updateSleepPrevention()
            } catch {
                errorMessage = "Playback command failed: \(error.localizedDescription)"
            }
        }
    }

    public func stop(reason: String? = nil) {
        stopPolling()
        guard let device = selectedDevice else {
            finishStop(message: reason)
            return
        }

        Task {
            try? await dlna.stop(device: device)
            finishStop(message: reason)
        }
    }

    private func finishStop(message: String? = nil) {
        subtitleSwitchTask?.cancel()
        subtitleSwitchTask = nil
        server.stop()
        isStreaming = false
        isConnecting = false
        playbackState = .stopped
        currentTime = 0
        activeStreamURL = nil
        hasStartedPlaying = false
        consecutivePollErrors = 0

        if let msg = message {
            statusMessage = msg
        } else {
            statusMessage = selectedFileURL != nil ? "Ready to stream" : "Select a video file to begin"
        }

        // Automatically disable lid-close streaming option so laptop won't stay awake
        if preventSleepOnLidClose {
            NSLog("[PlaybackViewModel] Playback stopped. Automatically disabling lid-close sleep prevention to save battery.")
            preventSleepOnLidClose = false
        }
        updateSleepPrevention()
    }

    public func updateSleepPrevention() {
        refreshPowerAndAuthStatus()
        if isStreaming && playbackState == .playing && preventSleepOnLidClose {
            SleepManager.shared.enableSleepPrevention()
        } else {
            SleepManager.shared.disableSleepPrevention()
        }
    }

    private func setupBatterySafeguard() {
        SleepManager.shared.onBatteryCritical = { [weak self] level in
            DispatchQueue.main.async {
                guard let self = self else { return }
                NSLog("[PlaybackViewModel] Received battery critical notification (%d%%)", level)
                self.stop(reason: "Streaming paused: Battery critically low (\(level)%). Sleep restored.")
            }
        }
    }

    public func refreshPowerAndAuthStatus() {
        let status = SleepManager.getPowerStatus()
        isOnBattery = status.isOnBattery
        batteryLevel = status.batteryPercentage
        isBatteryLidSleepAuthorized = SleepManager.checkBatteryAuthorization()
    }

    public func authorizeBatteryLidSleep() {
        let res = SleepManager.installBatteryAuthorization()
        refreshPowerAndAuthStatus()
        if res.success {
            batteryAuthErrorMessage = nil
            if preventSleepOnLidClose {
                updateSleepPrevention()
            }
        } else {
            batteryAuthErrorMessage = res.error
        }
    }

    public func revokeBatteryLidSleep() {
        let res = SleepManager.removeBatteryAuthorization()
        refreshPowerAndAuthStatus()
        if !res.success {
            batteryAuthErrorMessage = res.error
        }
    }

    // MARK: - Seeking
    private var lastSeekTime: Date = Date.distantPast

    public func seek(to seconds: Double) {
        guard let device = selectedDevice, isStreaming else { return }
        let target = max(0, min(duration > 0 ? duration : seconds, seconds))
        currentTime = target
        scrubPosition = target
        lastSeekTime = Date()

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
        scrubPosition = max(0, min(duration > 0 ? duration : position, position))
    }

    public func onScrubbingEnded() {
        isUserScrubbing = false
        seek(to: scrubPosition)
    }

    // MARK: - Volume Control
    private var lastVolumeChangeTime: Date = Date.distantPast
    private var volumePollCycle: Int = 0
    private var isSyncingVolume: Bool = false

    @discardableResult
    public func syncVolume(device: DLNADevice) async -> (volume: Int, isMuted: Bool)? {
        guard device.renderingControlURL != nil else { return nil }
        guard !isSyncingVolume else { return nil }
        isSyncingVolume = true
        defer { isSyncingVolume = false }

        do {
            let currentVol = try await dlna.getVolume(device: device)
            let muted = try await dlna.getMute(device: device)

            let timeSinceUserChange = Date().timeIntervalSince(lastVolumeChangeTime)
            if timeSinceUserChange > 1.5 {
                await MainActor.run {
                    self.volume = Double(currentVol)
                    self.isMuted = muted
                    self.supportsVolumeControl = true
                }
            }
            return (currentVol, muted)
        } catch {
            NSLog("[PlaybackViewModel] Could not sync TV volume: %@", error.localizedDescription)
            return nil
        }
    }

    public func fetchVolume() {
        guard let device = selectedDevice, device.renderingControlURL != nil else {
            supportsVolumeControl = false
            return
        }
        supportsVolumeControl = true
        Task {
            await syncVolume(device: device)
        }
    }

    public func setVolume(_ newVolume: Double) {
        let clamped = max(0, min(100, round(newVolume)))
        volume = clamped
        lastVolumeChangeTime = Date()
        if isMuted && clamped > 0 {
            isMuted = false
        }

        guard let device = selectedDevice, device.renderingControlURL != nil else { return }

        volumeDebounceTask?.cancel()
        volumeDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await dlna.setVolume(device: device, volume: Int(clamped))
            } catch {
                NSLog("[PlaybackViewModel] Failed to set TV volume: %@", error.localizedDescription)
            }
        }
    }

    public func toggleMute() {
        guard let device = selectedDevice, device.renderingControlURL != nil else { return }
        let newMuted = !isMuted
        isMuted = newMuted
        lastVolumeChangeTime = Date()

        Task {
            do {
                try await dlna.setMute(device: device, isMuted: newMuted)
            } catch {
                NSLog("[PlaybackViewModel] Failed to toggle TV mute: %@", error.localizedDescription)
            }
        }
    }

    public func adjustVolume(by delta: Double) {
        setVolume(volume + delta)
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
            consecutivePollErrors = 0

            let timeSinceSeek = Date().timeIntervalSince(lastSeekTime)
            if !isUserScrubbing && timeSinceSeek > 1.2 {
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

            if info.state == .playing || currentTime > 1.0 {
                hasStartedPlaying = true
            }

            // Periodically sync TV volume (every ~2 seconds) if user isn't actively adjusting it
            volumePollCycle += 1
            if volumePollCycle % 2 == 0 {
                let timeSinceVolumeChange = Date().timeIntervalSince(lastVolumeChangeTime)
                if timeSinceVolumeChange > 1.5 {
                    await syncVolume(device: device)
                }
            }

            // Detect finished or stopped playback:
            // 1. Natural end: Duration known, and current time reached end (within 2s)
            let reachedEnd = duration > 5.0 && currentTime >= (duration - 2.0)
            // 2. TV stopped after playing: TV entered stopped/no_media state
            let tvStoppedAfterPlayback = hasStartedPlaying && info.state == .stopped

            if reachedEnd || tvStoppedAfterPlayback {
                NSLog("[PlaybackViewModel] Playback completion detected (tvStopped: %d, reachedEnd: %d, time: %.1f, duration: %.1f)", tvStoppedAfterPlayback ? 1 : 0, reachedEnd ? 1 : 0, currentTime, duration)
                let completionMsg = reachedEnd ? "Playback finished" : "Playback stopped on TV"
                stop(reason: completionMsg)
            }
        } catch {
            consecutivePollErrors += 1
            NSLog("[PlaybackViewModel] Polling error (#%d): %@", consecutivePollErrors, error.localizedDescription)
            // If TV is unreachable for ~6 consecutive seconds (e.g. turned off by remote or network loss), stop session
            if isStreaming && consecutivePollErrors >= 6 {
                NSLog("[PlaybackViewModel] TV unreachable for 6 seconds; assuming TV powered off. Stopping session.")
                stop(reason: "TV disconnected or turned off")
            }
        }
    }
}
