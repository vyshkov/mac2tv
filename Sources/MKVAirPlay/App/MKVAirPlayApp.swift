import SwiftUI
import AppKit
import Combine

@main
struct MKVAirPlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("MKVAirPlay", id: "main") {
            ContentView(viewModel: PlaybackViewModel.shared)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL { url in
                    appDelegate.handleOpenFile(url: url)
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 430)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Playback") {
                Button(PlaybackViewModel.shared.playbackState == .playing ? "Pause" : "Play") {
                    PlaybackViewModel.shared.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(!PlaybackViewModel.shared.isStreaming)

                Button("Stop Streaming") {
                    PlaybackViewModel.shared.stop()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!PlaybackViewModel.shared.isStreaming)

                Divider()

                Button("Volume Up (+1)") {
                    PlaybackViewModel.shared.adjustVolume(by: 1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.option, .command])
                .disabled(!PlaybackViewModel.shared.isStreaming || !PlaybackViewModel.shared.supportsVolumeControl)

                Button("Volume Down (-1)") {
                    PlaybackViewModel.shared.adjustVolume(by: -1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.option, .command])
                .disabled(!PlaybackViewModel.shared.isStreaming || !PlaybackViewModel.shared.supportsVolumeControl)

                Button(PlaybackViewModel.shared.isMuted ? "Unmute TV" : "Mute TV") {
                    PlaybackViewModel.shared.toggleMute()
                }
                .keyboardShortcut("m", modifiers: [.option, .command])
                .disabled(!PlaybackViewModel.shared.isStreaming || !PlaybackViewModel.shared.supportsVolumeControl)

                Divider()

                Toggle("Keep Streaming When Lid is Closed", isOn: Binding(
                    get: { PlaybackViewModel.shared.preventSleepOnLidClose },
                    set: { PlaybackViewModel.shared.preventSleepOnLidClose = $0 }
                ))
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    static private(set) var shared: AppDelegate?
    private var statusItem: NSStatusItem?
    private weak var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var isQuitting = false
    private var currentContentHeight: CGFloat = 0
    private var isProgrammaticResize = false

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        setupStatusItem()
        setupWindow()
        setupStateObservation()
        handleCommandLineArguments()
    }

    func configureWindow(_ window: NSWindow) {
        self.mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear

        var mask = window.styleMask
        mask.insert([.titled, .closable, .miniaturizable, .fullSizeContentView])
        mask.remove(.resizable)
        window.styleMask = mask

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none

        window.showsResizeIndicator = false
        window.collectionBehavior.insert(.fullScreenNone)
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("")

        // Ensure standard window control buttons (close, minimize) are explicitly visible & enabled
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.closeButton)?.isEnabled = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        bringTitlebarToFront(in: window)

        let targetWidth: CGFloat = 520
        let targetHeight: CGFloat = currentContentHeight > 100 ? currentContentHeight : 430
        window.minSize = NSSize(width: targetWidth, height: targetHeight)
        window.maxSize = NSSize(width: targetWidth, height: targetHeight)
    }

    private func bringTitlebarToFront(in window: NSWindow) {
        window.titlebarSeparatorStyle = .none
        guard let titlebarContainer = window.standardWindowButton(.closeButton)?.superview?.superview,
              let themeFrame = titlebarContainer.superview else { return }

        if themeFrame.subviews.last !== titlebarContainer {
            themeFrame.addSubview(titlebarContainer, positioned: .above, relativeTo: nil)
        }
        titlebarContainer.layer?.zPosition = 1000
        titlebarContainer.isHidden = false
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.closeButton)?.isEnabled = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        makeTitlebarTransparent(titlebarContainer)
    }

    private func makeTitlebarTransparent(_ container: NSView) {
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        func sanitize(_ view: NSView) {
            let className = NSStringFromClass(type(of: view))
            let layerClass = view.layer.map { NSStringFromClass(type(of: $0)) } ?? ""
            if className.contains("Background") || className.contains("Decoration") || layerClass.contains("Backdrop") || className.contains("VisualEffect") {
                view.isHidden = true
                view.alphaValue = 0
            } else {
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.clear.cgColor
            }

            for subview in view.subviews {
                let subClass = NSStringFromClass(type(of: subview))
                if subClass.contains("Close") || subClass.contains("ThemeWidget") {
                    subview.isHidden = false
                    subview.alphaValue = 1.0
                } else {
                    sanitize(subview)
                }
            }
        }

        sanitize(container)
    }

    private func setupWindow() {
        // Clear any old saved frames from UserDefaults so macOS doesn't restore stale sizes
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame main")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame MKVAirPlay")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            var assignedMain = false
            for window in NSApp.windows {
                if window.className.contains("StatusBar") { continue }
                if !window.canBecomeMain { continue }

                if !assignedMain {
                    assignedMain = true
                    self.configureWindow(window)

                    if self.currentContentHeight > 100 {
                        self.updateWindowHeight(self.currentContentHeight)
                    } else {
                        let targetWidth: CGFloat = 520
                        let targetHeight: CGFloat = 430
                        var frame = window.frame
                        frame.size = NSSize(width: targetWidth, height: targetHeight)
                        self.isProgrammaticResize = true
                        window.setFrame(frame, display: true, animate: false)
                        self.isProgrammaticResize = false
                    }
                } else {
                    window.close()
                }
            }
        }
    }

    func updateWindowHeight(_ contentHeight: CGFloat) {
        guard let window = mainWindow ?? NSApp.windows.first(where: { !$0.className.contains("StatusBar") && $0.canBecomeMain }) else { return }
        self.mainWindow = window
        configureWindow(window)

        let targetHeight = ceil(contentHeight)
        guard targetHeight > 100 else { return }

        currentContentHeight = targetHeight
        let targetWidth: CGFloat = 520

        window.minSize = NSSize(width: targetWidth, height: targetHeight)
        window.maxSize = NSSize(width: targetWidth, height: targetHeight)

        let currentFrame = window.frame
        if abs(currentFrame.size.height - targetHeight) > 1 || abs(currentFrame.size.width - targetWidth) > 1 {
            var newFrame = currentFrame
            let heightDiff = targetHeight - currentFrame.size.height
            // Keep top-left anchored in screen coordinates
            newFrame.origin.y -= heightDiff
            newFrame.size = NSSize(width: targetWidth, height: targetHeight)

            // Constrain within visible screen bounds
            if let screen = window.screen ?? NSScreen.main {
                let visibleFrame = screen.visibleFrame
                if newFrame.origin.y < visibleFrame.minY {
                    newFrame.origin.y = visibleFrame.minY
                }
                if newFrame.maxY > visibleFrame.maxY {
                    newFrame.origin.y = visibleFrame.maxY - newFrame.height
                }
            }

            isProgrammaticResize = true
            window.setFrame(newFrame, display: true, animate: window.isVisible)
            isProgrammaticResize = false
        }
    }

    // MARK: - NSWindowDelegate (Disallow Manual Resizing Completely)
    func windowDidUpdate(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        bringTitlebarToFront(in: window)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if isProgrammaticResize {
            return frameSize
        }
        // Force the window to remain at 520 width and current content height
        let targetHeight = currentContentHeight > 100 ? currentContentHeight : sender.frame.size.height
        return NSSize(width: 520, height: targetHeight)
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        return false
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
                guard let self = self else { return }
                if let button = self.statusItem?.button {
                    let iconName = isStreaming ? "play.tv.fill" : "play.tv"
                    let img = NSImage(systemSymbolName: iconName, accessibilityDescription: "MKVAirPlay")
                    img?.isTemplate = true
                    button.image = img
                }
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
        SleepManager.shared.restoreDefaultSleep()
        LocalStreamingServer.shared.stop()
    }

    // MARK: - Open With / File Handling
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        handleOpenFile(url: url)
    }

    func handleOpenFile(url: URL) {
        guard url.isFileURL else { return }
        let standardized = url.standardizedFileURL
        PlaybackViewModel.shared.selectFile(url: standardized)
        showMainWindow()
    }

    private func handleCommandLineArguments() {
        let args = CommandLine.arguments
        guard args.count > 1 else { return }

        for arg in args.dropFirst() {
            if arg.starts(with: "-psn") || arg.starts(with: "-") { continue }
            let url = URL(fileURLWithPath: arg)
            if FileManager.default.fileExists(atPath: url.path) {
                handleOpenFile(url: url)
                break
            }
        }
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

        // 5. Keep Streaming When Lid is Closed Option
        let isSleepActive = vm.isStreaming && vm.playbackState == .playing && vm.preventSleepOnLidClose
        let sleepTitle: String
        if isSleepActive {
            if vm.isLidClosed {
                sleepTitle = "Keep Streaming When Lid is Closed (Lid Closed - Display Off)"
            } else {
                sleepTitle = vm.isOnBattery ? "Keep Streaming When Lid is Closed (Active on Battery)" : "Keep Streaming When Lid is Closed (Active on AC)"
            }
        } else if vm.preventSleepOnLidClose {
            sleepTitle = vm.isBatteryLidSleepAuthorized ? "Keep Streaming When Lid is Closed (Armed: AC + Battery)" : "Keep Streaming When Lid is Closed (Armed: AC only)"
        } else {
            sleepTitle = "Keep Streaming When Lid is Closed"
        }
        let sleepItem = NSMenuItem(
            title: sleepTitle,
            action: #selector(togglePreventSleepOnLidClose),
            keyEquivalent: ""
        )
        sleepItem.target = self
        sleepItem.state = vm.preventSleepOnLidClose ? .on : .off
        menu.addItem(sleepItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Quit Application
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

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)

        guard let window = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.className.contains("StatusBar") }) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.showMainWindow()
            }
            return
        }
        self.mainWindow = window

        // Close any duplicate/secondary windows
        for otherWindow in NSApp.windows {
            if otherWindow !== window && otherWindow.canBecomeMain && !otherWindow.className.contains("StatusBar") {
                otherWindow.close()
            }
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)

        if currentContentHeight > 100 {
            updateWindowHeight(currentContentHeight)
        }

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

    @objc private func togglePreventSleepOnLidClose() {
        PlaybackViewModel.shared.preventSleepOnLidClose.toggle()
    }

    @objc private func quitApp() {
        isQuitting = true
        NSApp.terminate(nil)
    }
}
