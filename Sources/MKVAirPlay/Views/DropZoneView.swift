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
                if viewModel.isStreaming {
                    // Compact Streaming File Card
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color.indigo.opacity(0.85), Color.cyan.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: 1
                                        )
                                )

                            Image(systemName: "film.stack.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(fileURL.lastPathComponent)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            HStack(spacing: 6) {
                                LiquidGlassPill(viewModel.selectedFileFormat, tint: .cyan)

                                if !viewModel.selectedFileSize.isEmpty {
                                    Text(viewModel.selectedFileSize)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Spacer()

                        Button(action: openFilePicker) {
                            Text("Change")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(LiquidGlassButtonStyle(isProminent: false))
                        .disabled(viewModel.isConnecting)
                    }
                    .liquidGlassCard(cornerRadius: 16, padding: 12, glow: .indigo)
                } else {
                    // Expanded Media Card (Flex: 1)
                    VStack(spacing: 14) {
                        Spacer(minLength: 8)

                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color.indigo.opacity(0.85), Color.cyan.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 64, height: 64)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: 1.2
                                        )
                                )
                                .shadow(color: Color.indigo.opacity(0.35), radius: 10, x: 0, y: 4)

                            Image(systemName: "film.stack.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }

                        VStack(spacing: 6) {
                            Text(fileURL.lastPathComponent)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)

                            HStack(spacing: 6) {
                                LiquidGlassPill(viewModel.selectedFileFormat, tint: .cyan)

                                if !viewModel.selectedFileSize.isEmpty {
                                    Text(viewModel.selectedFileSize)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Button(action: openFilePicker) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11))
                                Text("Change Video")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(LiquidGlassButtonStyle(isProminent: false))
                        .disabled(viewModel.isConnecting)

                        Spacer(minLength: 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
                    .liquidGlassCard(cornerRadius: 18, padding: 14, glow: .indigo)
                }
            } else {
                // Empty Drop Target (Frosted Glass Container, Flex: 1)
                Button(action: openFilePicker) {
                    VStack(spacing: 14) {
                        Spacer(minLength: 10)

                        ZStack {
                            Circle()
                                .fill(viewModel.isDropTargeted ? Color.cyan.opacity(0.25) : Color.primary.opacity(0.04))
                                .frame(width: 68, height: 68)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: viewModel.isDropTargeted ?
                                                    [Color.cyan, Color.indigo] :
                                                    [Color.white.opacity(0.4), Color.white.opacity(0.08)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                             lineWidth: 1.2
                                        )
                                )
                                .shadow(color: viewModel.isDropTargeted ? Color.cyan.opacity(0.4) : Color.clear, radius: 12)

                            Image(systemName: viewModel.isDropTargeted ? "arrow.down.circle.fill" : "play.rectangle.on.rectangle")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundColor(viewModel.isDropTargeted ? .cyan : .primary.opacity(0.75))
                                .scaleEffect(viewModel.isDropTargeted ? 1.15 : 1.0)
                                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: viewModel.isDropTargeted)
                        }

                        VStack(spacing: 4) {
                            Text("Drag & Drop MKV or Video File")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)

                            Text("or click to browse from your Mac")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Text("Supports MKV, MP4, MOV, WebM, AVI")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))

                        Spacer(minLength: 10)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)

                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: viewModel.isDropTargeted ?
                                            [Color.cyan.opacity(0.12), Color.indigo.opacity(0.08)] :
                                            [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                viewModel.isDropTargeted ?
                                    Color.cyan :
                                    Color.white.opacity(0.25),
                                style: StrokeStyle(lineWidth: viewModel.isDropTargeted ? 2 : 1.2, dash: viewModel.isDropTargeted ? [] : [7, 5])
                            )
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isConnecting)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $viewModel.isDropTargeted) { providers in
            guard !viewModel.isConnecting else { return false }
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
        guard !viewModel.isConnecting else { return }
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
