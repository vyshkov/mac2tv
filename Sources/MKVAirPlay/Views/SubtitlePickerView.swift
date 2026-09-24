import SwiftUI
import UniformTypeIdentifiers

public struct SubtitlePickerView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.selectedSubtitle.isOff ? "captions.bubble" : "captions.bubble.fill")
                    .font(.system(size: 16))
                    .foregroundColor(viewModel.selectedSubtitle.isOff ? .secondary : .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Subtitles")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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

                        Button(action: openSubtitleFilePicker) {
                            Label("Load External Subtitle (.srt, .vtt)...", systemImage: "plus.circle")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(viewModel.selectedSubtitle.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(viewModel.selectedSubtitle.isOff ? .primary : .accentColor)
                                .lineLimit(1)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(viewModel.selectedFileURL == nil)
                }
            }

            Spacer()

            if !viewModel.selectedSubtitle.isOff {
                Text("Active")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
            }
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
    }

    private func openSubtitleFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt") ?? .plainText,
            UTType(filenameExtension: "vtt") ?? .plainText,
            .plainText
        ]
        panel.prompt = "Select Subtitles"

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadExternalSubtitleFile(url: url)
        }
    }
}
