import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel = PlaybackViewModel()

    public init() {}

    public var body: some View {
        ZStack {
            // 1. Native macOS Translucent Blur (behind-window vibrancy)
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()

            // 2. Refractive Ambient Color Bleed (Liquid Glass chromatic depth)
            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(Color(red: 0.1, green: 0.5, blue: 1.0).opacity(0.12))
                        .frame(width: 320, height: 320)
                        .blur(radius: 80)
                        .offset(x: -proxy.size.width * 0.25, y: -proxy.size.height * 0.25)

                    Circle()
                        .fill(Color(red: 0.5, green: 0.2, blue: 0.9).opacity(0.10))
                        .frame(width: 280, height: 280)
                        .blur(radius: 70)
                        .offset(x: proxy.size.width * 0.3, y: proxy.size.height * 0.2)
                }
            }
            .ignoresSafeArea()

            // 3. Flexible Glass Layout (Flex: 1 center component, full window coverage)
            GeometryReader { windowProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Top Space for macOS Window Traffic Light Controls
                        Color.clear
                            .frame(height: 12)

                        // Liquid Glass Header
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(LinearGradient(
                                        colors: [Color.cyan, Color.blue, Color.indigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.7), .white.opacity(0.2)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .shadow(color: Color.blue.opacity(0.35), radius: 8, x: 0, y: 3)

                                Image(systemName: "tv.and.mediabox")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("MKVAirPlay")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))

                                Text("Stream MKV to Smart TV via DLNA & AirPlay")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Status Pill Badge
                            LiquidGlassPill(
                                viewModel.isStreaming ? "Streaming" : (viewModel.selectedDevice != nil ? "Ready" : "Searching"),
                                systemImage: viewModel.isStreaming ? "dot.radiowaves.left.and.right" : (viewModel.selectedDevice != nil ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right"),
                                tint: viewModel.isStreaming ? .green : (viewModel.selectedDevice != nil ? .cyan : .orange)
                            )
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2)

                        // Target TV Selector
                        DevicePickerView(viewModel: viewModel)

                        // Center Flexible Component: Drop Zone / Media Deck (Flex: 1)
                        DropZoneView(viewModel: viewModel)

                        // Subtitle Settings (Embedded & External)
                        SubtitlePickerView(viewModel: viewModel)

                        // Sleep Prevention Settings
                        SleepToggleView(viewModel: viewModel)

                        // Playback Controls / Stream Action
                        PlaybackControlsView(viewModel: viewModel)

                        // Error Banner (Liquid Red Glass)
                        if let error = viewModel.errorMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.red)

                                Text(error)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.red)
                                    .lineLimit(2)

                                Spacer()

                                Button("Dismiss") {
                                    viewModel.errorMessage = nil
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                            }
                            .liquidGlassCard(cornerRadius: 14, padding: 12, glow: .red)
                        }

                        // Flexible bottom spacer to push footer to the very bottom
                        Spacer(minLength: 4)

                        // Footer Info & Remote Hint (Liquid Glass Bar)
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "remote.fill")
                                    .font(.system(size: 11))
                                Text("TV Magic Remote supported natively")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(.secondary)

                            Spacer()

                            if let url = viewModel.activeStreamURL {
                                Text(url)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text(viewModel.statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .frame(minWidth: windowProxy.size.width, minHeight: windowProxy.size.height)
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 540, maxWidth: 650, minHeight: 680, idealHeight: 740)
    }
}
