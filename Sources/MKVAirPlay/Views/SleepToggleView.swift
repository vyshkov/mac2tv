import SwiftUI

public struct SleepToggleView: View {
    @ObservedObject var viewModel: PlaybackViewModel

    public init(viewModel: PlaybackViewModel) {
        self.viewModel = viewModel
    }

    private var isActivelyPreventingSleep: Bool {
        viewModel.preventSleepOnLidClose && viewModel.isStreaming && viewModel.playbackState == .playing
    }

    private var subtitleText: String {
        if isActivelyPreventingSleep {
            if viewModel.isLidClosed {
                if viewModel.isOnBattery {
                    return "Active: Lid closed — display backlight off to save battery (15% safety cutoff)"
                } else {
                    return "Active: Lid closed — display backlight off to save battery"
                }
            } else if viewModel.isOnBattery {
                return "Active: streaming on battery (display backlight turns off when lid is closed)"
            } else {
                return "Active: streaming on charger (display backlight turns off when lid is closed)"
            }
        } else if viewModel.preventSleepOnLidClose {
            if viewModel.isBatteryLidSleepAuthorized {
                return "Ready: will stream with lid closed & turn off display backlight"
            } else {
                return "Active on charger; one-time authorization required for battery"
            }
        } else {
            return "Mac will sleep normally when lid is closed"
        }
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                isActivelyPreventingSleep ?
                                    (viewModel.isOnBattery ? Color.green.opacity(0.2) : Color.indigo.opacity(0.22)) :
                                (viewModel.preventSleepOnLidClose ? Color.purple.opacity(0.12) : Color.primary.opacity(0.05))
                            )
                            .frame(width: 38, height: 38)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: isActivelyPreventingSleep ?
                                                (viewModel.isOnBattery ?
                                                    [Color.green.opacity(0.65), Color.teal.opacity(0.3)] :
                                                    [Color.indigo.opacity(0.65), Color.cyan.opacity(0.3)]) :
                                                (viewModel.preventSleepOnLidClose ?
                                                    [Color.purple.opacity(0.55), Color.indigo.opacity(0.2)] :
                                                    [.white.opacity(0.35), .white.opacity(0.08)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.8
                                    )
                            )

                        Image(systemName: viewModel.preventSleepOnLidClose ? (viewModel.isOnBattery ? "battery.100.bolt" : "powersleep") : "moon.zzz")
                            .font(.system(size: 17))
                            .foregroundColor(
                                isActivelyPreventingSleep ?
                                    (viewModel.isOnBattery ? .green : .indigo) :
                                (viewModel.preventSleepOnLidClose ? .purple : .secondary)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Keep streaming when lid is closed")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)

                            if isActivelyPreventingSleep {
                                if viewModel.isLidClosed {
                                    LiquidGlassPill("Lid Closed (Display Off)", tint: .green)
                                } else {
                                    LiquidGlassPill(
                                        viewModel.isOnBattery ? "Active (Battery)" : "Active (AC)",
                                        tint: viewModel.isOnBattery ? .green : .indigo
                                    )
                                }
                            } else if viewModel.preventSleepOnLidClose {
                                if viewModel.isBatteryLidSleepAuthorized {
                                    LiquidGlassPill("Armed (AC + Battery)", tint: .purple)
                                } else {
                                    LiquidGlassPill("Armed (AC only)", tint: .purple)
                                }
                            }
                        }

                        Text(subtitleText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: $viewModel.preventSleepOnLidClose)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            // Inline authorization banner if enabled but not yet authorized for battery
            if viewModel.preventSleepOnLidClose && !viewModel.isBatteryLidSleepAuthorized {
                Divider()
                    .opacity(0.3)
                    .padding(.vertical, 2)

                HStack(spacing: 10) {
                    Image(systemName: "bolt.batteryblock.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Enable streaming on Battery")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("macOS requires a one-time admin authorization for pmset to stream on battery with lid closed.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        viewModel.authorizeBatteryLidSleep()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 10))
                            Text("Authorize")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
                }

                if let error = viewModel.batteryAuthErrorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(error)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .liquidGlassCard(cornerRadius: 16, padding: 12)
    }
}
