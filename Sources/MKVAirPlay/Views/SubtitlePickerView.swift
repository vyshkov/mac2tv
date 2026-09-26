import SwiftUI
import UniformTypeIdentifiers

public struct SubtitlePickerView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(viewModel.selectedSubtitle.isOff ? Color.primary.opacity(0.05) : Color.cyan.opacity(0.12))
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: viewModel.selectedSubtitle.isOff ?
                                            [.white.opacity(0.35), .white.opacity(0.08)] :
                                            [Color.cyan.opacity(0.5), Color.cyan.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        )

                    Image(systemName: viewModel.selectedSubtitle.isOff ? "captions.bubble" : "captions.bubble.fill")
                        .font(.system(size: 17))
                        .foregroundColor(viewModel.selectedSubtitle.isOff ? .secondary : .cyan)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Subtitles")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                        .textCase(.uppercase)

                    Menu {
                        ForEach(viewModel.availableSubtitles) { track in
                            Button(action: {
                                viewModel.selectSubtitle(track)
                            }) {
                                HStack {
                                    Text(track.displayName)
                                    if viewModel.selectedSubtitle.id == track.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }

                        Divider()

                        Button(action: {
                            viewModel.promptExternalSubtitleFile()
                        }) {
                            Label("Load External Subtitle (.srt, .vtt)...", systemImage: "plus.circle")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(viewModel.selectedSubtitle.displayName)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(viewModel.selectedSubtitle.isOff ? .primary : .cyan)
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

            if !viewModel.selectedSubtitle.isOff {
                LiquidGlassPill("Active", systemImage: "checkmark", tint: .cyan)
            }
        }
        .liquidGlassCard(cornerRadius: 16, padding: 12)
    }
}
