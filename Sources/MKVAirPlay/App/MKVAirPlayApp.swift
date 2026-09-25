import SwiftUI
import AppKit
import Combine

@main
struct MKVAirPlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: PlaybackViewModel.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 540, height: 720)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        setupStatusItem()
        setupWindow()
        setupStateObservation()
    }

    private func setupWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            for window in NSApp.windows {
                if window.className.contains("StatusBar") { continue }
                if !window.canBecomeMain { continue }

                self.mainWindow = window
                window.delegate = self
                window.isReleasedWhenClosed = false
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
                break
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let img = NSImage(systemSymbolName: "play.tv", accessibilityDescription: "MKVAirPlay")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "MKVAirPlay"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    private func setupStateObservation() {
        PlaybackViewModel.shared.$isStreaming
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isStreaming in
                guard let self = self, let button = self.statusItem?.button else { return }
                let iconName = isStreaming ? "play.tv.fill" : "play.tv"
                let img = NSImage(systemSymbolName: iconName, accessibilityDescription: "MKVAirPlay")
                img?.isTemplate = true
                button.image = img
            }
            .store(in: &cancellables)
    }

    // MARK: - Window Management
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isQuitting {
            return true
        }
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isQuitting = true
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        isQuitting = true
        SleepManager.shared.disableSleepPrevention()
        LocalStreamingServer.shared.stop()
    }

    // MARK: - Menu Delegate
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let vm = PlaybackViewModel.shared

        // 1. Status / Info Header
        if vm.isStreaming {
            let statusTitle = "▶ Streaming to \(vm.selectedDevice?.displayName ?? "TV")"
            let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)

            if !vm.selectedFileName.isEmpty {
                var fileInfo = "🎬 \(vm.selectedFileName)"
                if vm.duration > 0 {
                    let curStr = TimeHelper.formatHHMMSS(seconds: vm.currentTime)
                    let durStr = TimeHelper.formatHHMMSS(seconds: vm.duration)
                    fileInfo += " (\(curStr) / \(durStr))"
                }
                let fileItem = NSMenuItem(title: fileInfo, action: nil, keyEquivalent: "")
                fileItem.isEnabled = false
                menu.addItem(fileItem)
            }
        } else if vm.selectedFileURL != nil {
            let readyItem = NSMenuItem(title: "Ready: \(vm.selectedFileName)", action: nil, keyEquivalent: "")
            readyItem.isEnabled = false
            menu.addItem(readyItem)
        } else {
            let idleItem = NSMenuItem(title: "MKVAirPlay (Idle)", action: nil, keyEquivalent: "")
            idleItem.isEnabled = false
            menu.addItem(idleItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Show / Hide Window
        let isVisible = (mainWindow?.isVisible ?? false) && !(mainWindow?.isMiniaturized ?? false)
        let windowTitle = isVisible ? "Hide MKVAirPlay" : "Show MKVAirPlay"
        let windowItem = NSMenuItem(title: windowTitle, action: #selector(toggleWindow), keyEquivalent: "o")
        windowItem.target = self
        menu.addItem(windowItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Play / Pause Control
        let isPlaying = vm.playbackState == .playing
        let playTitle = isPlaying ? "Pause" : "Play"
        let playItem = NSMenuItem(title: playTitle, action: #selector(togglePlayPause), keyEquivalent: "p")
        playItem.target = self
        playItem.isEnabled = vm.isStreaming
        menu.addItem(playItem)

        // 4. Stop Streaming Control
        let stopItem = NSMenuItem(title: "Stop Streaming", action: #selector(stopStreaming), keyEquivalent: ".")
        stopItem.target = self
        stopItem.isEnabled = vm.isStreaming
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Quit Application
        let quitItem = NSMenuItem(title: "Quit MKVAirPlay", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions
    @objc private func toggleWindow() {
        guard let window = mainWindow else {
            showMainWindow()
            return
        }

        if window.isVisible && !window.isMiniaturized && window.isKeyWindow {
            window.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        } else {
            showMainWindow()
        }
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)

        guard let window = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.className.contains("StatusBar") }) else {
            return
        }
        self.mainWindow = window

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func togglePlayPause() {
        PlaybackViewModel.shared.togglePlayPause()
    }

    @objc private func stopStreaming() {
        PlaybackViewModel.shared.stop()
    }

    @objc private func quitApp() {
        isQuitting = true
        NSApp.terminate(nil)
    }
}
