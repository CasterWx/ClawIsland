import AppKit

struct TerminalActivator {
    
    /// Resolve the host GUI application name (e.g., "Cursor", "iTerm2") for a given PID.
    static func resolveAppName(pid: Int?) -> String? {
        guard let pid = pid else { return nil }
        var currentPid = pid_t(pid)
        let apps = NSWorkspace.shared.runningApplications
        
        while currentPid > 1 {
            if let app = apps.first(where: { $0.processIdentifier == currentPid }) {
                guard let name = app.localizedName else { return nil }
                // Optional aesthetic short-hands for extremely long display names
                if name == "Visual Studio Code" || name == "VSCodium" { return "VS Code" }
                if name == "iTerm" { return "iTerm2" }
                return name
            }
            currentPid = getParentPid(currentPid)
        }
        return nil
    }
    
    /// Activate the terminal or IDE associated with the given session PID and CWD.
    static func activate(pid: Int?, cwd: String?) {
        DispatchQueue.global(qos: .userInitiated).async {
            var targetApp: NSRunningApplication? = nil
            
            // 1. Try to find the GUI app by tracing up the process tree from PID
            if let pid = pid {
                var currentPid = pid_t(pid)
                let apps = NSWorkspace.shared.runningApplications
                
                while currentPid > 1 {
                    if let app = apps.first(where: { $0.processIdentifier == currentPid }) {
                        targetApp = app
                        break
                    }
                    currentPid = getParentPid(currentPid)
                }
            }
            
            // 2. Bring the found app to the front
            if let app = targetApp {
                if app.isHidden { app.unhide() }
                app.activate() // Note: ignoringOtherApps is deprecated in macOS 14
                
                // CRUCIAL: Use openApplication for reliable Space switching across displays
                // (especially required for Electron apps like Cursor/VSCode to properly jump)
                if let bundleURL = app.bundleURL {
                    NSWorkspace.shared.openApplication(at: bundleURL, configuration: NSWorkspace.OpenConfiguration())
                }
                
                // If we also want to raise the specific window for this CWD, doing it via AppleScript
                if let cwd = cwd, let bundleId = app.bundleIdentifier {
                    activateTerminalWindow(bundleId: bundleId, cwd: cwd, appName: app.localizedName ?? "")
                }
                return
            }
            
            // 3. Fallback: Match CWD against known terminals if PID trace failed
            if let cwd = cwd, !cwd.isEmpty {
                activateByCWD(cwd)
            }
        }
    }
    
    // Helper to get parent process ID quickly via ps
    private static func getParentPid(_ pid: pid_t) -> pid_t {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "ps -p \(pid) -o ppid= | tr -d ' ' | head -n 1"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Silence stderr
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let ppid = pid_t(output) {
                return ppid
            }
        } catch {}
        return 0
    }
    
    private static func activateTerminalWindow(bundleId: String, cwd: String, appName: String) {
        let folderName = (cwd as NSString).lastPathComponent
        guard !folderName.isEmpty else { return }
        
        let script = """
        tell application "System Events"
            try
                tell process "\(escapeAppleScript(appName))"
                    set frontmost to true
                    repeat with w in windows
                        try
                            if name of w contains "\(escapeAppleScript(folderName))" then
                                perform action "AXRaise" of w
                                return
                            end if
                        end try
                    end repeat
                end tell
            end try
        end tell
        """
        runAppleScript(script)
    }
    
    private static func activateByCWD(_ cwd: String) {
        let folderName = (cwd as NSString).lastPathComponent
        guard !folderName.isEmpty else { return }
        
        // This is a catch-all fallback: dynamically iterate over ALL visible apps
        let script = """
        tell application "System Events"
            set folderStr to "\(escapeAppleScript(folderName))"
            set visibleApps to name of (every process where background only is false)
            repeat with appName in visibleApps
                try
                    tell process appName
                        repeat with w in windows
                            if name of w contains folderStr then
                                set frontmost to true
                                perform action "AXRaise" of w
                                return
                            end if
                        end repeat
                    end tell
                end try
            end repeat
        end tell
        """
        runAppleScript(script)
    }
    
    private static func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }
    
    private static func escapeAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
