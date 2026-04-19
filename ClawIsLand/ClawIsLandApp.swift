import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindowController: NotchWindowController?
    var bridgeServer: BridgeServer?
    var settingsWindow: NSWindow?
    
    @objc func openSettingsWindow() {
        // If settings is already visible, close it (toggle behavior)
        if let win = settingsWindow, win.isVisible {
            win.close()
            return
        }
        
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "Preferences"
            win.center()
            win.isReleasedWhenClosed = false
            win.contentView = NSHostingView(rootView: SettingsView())
            // Place above the notch panel so it receives clicks
            win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            self.settingsWindow = win
        }
        
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App will not show in dock
        NSApp.setActivationPolicy(.accessory)
        
        // Listen for settings toggle from the notch panel
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsWindow), name: .init("toggleSettingsWindow"), object: nil)
        
        // 自动安装/修正 Claude 配置文件 (执行注入逻辑)
        injectHooksAutomatically()
        
        SoundManager.shared.setupDefaultsIfNeeded()
        
        // Start UNIX Socket Server
        bridgeServer = BridgeServer(state: SessionState.shared)
        bridgeServer?.start()
        
        // Setup Window
        notchWindowController = NotchWindowController(rootView: ContentView())
        notchWindowController?.showWindow(nil)
    }
    
    private func injectHooksAutomatically() {
        // Try to find it in the app bundle first, otherwise try the local developer path
        var scriptPath = Bundle.main.path(forResource: "install-hook", ofType: "py") ?? ""
        if !FileManager.default.fileExists(atPath: scriptPath) {
            scriptPath = "/Users/\(NSUserName())/Desktop/my_ios_project/ClawIsLand/install-hook.py"
        }
        
        guard FileManager.default.fileExists(atPath: scriptPath) else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptPath]
        
        do {
            try process.run()
        } catch {
            print("Failed to auto-inject hooks: \(error)")
        }
    }
}

@main
struct ClawIsLandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No default scenes because WindowGroup/Settings behave unexpectedly in .accessory mode without MainMenu.
        // We manage windows manually in AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
