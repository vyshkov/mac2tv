import SwiftUI

public struct DevicePickerView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 12) {
            // TV Icon & Status Indicator
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "tv.badge.wifi")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1.5)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Screen")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .foregroundColor(.primary)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            Spacer()

            // Rescan Button
            Button(action: {
                viewModel.refreshDiscovery()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(viewModel.isSearchingDevices ? 360 : 0))
                    .animation(viewModel.isSearchingDevices ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isSearchingDevices)
            }
            .buttonStyle(.plain)
            .help("Refresh TV Devices")
            .padding(6)
            .background(Circle().fill(Color.primary.opacity(0.05)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .sheet(isPresented: $viewModel.showingManualIPSheet) {
            manualIPModal
        }
    }

    private var statusColor: Color {
        if viewModel.selectedDevice != nil {
            return .green
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
