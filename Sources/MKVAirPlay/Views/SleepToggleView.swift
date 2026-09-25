import SwiftUI

public struct SleepToggleView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(viewModel.preventSleepOnLidClose ? Color.indigo.opacity(0.15) : Color.primary.opacity(0.05))
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: viewModel.preventSleepOnLidClose ?
                                            [Color.indigo.opacity(0.55), Color.purple.opacity(0.2)] :
                                            [.white.opacity(0.35), .white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        )

                    Image(systemName: viewModel.preventSleepOnLidClose ? "powersleep" : "moon.zzz")
                        .font(.system(size: 17))
                        .foregroundColor(viewModel.preventSleepOnLidClose ? .indigo : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Keep streaming when lid is closed")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)

                        if viewModel.preventSleepOnLidClose {
                            LiquidGlassPill("Active", tint: .indigo)
                        }
                    }

                    Text("Prevents sleep while allowing the display to turn off")
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
