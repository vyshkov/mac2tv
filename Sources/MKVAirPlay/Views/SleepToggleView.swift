import SwiftUI

public struct SleepToggleView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.preventSleepOnLidClose ? "powersleep" : "moon.zzz")
                    .font(.system(size: 15))
                    .foregroundColor(viewModel.preventSleepOnLidClose ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep streaming when lid is closed")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text("Prevents sleep while allowing the display to turn off")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: $viewModel.preventSleepOnLidClose)
                .toggleStyle(.switch)
                .labelsHidden()
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
}
