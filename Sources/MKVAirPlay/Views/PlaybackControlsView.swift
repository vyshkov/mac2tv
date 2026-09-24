import SwiftUI

public struct PlaybackControlsView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            if !viewModel.isStreaming {
                // Stream to TV Button
                Button(action: {
                    viewModel.startStreaming()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "tv.badge.wifi")
                            .font(.system(size: 16, weight: .bold))
                        Text(viewModel.selectedDevice != nil ? "Stream to \(viewModel.selectedDevice!.displayName)" : "Stream to TV")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(viewModel.selectedFileURL == nil || viewModel.selectedDevice == nil)
                .help(viewModel.selectedFileURL == nil ? "Select a video file first" : (viewModel.selectedDevice == nil ? "Select a TV device" : "Stream to TV"))
            } else {
                // Active Playback Controls Deck
                VStack(spacing: 14) {
                    // Status Badge
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.playbackState.color)
                                .frame(width: 8, height: 8)

                            Text(viewModel.playbackState.title)
                                .font(.caption.bold())
                                .foregroundColor(viewModel.playbackState.color)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(viewModel.playbackState.color.opacity(0.12))
                        .cornerRadius(20)

                        Spacer()

                        if let target = viewModel.selectedDevice {
                            Text(target.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Scrubber Bar
                    VStack(spacing: 4) {
                        CustomScrubber(
                            value: viewModel.isUserScrubbing ? $viewModel.scrubPosition : Binding(
                                get: { viewModel.currentTime },
                                set: { _ in }
                            ),
                            inRange: 0...(viewModel.duration > 0 ? viewModel.duration : 1),
                            onEditingChanged: { editing in
                                if editing {
                                    viewModel.onScrubbingBegan()
                                } else {
                                    viewModel.onScrubbingEnded()
                                }
                            }
                        )

                        HStack {
                            Text(TimeHelper.format(seconds: viewModel.isUserScrubbing ? viewModel.scrubPosition : viewModel.currentTime))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(TimeHelper.format(seconds: viewModel.duration))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Transport Buttons Deck
                    HStack(spacing: 20) {
                        // -60s
                        Button(action: { viewModel.skip(by: -60) }) {
                            Text("-1m")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                        .help("Skip backward 1 minute")

                        // -10s
                        Button(action: { viewModel.skip(by: -10) }) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 18))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                        .help("Skip backward 10 seconds")

                        // Play / Pause Main Button
                        Button(action: { viewModel.togglePlayPause() }) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .frame(width: 52, height: 52)
                                    .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 3)

                                Image(systemName: viewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                                    .offset(x: viewModel.playbackState == .playing ? 0 : 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.playbackState == .playing ? "Pause" : "Play")

                        // +10s
                        Button(action: { viewModel.skip(by: 10) }) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 18))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                        .help("Skip forward 10 seconds")

                        // +60s
                        Button(action: { viewModel.skip(by: 60) }) {
                            Text("+1m")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                        .help("Skip forward 1 minute")

                        Spacer()

                        // Stop Button
                        Button(action: { viewModel.stop() }) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14))
                                .frame(width: 34, height: 34)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .background(Circle().fill(Color.red.opacity(0.1)))
                        .help("Stop Streaming")
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Custom Scrubber Slider
struct CustomScrubber: View {
    @Binding var value: Double
    let inRange: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        Slider(
            value: $value,
            in: inRange,
            onEditingChanged: onEditingChanged
        )
        .accentColor(.accentColor)
    }
}
