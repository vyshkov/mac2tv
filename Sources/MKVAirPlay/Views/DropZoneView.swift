import SwiftUI
import UniformTypeIdentifiers

public struct DropZoneView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let fileURL = viewModel.selectedFileURL {
                // File Selected Card
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.indigo.opacity(0.8), Color.purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 54, height: 54)

                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(fileURL.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 8) {
                            Text(viewModel.selectedFileFormat)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)

                            if !viewModel.selectedFileSize.isEmpty {
                                Text(viewModel.selectedFileSize)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Button(action: openFilePicker) {
                        Text("Change")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            } else {
                // Empty Drop Target
                Button(action: openFilePicker) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(viewModel.isDropTargeted ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                                .frame(width: 64, height: 64)

                            Image(systemName: viewModel.isDropTargeted ? "arrow.down.circle.fill" : "play.rectangle.on.rectangle")
                                .font(.system(size: 30))
                                .foregroundColor(viewModel.isDropTargeted ? .accentColor : .secondary)
                                .scaleEffect(viewModel.isDropTargeted ? 1.15 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.isDropTargeted)
                        }

                        VStack(spacing: 4) {
                            Text("Drag & Drop MKV or Video File")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text("or click to browse from your Mac")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Text("Supports MKV, MP4, MOV, WebM, AVI")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(viewModel.isDropTargeted ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                viewModel.isDropTargeted ? Color.accentColor : Color.primary.opacity(0.15),
                                style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $viewModel.isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async {
                        viewModel.selectFile(url: url)
                    }
                }
            }
            return true
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "mkv") ?? .movie,
            .mpeg4Movie,
            .quickTimeMovie,
            .movie,
            .video
        ]
        panel.prompt = "Select Video"

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.selectFile(url: url)
        }
    }
}
