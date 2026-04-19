import Foundation
import Combine

struct QuestionOption: Codable, Hashable {
    var label: String
    var description: String?
}

struct QuestionItem: Codable, Hashable {
    var question: String
    var header: String?
    var options: [QuestionOption]?
    var multiSelect: Bool?
}

struct ToolInput: Codable {
    var command: String?
    var file_path: String?
    var content: String?
    var query: String?
    var code: String?
    var questions: [QuestionItem]?
}

struct HookPayload: Codable {
    var hookEventName: String?
    var sessionID: String?
    var cwd: String?
    var toolName: String?
    var toolInput: ToolInput?
    var prompt: String?
    var message: String?
    var title: String?
    var error: String?
    var lastAssistantMessage: String?
    
    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case prompt
        case message
        case title
        case error
        case lastAssistantMessage = "last_assistant_message"
    }
}

struct ActiveSession: Codable, Identifiable {
    var id: String { sessionId }
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Int
    let entrypoint: String?
}

// Structs for the response back to Claude Code
struct ClaudePermissionDecision: Codable {
    var behavior: String
}

struct ClaudeHookSpecificOutput: Codable {
    var hookEventName: String
    var decision: ClaudePermissionDecision
}

struct ClaudeResponseOutput: Codable {
    var `continue`: Bool
    var suppressOutput: Bool
    var hookSpecificOutput: ClaudeHookSpecificOutput
}

struct SessionMetrics: Codable {
    var msgCount: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var toolCalls: Int = 0
}

struct SessionMessage: Identifiable, Codable {
    var id: String { UUID().uuidString }
    let role: String
    let content: String
}

@Observable
class SessionState {
    static let shared = SessionState()
    
    var currentPayload: HookPayload?
    var sessionPayloads: [String: HookPayload] = [:]
    var sessionHistories: [String: String] = [:]
    var sessionMetrics: [String: SessionMetrics] = [:]
    var sessionMessages: [String: [SessionMessage]] = [:]
    
    var isExpanded: Bool = false
    var expandedSessionId: String? = nil
    var statusText: String = "Monitoring..."
    var socketConnection: FileHandle?
    var activeProcessCount: Int = 0
    var activeSessions: [ActiveSession] = []
    
    private var processTimer: Timer?
    
    init() {
        startProcessMonitoring()
    }
    
    func startProcessMonitoring() {
        processTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.checkClaudeProcesses()
        }
        processTimer?.fire()
    }
    
    private var lastFileSizes: [String: UInt64] = [:]
    private var cachedHistoryData: [String: (String?, SessionMetrics, [SessionMessage])] = [:]
    
    private func fetchHistoryAndMetrics(cwd: String, sessionId: String) -> (String?, SessionMetrics, [SessionMessage]) {
        let dashedCwd = cwd.replacingOccurrences(of: "[^a-zA-Z0-9-]", with: "-", options: .regularExpression)
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let histURL = homeDir.appendingPathComponent(".claude/projects/\(dashedCwd)/\(sessionId).jsonl")
        
        let path = histURL.path
        if let attrs = try? fileManager.attributesOfItem(atPath: path),
           let currentSize = attrs[.size] as? UInt64 {
            if let lastSize = lastFileSizes[sessionId], lastSize == currentSize, let cached = cachedHistoryData[sessionId] {
                return cached
            }
            lastFileSizes[sessionId] = currentSize
        } else {
            return (nil, SessionMetrics(), [])
        }
        
        var metrics = SessionMetrics()
        var lastStatus: String? = nil
        var messages: [SessionMessage] = []
        
        guard let data = try? Data(contentsOf: histURL),
              let content = String(data: data, encoding: .utf8) else { return (nil, metrics, []) }
        
        // Fast line split
        var startIndex = content.startIndex
        var lines: [Substring] = []
        while startIndex < content.endIndex {
            let nextNewLine = content[startIndex...].firstIndex(of: "\n") ?? content.endIndex
            lines.append(content[startIndex..<nextNewLine])
            if nextNewLine == content.endIndex { break }
            startIndex = content.index(after: nextNewLine)
        }
        
        metrics.msgCount = lines.count
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            if let dict = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: []) as? [String: Any],
               let type = dict["type"] as? String {
                
                if type == "last-prompt", let lastPrompt = dict["lastPrompt"] as? String {
                    lastStatus = "🗣 \(lastPrompt.count > 100 ? String(lastPrompt.prefix(100)) + "..." : lastPrompt)"
                    messages.append(SessionMessage(role: "user", content: lastPrompt))
                }
                
                if type == "user", let msg = dict["message"] as? [String: Any], let txt = msg["content"] as? String {
                    lastStatus = "🗣 \(txt.count > 100 ? String(txt.prefix(100)) + "..." : txt)"
                    messages.append(SessionMessage(role: "user", content: txt))
                }
                
                if type == "assistant", let msg = dict["message"] as? [String: Any] {
                    if let contentArray = msg["content"] as? [[String: Any]] {
                        if let firstText = contentArray.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String {
                            lastStatus = "🤖 \(firstText.count > 100 ? String(firstText.prefix(100)) + "..." : firstText)"
                            messages.append(SessionMessage(role: "assistant", content: firstText))
                        }
                        for c in contentArray {
                            if (c["type"] as? String) == "tool_use" {
                                metrics.toolCalls += 1
                            }
                        }
                    }
                    if let usage = msg["usage"] as? [String: Any] {
                        metrics.inputTokens += (usage["input_tokens"] as? Int) ?? 0
                        metrics.outputTokens += (usage["output_tokens"] as? Int) ?? 0
                    }
                }
            }
        }
        
        let result = (lastStatus, metrics, Array(messages.suffix(30)))
        cachedHistoryData[sessionId] = result
        return result
    }
    
    private func checkClaudeProcesses() {
        DispatchQueue.global(qos: .background).async {
            let fileManager = FileManager.default
            let homeDir = fileManager.homeDirectoryForCurrentUser
            let sessionsURL = homeDir.appendingPathComponent(".claude/sessions")
            
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: sessionsURL, includingPropertiesForKeys: nil)
                let jsonFiles = fileURLs.filter { $0.pathExtension == "json" }
                
                var validSessions: [ActiveSession] = []
                let decoder = JSONDecoder()
                
                for fileURL in jsonFiles {
                    if let data = try? Data(contentsOf: fileURL),
                       let session = try? decoder.decode(ActiveSession.self, from: data) {
                        
                        let isRunning = kill(pid_t(session.pid), 0) == 0
                        if isRunning {
                            validSessions.append(session)
                        } else {
                            try? fileManager.removeItem(at: fileURL)
                            DispatchQueue.main.async {
                                self.sessionPayloads.removeValue(forKey: session.sessionId)
                                self.sessionHistories.removeValue(forKey: session.sessionId)
                                self.sessionMetrics.removeValue(forKey: session.sessionId)
                            }
                        }
                    }
                }
                
                validSessions.sort { $0.startedAt > $1.startedAt }
                
                var tempHistories: [String: String] = [:]
                var tempMetrics: [String: SessionMetrics] = [:]
                var tempMessages: [String: [SessionMessage]] = [:]
                for session in validSessions {
                    let (hist, met, msgs) = self.fetchHistoryAndMetrics(cwd: session.cwd, sessionId: session.sessionId)
                    if let h = hist {
                        tempHistories[session.sessionId] = h
                    }
                    tempMetrics[session.sessionId] = met
                    tempMessages[session.sessionId] = msgs
                }
                
                DispatchQueue.main.async {
                    self.activeSessions = validSessions
                    self.activeProcessCount = validSessions.count
                    self.sessionHistories = tempHistories
                    self.sessionMetrics = tempMetrics
                    self.sessionMessages = tempMessages
                    
                    if self.currentPayload == nil {
                        if validSessions.count > 0 {
                            let lastCwd = validSessions.first?.cwd.components(separatedBy: "/").last ?? "Unknown"
                            self.statusText = "\(validSessions.count) Session\(validSessions.count > 1 ? "s" : "") (\(lastCwd))"
                        } else {
                            self.statusText = "Idle"
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.activeSessions = []
                    self.activeProcessCount = 0
                    if self.currentPayload == nil { self.statusText = "Idle" }
                }
            }
        }
    }
    
    var latestSoundTrigger: (String, UUID)?
    
    @MainActor
    func updateState(payload: HookPayload, connection: FileHandle? = nil) {
        if let eventName = payload.hookEventName {
            self.latestSoundTrigger = (eventName, UUID())
        }
        
        let ignoredVisualEvents = ["PreToolUse", "PostToolUse", "PostToolUseFailure"]
        if !ignoredVisualEvents.contains(payload.hookEventName ?? "") {
            self.currentPayload = payload
            self.statusText = payload.hookEventName ?? "Processing..."
        }
        self.socketConnection = connection
        
        if let sid = payload.sessionID {
            self.sessionPayloads[sid] = payload
        }
        
        switch payload.hookEventName {
        case "SessionStart":
            self.statusText = "Session Started"
            self.isExpanded = true
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run { if self.currentPayload?.hookEventName == "SessionStart" { self.isExpanded = false; self.currentPayload = nil } }
            }
        case "UserPromptSubmit":
            self.statusText = "New Prompt Submitted"
            self.isExpanded = true
            Task {
                let autoCollapseData = UserDefaults.standard.double(forKey: "autoCollapseDuration")
                let delay = autoCollapseData > 0 ? autoCollapseData : 3.0
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run { 
                    if self.currentPayload?.hookEventName == "UserPromptSubmit" { 
                        self.isExpanded = false
                        self.currentPayload = nil 
                    } 
                }
            }
        case "PermissionRequest":
            self.statusText = "Permission Required..."
            self.isExpanded = true
        case "Notification":
            self.statusText = payload.title ?? "Notification"
            self.isExpanded = true
        case "Error":
            self.statusText = payload.prompt ?? "System Error"
            self.isExpanded = true
        case "Stop":
            self.statusText = "Agent Finished"
            self.isExpanded = true
            Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                await MainActor.run { 
                    if self.currentPayload?.hookEventName == "Stop" { 
                        self.isExpanded = false
                        self.currentPayload = nil 
                    } 
                }
            }
        case "SessionEnd":
            self.statusText = "Session Ended"
            self.isExpanded = true
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run { if self.currentPayload?.hookEventName == "SessionEnd" { self.isExpanded = false; self.currentPayload = nil } }
            }
        case .none:
            // Fallback for parsing error simulation
            if payload.prompt?.contains("Failed to parse") == true {
                self.statusText = "JSON Parsing Issue"
                self.isExpanded = true
            } else {
                self.isExpanded = false
            }
        case "PreToolUse", "PostToolUse", "PostToolUseFailure":
            // Silently ignore to prevent UI flicker and redundant status updates
            break
        case "AssistantMessage":
            self.statusText = "New Message"
            self.isExpanded = false
        default:
            self.statusText = "\(payload.hookEventName!)"
            self.isExpanded = false
        }
    }
    
    @MainActor
    func replyToHook(allow: Bool) {
        guard let connection = socketConnection else { return }
        
        let rootNode: [String: Any] = [
            "continue": true,
            "suppressOutput": true,
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": allow ? "allow" : "deny"
                ]
            ]
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: rootNode, options: [])
            var line = data
            line.append(UInt8(ascii: "\n"))
            try connection.write(contentsOf: line)
            try connection.close()
            
            self.isExpanded = false
            self.currentPayload = nil
            self.socketConnection = nil
            self.statusText = allow ? "Allowed" : "Denied"
        } catch {
            print("Failed to reply: \(error)")
        }
    }
    
    @MainActor
    func replyToQuestion(answer: String, question: String) {
        guard let connection = socketConnection else { return }
        
        // Wrap the payload dict with the structure Claude Code asks for.
        let rootNode: [String: Any] = [
            "continue": true,
            "suppressOutput": true,
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": "allow",
                    "updatedInput": [
                        "answers": [question: answer]
                    ]
                ]
            ]
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: rootNode, options: [])
            var line = data
            line.append(UInt8(ascii: "\n"))
            try connection.write(contentsOf: line)
            try connection.close()
            
            self.isExpanded = false
            self.currentPayload = nil
            self.socketConnection = nil
            self.statusText = "Answer Submitted"
        } catch {
            print("Failed to reply: \(error)")
        }
    }
}
