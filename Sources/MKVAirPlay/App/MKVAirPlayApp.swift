import SwiftUI
import AppKit

@main
struct MKVAirPlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 540, height: 720)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            for window in NSApp.windows {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
                window.minSize = NSSize(width: 500, height: 680)

                let frame = window.frame
                if frame.size.height < 680 || frame.size.width < 500 {
                    let newWidth = max(540, frame.size.width)
                    let newHeight = max(720, frame.size.height)
                    var newFrame = frame
                    newFrame.origin.y -= (newHeight - frame.size.height)
                    newFrame.size = NSSize(width: newWidth, height: newHeight)
                    window.setFrame(newFrame, display: true, animate: true)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        SleepManager.shared.disableSleepPrevention()
        LocalStreamingServer.shared.stop()
    }
}
