import SwiftUI

public struct PlaybackControlsView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            if !viewModel.isStreaming {
                // Stream to TV Button (Liquid Glass Prominent Pill)
                Button(action: {
                    viewModel.startStreaming()
                }) {
                    HStack(spacing: 10) {
                        if viewModel.isConnecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.85)
                                .frame(width: 18, height: 18)

                            Text(viewModel.statusMessage)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        } else {
                            Image(systemName: "tv.badge.wifi")
                                .font(.system(size: 16, weight: .bold))
                            Text(viewModel.selectedDevice != nil ? "Stream to \(viewModel.selectedDevice!.displayName)" : "Stream to TV")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(.white)
                    .bufferingShimmer(isActive: viewModel.isConnecting)
                }
                .buttonStyle(LiquidGlassButtonStyle(isProminent: true, tint: .cyan, isBuffering: viewModel.isConnecting))
                .disabled(viewModel.selectedFileURL == nil || viewModel.selectedDevice == nil || viewModel.isConnecting)
                .opacity(viewModel.selectedFileURL == nil || viewModel.selectedDevice == nil ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: viewModel.isConnecting)
                .help(viewModel.selectedFileURL == nil ? "Select a video file first" : (viewModel.selectedDevice == nil ? "Select a TV device" : (viewModel.isConnecting ? "Buffering stream..." : "Stream to TV")))
            } else {
                // Active Playback Controls Deck (Liquid Glass)
                VStack(spacing: 16) {
                    // Status Header
                    HStack {
                        LiquidGlassPill(
                            viewModel.playbackState.title,
                            systemImage: viewModel.playbackState == .playing ? "play.circle.fill" : "pause.circle.fill",
                            tint: viewModel.playbackState.color
                        )

                        Spacer()

                        if let target = viewModel.selectedDevice {
                            HStack(spacing: 5) {
                                Image(systemName: "tv")
                                    .font(.system(size: 10))
                                Text(target.displayName)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(.secondary)
                        }
                    }

                    // Scrubber Bar
                    VStack(spacing: 6) {
                        TimelineScrubber(viewModel: viewModel)

                        HStack {
                            Text(TimeHelper.format(seconds: viewModel.isUserScrubbing ? viewModel.scrubPosition : viewModel.currentTime))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(TimeHelper.format(seconds: viewModel.duration))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Transport Buttons Deck (Horizontally Centered with Trailing Stop)
                    ZStack {
                        // Centered Playback Controls Deck
                        HStack(spacing: 16) {
                            // -60s Glass Button
                            Button(action: { viewModel.skip(by: -60) }) {
                                Text("-1m")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Skip backward 1 minute")

                            // -10s Glass Button
                            Button(action: { viewModel.skip(by: -10) }) {
                                Image(systemName: "gobackward.10")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Skip backward 10 seconds")

                            // Play / Pause Main Liquid Orb
                            Button(action: { viewModel.togglePlayPause() }) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(
                                            colors: [Color(red: 0.15, green: 0.58, blue: 1.0), Color(red: 0.35, green: 0.35, blue: 0.95)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        .frame(width: 52, height: 52)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom),
                                                    lineWidth: 1.2
                                                )
                                        )
                                        .shadow(color: Color.blue.opacity(0.45), radius: 12, x: 0, y: 4)

                                    Image(systemName: viewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                        .offset(x: viewModel.playbackState == .playing ? 0 : 2)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(viewModel.playbackState == .playing ? "Pause" : "Play")

                            // +10s Glass Button
                            Button(action: { viewModel.skip(by: 10) }) {
                                Image(systemName: "goforward.10")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Skip forward 10 seconds")

                            // +60s Glass Button
                            Button(action: { viewModel.skip(by: 60) }) {
                                Text("+1m")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Skip forward 1 minute")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        // Leading Volume Button (Symmetric with Stop Button)
                        HStack {
                            VolumeControlView(viewModel: viewModel)
                            Spacer()
                        }

                        // Trailing Stop Button
                        HStack {
                            Spacer()

                            Button(action: { viewModel.stop() }) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.red)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle()
                                            .fill(Color.red.opacity(0.12))
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                LinearGradient(colors: [Color.red.opacity(0.5), Color.red.opacity(0.15)], startPoint: .top, endPoint: .bottom),
                                                lineWidth: 0.8
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Stop Streaming")
                        }
                    }
                    .padding(.top, 4)
                }
                .liquidGlassCard(cornerRadius: 18, padding: 16, glow: .blue)
            }
        }
    }
}

// MARK: - Interactive Timeline Scrubber (Click & Drag to Seek)
public struct TimelineScrubber: View {
    @ObservedObject var viewModel: PlaybackViewModel

    private var progress: Double {
        guard viewModel.duration > 0 else { return 0 }
        let time = viewModel.isUserScrubbing ? viewModel.scrubPosition : viewModel.currentTime
        return max(0, min(1, time / viewModel.duration))
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let trackHeight: CGFloat = 6
            let thumbDiameter: CGFloat = 16

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: trackHeight)

                // Progress Fill Track with Liquid Gradient
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color.cyan, Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(0, min(totalWidth, totalWidth * CGFloat(progress))), height: trackHeight)
                    .shadow(color: Color.cyan.opacity(0.35), radius: 3, x: 0, y: 1)

                // Scrubber Thumb Handle (Glossy Glass Orb)
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: Color.black.opacity(0.20), radius: 3, x: 0, y: 1.5)
                    .overlay(
                        Circle().strokeBorder(Color.blue, lineWidth: 2)
                    )
                    .offset(x: max(0, min(totalWidth - thumbDiameter, totalWidth * CGFloat(progress) - thumbDiameter / 2)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle()) // Makes the whole 22pt high area interactive
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let locationX = max(0, min(totalWidth, gesture.location.x))
                        let pct = totalWidth > 0 ? (locationX / totalWidth) : 0
                        let target = Double(pct) * max(1, viewModel.duration)

                        if !viewModel.isUserScrubbing {
                            viewModel.onScrubbingBegan()
                        }
                        viewModel.onScrubbingChanged(to: target)
                    }
                    .onEnded { gesture in
                        let locationX = max(0, min(totalWidth, gesture.location.x))
                        let pct = totalWidth > 0 ? (locationX / totalWidth) : 0
                        let target = Double(pct) * max(1, viewModel.duration)

                        viewModel.onScrubbingChanged(to: target)
                        viewModel.onScrubbingEnded()
                    }
            )
        }
        .frame(height: 24)
    }
}

// MARK: - Volume Control Button & Popover
public struct VolumeControlView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    private var speakerIcon: String {
        if viewModel.isMuted || viewModel.volume == 0 {
            return "speaker.slash.fill"
        } else if viewModel.volume < 33 {
            return "speaker.wave.1.fill"
        } else if viewModel.volume < 66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private var speakerColor: Color {
        if !viewModel.supportsVolumeControl {
            return .secondary.opacity(0.6)
        } else if viewModel.isMuted {
            return .orange
        } else if viewModel.volume == 0 {
            return .secondary
        } else {
            return .cyan
        }
    }

    public var body: some View {
        Button(action: {
            if viewModel.supportsVolumeControl {
                viewModel.fetchVolume()
                viewModel.showingVolumePopover.toggle()
            }
        }) {
            Image(systemName: speakerIcon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(speakerColor)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(speakerColor.opacity(0.12))
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [speakerColor.opacity(0.5), speakerColor.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.supportsVolumeControl)
        .opacity(viewModel.supportsVolumeControl ? 1.0 : 0.4)
        .popover(isPresented: $viewModel.showingVolumePopover, arrowEdge: .top) {
            VolumePopoverContent(viewModel: viewModel)
        }
        .contextMenu {
            if viewModel.supportsVolumeControl {
                Button("Volume Up (+1)") { viewModel.adjustVolume(by: 1) }
                Button("Volume Down (-1)") { viewModel.adjustVolume(by: -1) }
                Divider()
                Button(viewModel.isMuted ? "Unmute TV" : "Mute TV") {
                    viewModel.toggleMute()
                }
            }
        }
        .help(viewModel.supportsVolumeControl ?
            "TV Volume: \(Int(viewModel.volume))\(viewModel.isMuted ? " (Muted)" : "") — Click to adjust" :
            "Volume control not supported by this TV"
        )
    }
}

// MARK: - Volume Popover Content
public struct VolumePopoverContent: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public var body: some View {
        VStack(spacing: 12) {
            // Header Row: TV name + Volume Point Value
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.cyan)
                    Text(viewModel.selectedDevice?.displayName ?? "TV Volume")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }

                Spacer()

                Text(viewModel.isMuted ? "Muted" : "\(Int(viewModel.volume))")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(viewModel.isMuted ? .orange : .cyan)
            }

            // Interactive Volume Slider Row with - and + (by 1 point)
            HStack(spacing: 8) {
                // Minus button (-1 point)
                Button(action: {
                    viewModel.adjustVolume(by: -1)
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .help("Decrease volume by 1")

                // Custom Liquid Glass Volume Slider
                VolumeSlider(viewModel: viewModel)

                // Plus button (+1 point)
                Button(action: {
                    viewModel.adjustVolume(by: 1)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .help("Increase volume by 1")
            }
        }
        .padding(14)
        .frame(width: 240)
        .onAppear {
            viewModel.fetchVolume()
        }
    }
}

// MARK: - Interactive Volume Slider
public struct VolumeSlider: View {
    @ObservedObject var viewModel: PlaybackViewModel

    private var progress: Double {
        if viewModel.isMuted { return 0 }
        return max(0, min(1, viewModel.volume / 100.0))
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let trackHeight: CGFloat = 6
            let thumbDiameter: CGFloat = 16

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: trackHeight)

                // Fill Track
                Capsule()
                    .fill(LinearGradient(
                        colors: viewModel.isMuted ?
                            [Color.orange.opacity(0.6), Color.orange] :
                            [Color.cyan, Color.blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(0, min(totalWidth, totalWidth * CGFloat(progress))), height: trackHeight)

                // Thumb Orb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: Color.black.opacity(0.20), radius: 2, x: 0, y: 1)
                    .overlay(
                        Circle().strokeBorder(viewModel.isMuted ? Color.orange : Color.cyan, lineWidth: 2)
                    )
                    .offset(x: max(0, min(totalWidth - thumbDiameter, totalWidth * CGFloat(progress) - thumbDiameter / 2)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let locationX = max(0, min(totalWidth, gesture.location.x))
                        let pct = totalWidth > 0 ? (locationX / totalWidth) : 0
                        viewModel.setVolume(Double(pct) * 100.0)
                    }
            )
        }
        .frame(height: 20)
    }
}
