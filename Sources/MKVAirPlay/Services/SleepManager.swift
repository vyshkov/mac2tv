import Foundation
import IOKit.pwr_mgt

public final class SleepManager: @unchecked Sendable {
    public static let shared = SleepManager()

    private var assertionID: IOPMAssertionID = 0
    private var networkAssertionID: IOPMAssertionID = 0
    private var activityToken: NSObjectProtocol?
    private var caffeinateProcess: Process?

    public private(set) var isSleepPrevented: Bool = false

    private init() {}

    public func enableSleepPrevention(reason: String = "MKVAirPlay Streaming MKV to Smart TV") {
        guard !isSleepPrevented else { return }
        isSleepPrevented = true

        // 1. ProcessInfo Activity: prevents idle system sleep while allowing display sleep
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: reason
        )

        // 2. IOKit Prevent User Idle System Sleep (Display can sleep, CPU/Network stays awake)
        let type = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        _ = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        // 3. IOKit Network Client Active Assertion
        let netType = "NetworkClientActive" as CFString
        _ = IOPMAssertionCreateWithName(
            netType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MKVAirPlay Active Streaming Server" as CFString,
            &networkAssertionID
        )

        // 4. Background caffeinate process: -i (idle sleep), -s (system sleep), -m (disk idle)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        proc.arguments = ["-i", "-s", "-m"]
        do {
            try proc.run()
            caffeinateProcess = proc
        } catch {
            NSLog("[SleepManager] Could not spawn caffeinate: %@", error.localizedDescription)
        }

        NSLog("[SleepManager] Sleep prevention active. Mac will not sleep when lid is closed.")
    }

    public func disableSleepPrevention() {
        guard isSleepPrevented else { return }
        isSleepPrevented = false

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }

        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }

        if networkAssertionID != 0 {
            IOPMAssertionRelease(networkAssertionID)
            networkAssertionID = 0
        }

        if let proc = caffeinateProcess {
            proc.terminate()
            caffeinateProcess = nil
        }

        NSLog("[SleepManager] Sleep prevention released.")
    }

    deinit {
        disableSleepPrevention()
    }
}
