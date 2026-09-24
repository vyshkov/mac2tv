import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel = PlaybackViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 18) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.cyan, Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)

                    Image(systemName: "tv.and.mediabox")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("MKVAirPlay")
                        .font(.system(size: 16, weight: .bold))

                    Text("Stream MKV to Smart TV via DLNA")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Target TV Selector
            DevicePickerView(viewModel: viewModel)

            // Drop Zone / File Picker
            DropZoneView(viewModel: viewModel)

            // Playback Controls / Stream Action
            PlaybackControlsView(viewModel: viewModel)

            // Error Banner (if present)
            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.errorMessage = nil
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
            }

            Spacer(minLength: 0)

            // Footer Info & Remote Hint
            VStack(spacing: 6) {
                Divider()

                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "remote.fill")
                            .font(.system(size: 11))
                        Text("TV Magic Remote supported natively")
                            .font(.system(size: 11))
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
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 520, maxWidth: 640, minHeight: 460, idealHeight: 520)
    }
}
