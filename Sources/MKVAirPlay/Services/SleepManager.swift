import Foundation
import IOKit.pwr_mgt
import IOKit.ps
import AppKit

public final class SleepManager: @unchecked Sendable {
    public static let shared = SleepManager()

    private var assertionID: IOPMAssertionID = 0
    private var networkAssertionID: IOPMAssertionID = 0
    private var activityToken: NSObjectProtocol?
    private var caffeinateProcess: Process?

    public private(set) var isSleepPrevented: Bool = false
    public private(set) var isPmsetSleepDisabled: Bool = false

    public var onBatteryCritical: ((Int) -> Void)?
    private var batteryMonitorTimer: Timer?

    public struct PowerStatus: Sendable {
        public let isOnBattery: Bool
        public let batteryPercentage: Int?

        public init(isOnBattery: Bool, batteryPercentage: Int?) {
            self.isOnBattery = isOnBattery
            self.batteryPercentage = batteryPercentage
        }
    }

    private init() {
        // Register for app termination to ensure sleep settings are always restored
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.disableSleepPrevention()
        }

        // Crash-safe self-healing: if pmset was left disabled from an earlier unexpected kill, restore it
        if SleepManager.checkBatteryAuthorization() {
            restoreDefaultSleep()
        }
    }

    // MARK: - Power Status
    public static func getPowerStatus() -> PowerStatus {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
        let isOnBattery = (type == kIOPSBatteryPowerValue as String)
        var percent: Int? = nil
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for ps in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] {
                if let cap = desc[kIOPSCurrentCapacityKey] as? Int {
                    percent = cap
                    break
                }
            }
        }
        return PowerStatus(isOnBattery: isOnBattery, batteryPercentage: percent)
    }

    // MARK: - Authorization Checking & Management
    public static func checkBatteryAuthorization() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", "/usr/bin/pmset", "-b", "disablesleep", "0"]
        let devNull = FileHandle.nullDevice
        proc.standardOutput = devNull
        proc.standardError = devNull
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    public static func installBatteryAuthorization() -> (success: Bool, error: String?) {
        let userName = NSUserName()
        let sudoersPath = "/etc/sudoers.d/mkvairplay"
        let rule = "\(userName) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -b disablesleep 1, /usr/bin/pmset -b disablesleep 0\\n%admin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -b disablesleep 1, /usr/bin/pmset -b disablesleep 0"
        
        let shellCommand = """
        TMPFILE=$(mktemp /tmp/mkvairplay_sudoers.XXXXXX) && printf '\(rule)\\n' > "$TMPFILE" && visudo -cf "$TMPFILE" && cp "$TMPFILE" \(sudoersPath) && chmod 0440 \(sudoersPath) && rm -f "$TMPFILE"
        """
        
        let escapedScript = shellCommand.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let appleScriptSource = "do shell script \"\(escapedScript)\" with administrator privileges"
        
        var errorDict: NSDictionary?
        if let script = NSAppleScript(source: appleScriptSource) {
            _ = script.executeAndReturnError(&errorDict)
            if let errorDict = errorDict {
                let errorMsg = errorDict[NSAppleScript.errorMessage] as? String ?? "Authorization was cancelled or failed."
                NSLog("[SleepManager] Authorization failed: %@", errorMsg)
                return (false, errorMsg)
            }
            let verified = checkBatteryAuthorization()
            return (verified, verified ? nil : "Configuration saved, but sudoers check did not verify.")
        }
        return (false, "Could not initialize AppleScript.")
    }

    public static func removeBatteryAuthorization() -> (success: Bool, error: String?) {
        let sudoersPath = "/etc/sudoers.d/mkvairplay"
        let appleScriptSource = "do shell script \"rm -f \(sudoersPath)\" with administrator privileges"
        var errorDict: NSDictionary?
        if let script = NSAppleScript(source: appleScriptSource) {
            _ = script.executeAndReturnError(&errorDict)
            if let errorDict = errorDict {
                let errorMsg = errorDict[NSAppleScript.errorMessage] as? String ?? "Failed to remove"
                return (false, errorMsg)
            }
            return (true, nil)
        }
        return (false, "Could not initialize AppleScript.")
    }

    // MARK: - pmset Management
    private func setPmsetDisableSleep(_ disable: Bool) {
        guard SleepManager.checkBatteryAuthorization() else { return }
        let arg = disable ? "1" : "0"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", arg]
        let devNull = FileHandle.nullDevice
        proc.standardOutput = devNull
        proc.standardError = devNull
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                isPmsetSleepDisabled = disable
                NSLog("[SleepManager] Successfully set pmset -a disablesleep %@", arg)
            } else {
                NSLog("[SleepManager] Failed to set pmset -a disablesleep %@ (exit code %d)", arg, proc.terminationStatus)
            }
        } catch {
            NSLog("[SleepManager] Error executing sudo pmset: %@", error.localizedDescription)
        }
    }

    public func restoreDefaultSleep() {
        guard SleepManager.checkBatteryAuthorization() else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]
        let devNull = FileHandle.nullDevice
        proc.standardOutput = devNull
        proc.standardError = devNull
        try? proc.run()
        proc.waitUntilExit()
        isPmsetSleepDisabled = false
    }

    // MARK: - Enable / Disable Sleep Prevention
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

        // 4. Background caffeinate process: -i (idle sleep), -s (system sleep), -m (disk idle), -w (bound to app PID)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        proc.arguments = ["-i", "-s", "-m", "-w", "\(ProcessInfo.processInfo.processIdentifier)"]
        do {
            try proc.run()
            caffeinateProcess = proc
        } catch {
            NSLog("[SleepManager] Could not spawn caffeinate: %@", error.localizedDescription)
        }

        // 5. Battery/Clamshell override: if authorized, set pmset -a disablesleep 1
        // This ensures the Mac stays awake when the lid is closed even on battery power
        if SleepManager.checkBatteryAuthorization() {
            setPmsetDisableSleep(true)
        }

        // 6. Start monitoring battery level to enforce low-battery safety cutoff
        startBatteryMonitoring()

        NSLog("[SleepManager] Sleep prevention active. Mac will not sleep when lid is closed.")
    }

    public func disableSleepPrevention() {
        guard isSleepPrevented else {
            // Still ensure pmset disablesleep is turned off
            if isPmsetSleepDisabled {
                setPmsetDisableSleep(false)
            }
            return
        }
        isSleepPrevented = false

        stopBatteryMonitoring()

        if isPmsetSleepDisabled {
            setPmsetDisableSleep(false)
        }

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

    // MARK: - Battery Monitoring & Safety Cutoff
    private func startBatteryMonitoring() {
        stopBatteryMonitoring()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.batteryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
                guard let self = self, self.isSleepPrevented else { return }
                let status = SleepManager.getPowerStatus()
                if status.isOnBattery, let level = status.batteryPercentage {
                    if level <= 15 {
                        NSLog("[SleepManager] Battery low (%d%%). Stopping sleep prevention to avoid battery exhaustion.", level)
                        self.onBatteryCritical?(level)
                    }
                }
            }
        }
    }

    private func stopBatteryMonitoring() {
        batteryMonitorTimer?.invalidate()
        batteryMonitorTimer = nil
    }

    deinit {
        disableSleepPrevention()
    }
}
