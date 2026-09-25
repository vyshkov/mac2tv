import Foundation
import IOKit.pwr_mgt
import IOKit.ps
import AppKit
import CoreGraphics

// MARK: - Display Brightness Dynamic Controller
final class DisplayBrightnessController: @unchecked Sendable {
    private typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private var handle: UnsafeMutableRawPointer?
    private var getBrightnessFn: GetBrightnessFunc?
    private var setBrightnessFn: SetBrightnessFunc?

    init() {
        if let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            handle = h
            if let getSym = dlsym(h, "DisplayServicesGetBrightness") {
                getBrightnessFn = unsafeBitCast(getSym, to: GetBrightnessFunc.self)
            }
            if let setSym = dlsym(h, "DisplayServicesSetBrightness") {
                setBrightnessFn = unsafeBitCast(setSym, to: SetBrightnessFunc.self)
            }
        }
    }

    deinit {
        if let h = handle { dlclose(h) }
    }

    func getBuiltInDisplayID() -> CGDirectDisplayID {
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        if CGGetActiveDisplayList(16, &activeDisplays, &displayCount) == .success {
            for i in 0..<Int(displayCount) {
                let d = activeDisplays[i]
                if CGDisplayIsBuiltin(d) != 0 {
                    return d
                }
            }
        }
        return CGMainDisplayID()
    }

    func getBrightness() -> Float? {
        guard let getFn = getBrightnessFn else { return nil }
        var val: Float = 0
        let ret = getFn(getBuiltInDisplayID(), &val)
        return ret == 0 ? val : nil
    }

    func setBrightness(_ value: Float) -> Bool {
        guard let setFn = setBrightnessFn else { return false }
        let clamped = max(0.0, min(1.0, value))
        let ret = setFn(getBuiltInDisplayID(), clamped)
        return ret == 0
    }
}

public final class SleepManager: @unchecked Sendable {
    public static let shared = SleepManager()

    private var assertionID: IOPMAssertionID = 0
    private var networkAssertionID: IOPMAssertionID = 0
    private var activityToken: NSObjectProtocol?
    private var caffeinateProcess: Process?

    public private(set) var isSleepPrevented: Bool = false
    public private(set) var isPmsetSleepDisabled: Bool = false

    // MARK: - Clamshell / Lid & Display State
    public private(set) var isLidClosed: Bool = SleepManager.isLidClosed()
    public private(set) var isDisplayTurnedOff: Bool = false
    private var savedBrightness: Float?
    private let brightnessController = DisplayBrightnessController()
    public var onLidStateChanged: ((Bool) -> Void)?

    private var notifyPort: IONotificationPortRef?
    private var clamshellNotifier: io_object_t = 0
    private var monitorTimer: Timer?

    public var onBatteryCritical: ((Int) -> Void)?

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

        // Self-healing brightness recovery if app was killed while lid was closed:
        if !SleepManager.isLidClosed() {
            if let currentBrightness = brightnessController.getBrightness(), currentBrightness < 0.02 {
                _ = brightnessController.setBrightness(0.5)
                NSLog("[SleepManager] Restored display brightness to default 0.5 on startup.")
            }
        }
    }

    // MARK: - Clamshell / Lid Detection
    public static func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        if let prop = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool {
            return prop
        }
        return false
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

        // 6. Start event-driven lid monitoring and timer
        startLidMonitoring()
        startMonitoringTimer()

        // Immediate check in case lid is already closed
        evaluateLidState()

        NSLog("[SleepManager] Sleep prevention active. Mac will not sleep when lid is closed.")
    }

    public func disableSleepPrevention() {
        guard isSleepPrevented else {
            // Still ensure pmset disablesleep is turned off
            if isPmsetSleepDisabled {
                setPmsetDisableSleep(false)
            }
            if isDisplayTurnedOff {
                let targetBrightness = savedBrightness ?? 0.5
                _ = brightnessController.setBrightness(targetBrightness)
                savedBrightness = nil
                isDisplayTurnedOff = false
                wakeDisplay()
            }
            return
        }
        isSleepPrevented = false

        stopMonitoringTimer()
        stopLidMonitoring()

        if isDisplayTurnedOff {
            let targetBrightness = savedBrightness ?? 0.5
            _ = brightnessController.setBrightness(targetBrightness)
            savedBrightness = nil
            isDisplayTurnedOff = false
            wakeDisplay()
        }

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

    // MARK: - Clamshell State Handling & Display Power Management
    public func evaluateLidState() {
        let closed = SleepManager.isLidClosed()
        let previousState = self.isLidClosed
        self.isLidClosed = closed

        if closed != previousState {
            NSLog("[SleepManager] Clamshell state changed: lid is now %@", closed ? "CLOSED" : "OPEN")
            onLidStateChanged?(closed)
        }

        guard isSleepPrevented else { return }

        if closed {
            handleLidClosed()
        } else {
            handleLidOpened()
        }
    }

    private func handleLidClosed() {
        if !isDisplayTurnedOff {
            if let currentBrightness = brightnessController.getBrightness(), currentBrightness > 0.05 {
                savedBrightness = currentBrightness
                NSLog("[SleepManager] Saved display brightness before lid close: %.2f", currentBrightness)
            }
            _ = brightnessController.setBrightness(0.0)
            isDisplayTurnedOff = true
            sleepDisplay()
            NSLog("[SleepManager] MacBook lid closed while streaming. Display backlight turned off to conserve battery.")
        } else {
            // Already marked turned off; ensure brightness is kept at 0.0 and display sleep is requested
            if let currentBrightness = brightnessController.getBrightness(), currentBrightness > 0.02 {
                _ = brightnessController.setBrightness(0.0)
                sleepDisplay()
            }
        }
    }

    private func handleLidOpened() {
        guard isDisplayTurnedOff else { return }

        let targetBrightness = savedBrightness ?? 0.5
        _ = brightnessController.setBrightness(targetBrightness)
        NSLog("[SleepManager] MacBook lid opened. Restoring display brightness to %.2f.", targetBrightness)
        savedBrightness = nil
        isDisplayTurnedOff = false

        wakeDisplay()
    }

    private func sleepDisplay() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["displaysleepnow"]
        let devNull = FileHandle.nullDevice
        proc.standardOutput = devNull
        proc.standardError = devNull
        try? proc.run()

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayWrangler"))
        if service != IO_OBJECT_NULL {
            IORegistryEntrySetCFProperty(service, "IORequestIdle" as CFString, kCFBooleanTrue)
            IOObjectRelease(service)
        }
    }

    private func wakeDisplay() {
        var userActivityAssertionID: IOPMAssertionID = 0
        _ = IOPMAssertionDeclareUserActivity(
            "MKVAirPlay Lid Opened" as CFString,
            kIOPMUserActiveLocal,
            &userActivityAssertionID
        )

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        proc.arguments = ["-u", "-t", "1"]
        let devNull = FileHandle.nullDevice
        proc.standardOutput = devNull
        proc.standardError = devNull
        try? proc.run()
    }

    private func startLidMonitoring() {
        stopLidMonitoring()

        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(rootDomain) }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.notifyPort = port

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let kr = IOServiceAddInterestNotification(
            port,
            rootDomain,
            kIOGeneralInterest,
            { (refcon, service, messageType, messageArgument) in
                guard let refcon = refcon else { return }
                let manager = Unmanaged<SleepManager>.fromOpaque(refcon).takeUnretainedValue()
                // 0xE0034100 is kIOPMMessageClamshellStateChange
                if messageType == 0xE0034100 {
                    DispatchQueue.main.async {
                        manager.evaluateLidState()
                    }
                }
            },
            selfPtr,
            &clamshellNotifier
        )
        if kr != kIOReturnSuccess {
            NSLog("[SleepManager] Failed to register clamshell interest notification: %d", kr)
        }
    }

    private func stopLidMonitoring() {
        if clamshellNotifier != 0 {
            IOObjectRelease(clamshellNotifier)
            clamshellNotifier = 0
        }
        if let port = notifyPort {
            let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
    }

    // MARK: - Monitoring Timer (Battery Safeguard & Lid Fallback)
    private func startMonitoringTimer() {
        stopMonitoringTimer()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                guard let self = self, self.isSleepPrevented else { return }

                // 1. Check lid state
                self.evaluateLidState()

                // 2. Enforce battery safety cutoff
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

    private func stopMonitoringTimer() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    deinit {
        disableSleepPrevention()
    }
}

