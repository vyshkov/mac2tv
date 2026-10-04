import SwiftUI
import UniformTypeIdentifiers

public struct AudioPickerView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(viewModel.selectedAudioTrack == nil ? Color.primary.opacity(0.05) : Color.purple.opacity(0.12))
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: viewModel.selectedAudioTrack == nil ?
                                            [.white.opacity(0.35), .white.opacity(0.08)] :
                                            [Color.purple.opacity(0.5), Color.purple.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        )

                    Image(systemName: viewModel.selectedAudioTrack == nil ? "speaker.slash" : "speaker.wave.2.fill")
                        .font(.system(size: 16))
                        .foregroundColor(viewModel.selectedAudioTrack == nil ? .secondary : .purple)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Audio Track")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                        .textCase(.uppercase)

                    Menu {
                        if viewModel.availableAudioTracks.isEmpty {
                            Text("Default Audio Track")
                        } else {
                            ForEach(viewModel.availableAudioTracks) { track in
                                Button(action: {
                                    viewModel.selectAudioTrack(track)
                                }) {
                                    HStack {
                                        Text(track.displayName)
                                        if viewModel.selectedAudioTrack?.id == track.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }

                        Divider()

                        Button(action: {
                            viewModel.promptExternalAudioFile()
                        }) {
                            Label("Load External Audio Track...", systemImage: "plus.circle")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(viewModel.selectedAudioTrack?.displayName ?? (viewModel.availableAudioTracks.isEmpty ? "Default Audio" : "Select Audio Track"))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(viewModel.selectedAudioTrack == nil ? .secondary : .primary)
                                .lineLimit(1)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(viewModel.selectedFileURL == nil || viewModel.isConnecting)
                }
            }

            Spacer()

            if let track = viewModel.selectedAudioTrack {
                let badgeText = track.layoutBadge ?? track.codec?.uppercased() ?? "Active"
                LiquidGlassPill(badgeText, systemImage: "checkmark", tint: .purple)
            }
        }
        .liquidGlassCard(cornerRadius: 16, padding: 12)
    }
}
