import SwiftUI

public struct SleepToggleView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    private var isActivelyPreventingSleep: Bool {
        viewModel.preventSleepOnLidClose && viewModel.isStreaming && viewModel.playbackState == .playing
    }

    public var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isActivelyPreventingSleep ? Color.indigo.opacity(0.22) :
                            (viewModel.preventSleepOnLidClose ? Color.purple.opacity(0.12) : Color.primary.opacity(0.05))
                        )
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: isActivelyPreventingSleep ?
                                            [Color.indigo.opacity(0.65), Color.cyan.opacity(0.3)] :
                                            (viewModel.preventSleepOnLidClose ?
                                                [Color.purple.opacity(0.55), Color.indigo.opacity(0.2)] :
                                                [.white.opacity(0.35), .white.opacity(0.08)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        )

                    Image(systemName: viewModel.preventSleepOnLidClose ? "powersleep" : "moon.zzz")
                        .font(.system(size: 17))
                        .foregroundColor(
                            isActivelyPreventingSleep ? .indigo :
                            (viewModel.preventSleepOnLidClose ? .purple : .secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Keep streaming when lid is closed")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)

                        if isActivelyPreventingSleep {
                            LiquidGlassPill("Active", tint: .indigo)
                        } else if viewModel.preventSleepOnLidClose {
                            LiquidGlassPill("Armed", tint: .purple)
                        }
                    }

                    Text(
                        isActivelyPreventingSleep ?
                            "Active: streaming with lid closed (auto-disables when finished)" :
                            (viewModel.preventSleepOnLidClose ?
                                "Keeps awake during playback only; auto-disables when done" :
                                "Mac will sleep normally when lid is closed")
                    )
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: $viewModel.preventSleepOnLidClose)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .liquidGlassCard(cornerRadius: 16, padding: 12)
    }
}
