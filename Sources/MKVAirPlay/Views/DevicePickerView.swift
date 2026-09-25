import SwiftUI

public struct DevicePickerView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 14) {
            // TV Icon & Status Indicator in Glass Squircle
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                        )

                    Image(systemName: "tv.badge.wifi")
                        .font(.system(size: 18))
                        .foregroundColor(.primary.opacity(0.9))

                    // Status Beacon
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: statusColor.opacity(0.8), radius: 3)
                        .offset(x: 10, y: 10)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Target Screen")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                        .textCase(.uppercase)

                    Menu {
                        if viewModel.discoveredDevices.isEmpty {
                            Text("Searching for TVs...")
                        } else {
                            ForEach(viewModel.discoveredDevices) { device in
                                Button(action: {
                                    viewModel.selectedDevice = device
                                }) {
                                    HStack {
                                        Text(device.displayName)
                                        if viewModel.selectedDevice?.id == device.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }

                        Divider()

                        Button(action: {
                            viewModel.manualIPText = viewModel.selectedDevice?.baseURL.host ?? "192.168.0.196"
                            viewModel.showingManualIPSheet = true
                        }) {
                            Label("Add TV by IP Address...", systemImage: "network")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(viewModel.selectedDevice?.displayName ?? "Scanning for TVs...")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .foregroundColor(.primary)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(viewModel.isConnecting || viewModel.isStreaming)
                }
            }

            Spacer()

            // Rescan Glass Button
            Button(action: {
                viewModel.refreshDiscovery()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary.opacity(0.8))
                    .rotationEffect(.degrees(viewModel.isSearchingDevices ? 360 : 0))
                    .animation(viewModel.isSearchingDevices ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isSearchingDevices)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isConnecting || viewModel.isStreaming)
            .help("Refresh TV Devices")
        }
        .liquidGlassCard(cornerRadius: 16, padding: 12)
        .sheet(isPresented: $viewModel.showingManualIPSheet) {
            manualIPModal
        }
    }

    private var statusColor: Color {
        if viewModel.isStreaming {
            return .green
        } else if viewModel.isConnecting {
            return .blue
        } else if viewModel.selectedDevice != nil {
            return .cyan
        } else if viewModel.isSearchingDevices {
            return .orange
        } else {
            return .gray
        }
    }

    private var manualIPModal: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect to TV by IP")
                .font(.headline)

            Text("Enter your Smart TV's IP address (e.g. 192.168.0.196):")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("192.168.0.196", text: $viewModel.manualIPText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.showingManualIPSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Connect") {
                    let trimmed = viewModel.manualIPText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        viewModel.addManualDevice(ipOrHost: trimmed)
                    }
                    viewModel.showingManualIPSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
