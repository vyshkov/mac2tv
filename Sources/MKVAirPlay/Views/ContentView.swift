import SwiftUI

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

final class WindowAccessorView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            onWindow?(window)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.onWindow = onWindow
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window {
            onWindow(window)
        }
    }
}

@MainActor
public struct ContentView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    public init() {
        self.viewModel = PlaybackViewModel.shared
    }

    public var body: some View {
        ZStack(alignment: .top) {
            WindowAccessor { window in
                AppDelegate.shared?.configureWindow(window)
            }
            .frame(width: 0, height: 0)

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

            // 3. Compact Glass Layout (Content-hugging vertical stack)
            VStack(spacing: 12) {
                // Top Space for macOS Window Traffic Light Controls
                Color.clear
                    .frame(height: 20)

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
                        viewModel.isStreaming ? "Streaming" : (viewModel.isConnecting ? "Buffering" : (viewModel.selectedDevice != nil ? "Ready" : "Searching")),
                        systemImage: viewModel.isStreaming ? "dot.radiowaves.left.and.right" : (viewModel.isConnecting ? "antenna.radiowaves.left.and.right" : (viewModel.selectedDevice != nil ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")),
                        tint: viewModel.isStreaming ? .green : (viewModel.isConnecting ? .blue : (viewModel.selectedDevice != nil ? .cyan : .orange))
                    )
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)

                // Target TV Selector
                DevicePickerView(viewModel: viewModel)

                // Center Component: Drop Zone / Media Deck
                DropZoneView(viewModel: viewModel)

                // Subtitle Settings (Only shown when a file is selected and not streaming)
                if viewModel.selectedFileURL != nil && !viewModel.isStreaming {
                    SubtitlePickerView(viewModel: viewModel)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

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

                    if viewModel.isStreaming, let url = viewModel.activeStreamURL {
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
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightPreferenceKey.self, value: geo.size.height)
                }
            )
        }
        .onPreferenceChange(ContentHeightPreferenceKey.self) { newHeight in
            guard newHeight > 100 else { return }
            let target = ceil(newHeight)
            if abs(viewModel.windowContentHeight - target) > 1 {
                viewModel.windowContentHeight = target
            }
            AppDelegate.shared?.updateWindowHeight(target)
        }
        .frame(width: 520, height: viewModel.windowContentHeight)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.selectedFileURL)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isStreaming)
    }
}
