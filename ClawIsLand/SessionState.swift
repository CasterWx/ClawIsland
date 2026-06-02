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

struct SubAgent: Identifiable {
    var id: String { agentId }
    let agentId: String
    let agentType: String
    let description: String
    let sessionId: String   // parent session ID
    let cwd: String         // parent session cwd (for building .jsonl path)
}

@Observable
class SessionState {
    static let shared = SessionState()
    
    var currentPayload: HookPayload?
    var sessionPayloads: [String: HookPayload] = [:]
    var sessionHistories: [String: String] = [:]
    var sessionMetrics: [String: SessionMetrics] = [:]
    var sessionMessages: [String: [SessionMessage]] = [:]
    var sessionSubAgents: [String: [SubAgent]] = [:]
    var subAgentMessages: [String: [SessionMessage]] = [:]
    var subAgentMetrics: [String: SessionMetrics] = [:]

    var isExpanded: Bool = false
    var expandedSessionId: String? = nil
    var expandedSubAgentId: String? = nil
    var statusText: String = "Monitoring..."
    var socketConnection: FileHandle?
    var activeProcessCount: Int = 0
    var activeSessions: [ActiveSession] = []
    
    private var processTimer: Timer?
    private var isCheckingProcesses = false

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
    
    private func fetchSubAgents(cwd: String, sessionId: String) -> [SubAgent] {
        let dashedCwd = cwd.replacingOccurrences(of: "[^a-zA-Z0-9-]", with: "-", options: .regularExpression)
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let subagentsURL = homeDir.appendingPathComponent(".claude/projects/\(dashedCwd)/\(sessionId)/subagents")

        guard let contents = try? fileManager.contentsOfDirectory(at: subagentsURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var agents: [SubAgent] = []
        let metaFiles = contents.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("agent-") }

        for metaURL in metaFiles {
            guard let data = try? Data(contentsOf: metaURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let agentType = json["agentType"] as? String,
                  let desc = json["description"] as? String else { continue }

            // Extract agentId from filename: agent-{agentId}.meta.json
            let filename = metaURL.deletingPathExtension().lastPathComponent // agent-{agentId}.meta
            let metaSuffix = ".meta"
            let agentFileName: String
            if filename.hasSuffix(metaSuffix) {
                agentFileName = String(filename.dropLast(metaSuffix.count)) // agent-{agentId}
            } else {
                agentFileName = filename
            }
            let agentId = String(agentFileName.dropFirst("agent-".count))

            agents.append(SubAgent(
                agentId: agentId,
                agentType: agentType,
                description: desc,
                sessionId: sessionId,
                cwd: cwd
            ))
        }

        return agents
    }

    private func fetchSubAgentHistory(cwd: String, sessionId: String, agentId: String) -> (String?, SessionMetrics, [SessionMessage]) {
        let dashedCwd = cwd.replacingOccurrences(of: "[^a-zA-Z0-9-]", with: "-", options: .regularExpression)
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let jsonlURL = homeDir.appendingPathComponent(".claude/projects/\(dashedCwd)/\(sessionId)/subagents/agent-\(agentId).jsonl")

        let path = jsonlURL.path
        if let attrs = try? fileManager.attributesOfItem(atPath: path),
           let currentSize = attrs[.size] as? UInt64 {
            let cacheKey = "sub_\(agentId)"
            if let lastSize = lastFileSizes[cacheKey], lastSize == currentSize, let cached = cachedHistoryData[cacheKey] {
                return cached
            }
            lastFileSizes[cacheKey] = currentSize
        } else {
            return (nil, SessionMetrics(), [])
        }

        var metrics = SessionMetrics()
        var lastStatus: String? = nil
        var messages: [SessionMessage] = []

        guard let data = try? Data(contentsOf: jsonlURL),
              let content = String(data: data, encoding: .utf8) else { return (nil, metrics, []) }

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
        let cacheKey = "sub_\(agentId)"
        cachedHistoryData[cacheKey] = result
        return result
    }

    private func checkClaudeProcesses() {
        guard !isCheckingProcesses else { return }
        isCheckingProcesses = true

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

                // Phase 1: Show session list immediately with basic info
                DispatchQueue.main.async {
                    self.activeSessions = validSessions
                    self.activeProcessCount = validSessions.count

                    if self.currentPayload == nil {
                        if validSessions.count > 0 {
                            let lastCwd = validSessions.first?.cwd.components(separatedBy: "/").last ?? "Unknown"
                            self.statusText = "\(validSessions.count) Session\(validSessions.count > 1 ? "s" : "") (\(lastCwd))"
                        } else {
                            self.statusText = "Idle"
                        }
                    }
                }

                // Phase 2: Load history per session, dispatch incrementally
                for session in validSessions {
                    let (hist, met, msgs) = self.fetchHistoryAndMetrics(cwd: session.cwd, sessionId: session.sessionId)

                    let subAgents = self.fetchSubAgents(cwd: session.cwd, sessionId: session.sessionId)
                    var subHistories: [String: String] = [:]
                    var subMet: [String: SessionMetrics] = [:]
                    var subMsgs: [String: [SessionMessage]] = [:]
                    for sa in subAgents {
                        let (saHist, saMet, saMsgs) = self.fetchSubAgentHistory(cwd: sa.cwd, sessionId: sa.sessionId, agentId: sa.agentId)
                        subMet[sa.agentId] = saMet
                        if !saMsgs.isEmpty { subMsgs[sa.agentId] = saMsgs }
                        if let h = saHist { subHistories["sub_\(sa.agentId)"] = h }
                    }

                    DispatchQueue.main.async {
                        if let h = hist { self.sessionHistories[session.sessionId] = h }
                        self.sessionMetrics[session.sessionId] = met
                        self.sessionMessages[session.sessionId] = msgs
                        if !subAgents.isEmpty { self.sessionSubAgents[session.sessionId] = subAgents }
                        for (k, v) in subHistories { self.sessionHistories[k] = v }
                        for (k, v) in subMet { self.subAgentMetrics[k] = v }
                        for (k, v) in subMsgs { self.subAgentMessages[k] = v }
                    }
                }

                DispatchQueue.main.async {
                    self.isCheckingProcesses = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isCheckingProcesses = false
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

        // Auto-dismiss stale PermissionRequest only when a session-advancing event arrives,
        // indicating the user already responded in the terminal.
        let sessionAdvancingEvents = ["UserPromptSubmit", "Stop", "SessionEnd"]
        if let currentEvent = self.currentPayload?.hookEventName,
           currentEvent == "PermissionRequest",
           let newEvent = payload.hookEventName,
           sessionAdvancingEvents.contains(newEvent) {
            self.socketConnection = nil
            self.currentPayload = nil
            self.isExpanded = false
        }

        let ignoredVisualEvents = ["PreToolUse", "PostToolUse", "PostToolUseFailure"]
        if !ignoredVisualEvents.contains(payload.hookEventName ?? "") {
            self.currentPayload = payload
            self.statusText = payload.hookEventName ?? "Processing..."
        }
        if payload.hookEventName == "PermissionRequest" {
            self.socketConnection = connection
        }
        
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
            self.isExpanded = false
            self.currentPayload = nil
            self.socketConnection = nil
            self.statusText = "Connection closed"
        }
    }
    
    @MainActor
    func replyToQuestion(answer: String, question: String) {
        guard let connection = socketConnection else { return }

        // Build updatedInput that preserves the original questions array,
        // because updatedInput REPLACES the entire tool input.
        var updatedInput: [String: Any] = ["answers": [question: answer]]
        if let payload = currentPayload,
           let questions = payload.toolInput?.questions {
            let encoder = JSONEncoder()
            if let questionsData = try? encoder.encode(questions),
               let questionsArray = try? JSONSerialization.jsonObject(with: questionsData) {
                updatedInput["questions"] = questionsArray
            }
        }

        let rootNode: [String: Any] = [
            "continue": true,
            "suppressOutput": true,
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": "allow",
                    "updatedInput": updatedInput
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
            self.isExpanded = false
            self.currentPayload = nil
            self.socketConnection = nil
            self.statusText = "Connection closed"
        }
    }
}
