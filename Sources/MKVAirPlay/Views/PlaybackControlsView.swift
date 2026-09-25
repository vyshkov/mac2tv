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

                            Text(viewModel.selectedDevice != nil ? "Buffering to \(viewModel.selectedDevice!.displayName)..." : "Buffering stream...")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
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
