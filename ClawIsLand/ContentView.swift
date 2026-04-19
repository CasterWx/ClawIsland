import SwiftUI
import MarkdownUI

extension Theme {
    static func clawTheme(baseColor: Color) -> Theme {
        Theme()
            .text {
                ForegroundColor(baseColor)
                FontSize(11)
                FontFamily(.system(.rounded))
            }
            .strong {
                FontWeight(.bold)
            }
            .heading1 { configuration in
                configuration.label.markdownMargin(top: 8, bottom: 4)
            }
            .code {
                FontFamilyVariant(.monospaced)
                ForegroundColor(Color.orange)
                BackgroundColor(Color.black.opacity(0.3))
            }
            .codeBlock { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .padding(8)
                }
                .background(Color.black.opacity(0.4))
                .cornerRadius(6)
                .markdownMargin(top: 6, bottom: 6)
            }
            .heading2 { configuration in
                configuration.label.markdownMargin(top: 6, bottom: 4)
            }
            .heading3 { configuration in
                configuration.label.markdownMargin(top: 4, bottom: 4)
            }
            .blockquote { configuration in
                configuration.label
                    .padding(8)
                    .padding(.leading, 12)
                    .background(Color.white.opacity(0.05))
                    .overlay(
                        Rectangle()
                            .fill(baseColor.opacity(0.6))
                            .frame(width: 3),
                        alignment: .leading
                    )
                    .markdownMargin(top: 6, bottom: 6)
            }
            .table { configuration in
                configuration.label
                    .markdownTableBorderStyle(TableBorderStyle(color: baseColor.opacity(0.2), width: 1))
                    .markdownTableBackgroundStyle(.alternatingRows(Color.white.opacity(0.05), Color.clear, header: Color.white.opacity(0.1)))
                    .markdownMargin(top: 6, bottom: 6)
            }
    }
}



struct NotchShape: Shape {
    var topFillet: CGFloat = 16
    var bottomRadius: CGFloat = 24
    
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let tf = topFillet
        let br = bottomRadius
        
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: tf, y: tf), control: CGPoint(x: tf, y: 0))
        p.addLine(to: CGPoint(x: tf, y: h - br))
        p.addQuadCurve(to: CGPoint(x: tf + br, y: h), control: CGPoint(x: tf, y: h))
        p.addLine(to: CGPoint(x: w - tf - br, y: h))
        p.addQuadCurve(to: CGPoint(x: w - tf, y: h - br), control: CGPoint(x: w - tf, y: h))
        p.addLine(to: CGPoint(x: w - tf, y: tf))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - tf, y: 0))
        p.addLine(to: CGPoint(x: 0, y: 0))
        
        return p
    }
}

struct DynamicHeightScrollView<Content: View>: View {
    let maxHeight: CGFloat
    let content: Content

    @State private var innerHeight: CGFloat = 10.0 // Start small, let GeometryReader expand it natively

    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ViewHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .frame(height: min(maxHeight, innerHeight))
        .onPreferenceChange(ViewHeightKey.self) { height in
            // Add a tiny buffer (4 points) to prevent exact boundary decimal clipping jitters
            innerHeight = height > 0 ? height + 4 : height
        }
    }
}

struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 10.0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ContentView: View {
    @Bindable var state = SessionState.shared
    @AppStorage("iconTheme") private var iconTheme: String = "ambientCore"
    @AppStorage("isPinned") private var isPinned: Bool = false
    @State private var isHovering: Bool = false
    @State private var pulseEffect: Bool = false
    @State private var newlyAddedTaskEffect: Bool = false
    @State private var hoverTask: Task<Void, Never>? = nil
    // Icon animation states
    @State private var neonRotation: Double = 0
    @State private var pixelFrame: Int = 0
    @State private var matrixOffset: CGFloat = 0
    @State private var dnaOffset: Bool = false
    @State private var orbScale: CGFloat = 0.8
    @State private var claudeRotation: Double = 0
    
    // Derived properties for UI bindings
    private var isTaskRunning: Bool {
        return state.activeProcessCount > 0 || state.isExpanded || state.currentPayload != nil
    }
    
    private var isExpandedState: Bool {
        isHovering || state.isExpanded || isPinned
    }
    
    private var indicatorColor: Color {
        if state.isExpanded {
            return .orange
        } else if isTaskRunning {
            return .green
        }
        return .gray
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Padding gap so content sits safely below the physical MacBook notch
            Color.clear.frame(height: isExpandedState ? 32 : 0)
                .overlay(alignment: .trailing) {
                    if isExpandedState {
                        HStack(spacing: 8) {
                            Button(action: {
                                isPinned.toggle()
                            }) {
                                Image(systemName: isPinned ? "pin.fill" : "pin")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isPinned ? .orange : .white.opacity(0.4))
                                    .padding(4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                NotificationCenter.default.post(name: .init("toggleSettingsWindow"), object: nil)
                            }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, 24)
                    }
                }
                .clipped()
            
            // Header / Compact State
            if !isExpandedState || state.currentPayload != nil {
                HStack(spacing: 12) {
                if !isExpandedState {
                    // Compact Ear Mode: Left Ear (Left side of the 440 width box)
                    HStack(spacing: 6) {
                        dynamicIcon()
                            .frame(width: 20, height: 20, alignment: .center)
                    }
                    
                    Spacer()
                    
                    // Compact Ear Mode: Right Ear
                    if state.activeProcessCount > 0 {
                        if newlyAddedTaskEffect {
                            Text("✨")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .scale.combined(with: .opacity)))
                        } else {
                            Text("\(state.activeProcessCount)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .contentTransition(.numericText())
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .scale.combined(with: .opacity)))
                        }
                    } else {
                        Text("Idle")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                } else {
                    // Expanded Header Mode (Below the Notch)
                    if state.currentPayload == nil {
                        ClaudeLogo(size: 18)
                            .shadow(color: isTaskRunning ? Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.8) : .clear, radius: 4)
                    }
                    
                    Spacer()
                    
                    if state.activeProcessCount > 0 {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    }
                    
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, (isExpandedState && state.currentPayload != nil) ? 0 : 9)
            .contentShape(Rectangle())
            .onTapGesture {
                if state.currentPayload != nil {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        state.isExpanded.toggle()
                    }
                }
            }
            } // Close condition for Notch Header
            // Settings overlay moved to ZStack directly to decouple from vertical flow
            
            // Expanded Content (Tool Requests / Streaming / Errors / Sessions)
            if let payload = state.currentPayload {
                PayloadDetailView(payload: payload, state: state)
            } else if isExpandedState && !state.activeSessions.isEmpty && state.currentPayload == nil {
                ActiveSessionsListView(sessions: state.activeSessions)
            }
        }
        .frame(width: isExpandedState ? 700 : 320)
        .animation(.easeInOut(duration: 0.35), value: isExpandedState)
        .animation(.easeInOut(duration: 0.3), value: state.currentPayload != nil)
        .contentShape(NotchShape(topFillet: 8, bottomRadius: 20))
        // Bake the shadow into the vector shape directly to prevent macOS CoreAnimation square-mask flickering
        .background(
            NotchShape(topFillet: 8, bottomRadius: 20)
                .fill(Color.black.opacity(isExpandedState ? 0.96 : 1.0))
                .shadow(color: .black.opacity(0.8), radius: 14, x: 0, y: 6)
        )
        .clipShape(NotchShape(topFillet: 8, bottomRadius: 20))
        .onChange(of: isExpandedState) { _, expanded in
            NotchContentTracker.shared.contentWidth = expanded ? 700 : 320
            NotchContentTracker.shared.contentHeight = expanded ? 500 : 40
        }
        .onAppear {
            NotchContentTracker.shared.contentWidth = isExpandedState ? 700 : 320
            NotchContentTracker.shared.contentHeight = isExpandedState ? 500 : 40
        }
        .overlay(
            NotchShape(topFillet: 8, bottomRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onHover { hover in
            hoverTask?.cancel()
            hoverTask = Task {
                if !hover {
                    // Brief debounce to prevent flicker from rapid hover state changes
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    
                    // Check if mouse is actually over the visible notch content area,
                    // NOT the entire transparent 800x700 canvas window.
                    let mouseLoc = NSEvent.mouseLocation
                    let isActuallyInside = await MainActor.run {
                        guard let screen = NSScreen.screens.first else { return false }
                        let screenTop = screen.frame.maxY
                        let contentWidth: CGFloat = isExpandedState ? 700 : 320
                        let contentHeight: CGFloat = isExpandedState ? 500 : 40
                        let centerX = screen.frame.midX
                        // The notch visual rect: centered horizontally, hanging from screen top
                        let notchRect = NSRect(
                            x: centerX - contentWidth / 2 - 20,  // margin
                            y: screenTop - contentHeight - 20,     // margin
                            width: contentWidth + 40,
                            height: contentHeight + 20
                        )
                        return notchRect.contains(mouseLoc)
                    }
                    if isActuallyInside { return }
                }
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    if isHovering != hover {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isHovering = hover
                    }
                }
            }
        }
        .onChange(of: state.activeProcessCount) { old, new in
            if new > old {
                // New task joined!
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    newlyAddedTaskEffect = true
                }
                
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await MainActor.run {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            newlyAddedTaskEffect = false
                        }
                    }
                }
            }
        }
        .onChange(of: state.latestSoundTrigger?.1) { _, _ in
            if let trigger = state.latestSoundTrigger {
                SoundManager.shared.playSound(for: trigger.0)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    
    @ViewBuilder
    func dynamicIcon() -> some View {
        let currentStatus: AgentStatus = {
            if !isTaskRunning { return .idle }
            if state.currentPayload?.hookEventName == "PermissionRequest" { return .waitingApproval }
            if state.statusText.lowercased().contains("ask") || state.statusText.lowercased().contains("question") { return .waitingQuestion }
            return .processing
        }()
        
        MascotView(source: iconTheme, status: currentStatus, size: 24)
            .shadow(color: isTaskRunning ? .white.opacity(0.3) : .clear, radius: 4)
    }
}

struct PayloadDetailView: View {
    let payload: HookPayload
    var state: SessionState
    
    var body: some View {
        let cwdName = (payload.cwd ?? "").components(separatedBy: "/").last ?? ""
        let message = payload.prompt ?? payload.title ?? payload.message ?? payload.lastAssistantMessage ?? state.statusText
        
        VStack(alignment: .leading, spacing: 0) {
            
            if payload.hookEventName == "PermissionRequest" {
                if payload.toolName == "AskUserQuestion", let questions = payload.toolInput?.questions, let primaryQuestion = questions.first {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            if #available(macOS 14.0, *) {
                                Image(systemName: "questionmark.bubble.fill")
                                    .foregroundColor(.blue)
                                    .symbolEffect(.pulse, options: .repeating)
                            } else {
                                Image(systemName: "questionmark.bubble.fill")
                                    .foregroundColor(.blue)
                            }
                            Text("Agent 提问: \(primaryQuestion.header ?? "需要您的决定")")
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        
                        Text(primaryQuestion.question)
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .padding(.bottom, 4)
                            
                        if let options = primaryQuestion.options, !options.isEmpty {
                            VStack(spacing: 6) {
                                ForEach(options, id: \.self) { option in
                                    Button(action: {
                                        state.replyToQuestion(answer: option.label, question: primaryQuestion.question)
                                    }) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.label)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.white)
                                            if let desc = option.description, !desc.isEmpty {
                                                Text(desc)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.white.opacity(0.5))
                                                    .lineLimit(2)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color.white.opacity(0.05))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            // Fallback if no options
                            HStack {
                                Text("此问题需要在终端回复...")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Button(action: { state.replyToHook(allow: true) }) {
                                    Text("放行")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.4))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    .background(Color.black.opacity(0.9))
                } else {
                    // Minimalist Tool Request Block
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            if #available(macOS 14.0, *) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .symbolEffect(.pulse, options: .repeating)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            }
                            Text("高危权限请求: \(payload.toolName ?? "Tool")")
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        
                        let preview = payload.toolInput?.command ?? payload.toolInput?.file_path ?? payload.toolInput?.query ?? payload.toolInput?.code
                        if let previewContent = preview {
                            Text("> \(previewContent)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(2)
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: { state.replyToHook(allow: false) }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("拒绝(⌘N)")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.3), lineWidth: 1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut("n", modifiers: .command)
                            
                            Button(action: { state.replyToHook(allow: true) }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("允许并继续(⌘Y)")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.4), lineWidth: 1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut("y", modifiers: .command)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    .background(Color.black.opacity(0.9))
                }
                
            } else if payload.hookEventName == "Error" {
                VStack(alignment: .leading, spacing: 4) {
                    Text("[ERR]").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.red)
                    Text("> \(payload.prompt ?? "Unknown Error")").font(.system(size: 10, design: .monospaced)).foregroundColor(.red.opacity(0.6))
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .background(Color.black.opacity(0.9))
                
            } else if payload.hookEventName == "Stop" {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                        Text("任务执行结束").font(.system(size: 11, weight: .bold)).foregroundColor(.green)
                    }
                    DynamicHeightScrollView(maxHeight: 250) {
                        Markdown(message)
                            .markdownTheme(.clawTheme(baseColor: .white.opacity(0.9)))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.3), lineWidth: 1))
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .background(Color.black.opacity(0.9))
            } else {
                // Option A: Extreme Minimalist
                VStack(alignment: .leading, spacing: 6) {
                    if !cwdName.isEmpty {
                        Text("[\(cwdName)]")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    
                    HStack(alignment: .top, spacing: 8) {
                        let tagInfo: (label: String, color: Color) = {
                            let name = payload.hookEventName ?? ""
                            if name.contains("Prompt") || name == "UserPromptSubmit" { return ("用户指令", .blue) }
                            if name == "PermissionRequest" { return ("权限请求", .orange) }
                            if name == "Error" { return ("系统异常", .red) }
                            if name == "ToolUse" || name == "ToolResult" { return ("工具调用", .purple) }
                            if name == "AssistantMessage" { return ("模型回复", .cyan) }
                            if name.contains("Process") { return ("后台进程", .gray) }
                            return ("系统消息", .gray)
                        }()
                        
                        Text(tagInfo.label)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tagInfo.color.opacity(0.2))
                            .foregroundColor(tagInfo.color)
                            .cornerRadius(4)
                        
                        Text(message.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(3)
                            .padding(.top, 1)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.85))
            }
        }
    }
}

struct ActiveSessionsListView: View {
    let sessions: [ActiveSession]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)
            VStack(spacing: 8) {
                ForEach(sessions) { session in
                    SessionRowView(session: session)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}

func formatTokenString(_ count: Int) -> String {
    if count == 0 { return "0" }
    if count >= 1_000_000 {
        return String(format: "%.1fM", Double(count) / 1000000.0)
    } else if count >= 1000 {
        return String(format: "%.1fK", Double(count) / 1000.0)
    }
    return "\(count)"
}

struct MetricLabel: View {
    let icon: String
    let text: String
    var color: Color = .white.opacity(0.6)
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.06))
        .cornerRadius(3)
    }
}

struct SessionRowView: View {
    let session: ActiveSession
    var state = SessionState.shared
    
    @State private var isHovered: Bool = false
    
    // Helper to extract 3 turns (user -> assistant)
    private func getRecentTurns(from messages: [SessionMessage], limit: Int = 3) -> [SessionMessage] {
        var userCount = 0
        var startIndex = 0
        for i in stride(from: messages.count - 1, through: 0, by: -1) {
            if messages[i].role == "user" {
                userCount += 1
                if userCount >= limit {
                    startIndex = i
                    break
                }
            }
        }
        return Array(messages[startIndex...])
    }
    
    var body: some View {
        let isDetailExpanded = (state.expandedSessionId == session.sessionId)
        let pathComponents = session.cwd.components(separatedBy: "/")
        let name = pathComponents.last ?? session.cwd
        let parent = pathComponents.dropLast().last ?? ""
        let payload = state.sessionPayloads[session.sessionId]
        let msgs = state.sessionMessages[session.sessionId] ?? []
        
        let uptimeStr = getUptimeString(from: session.startedAt)
        
        let statusMsg: String = {
            if let p = payload {
                let text = p.prompt ?? p.title ?? p.message ?? p.lastAssistantMessage ?? "Idle / Running in background"
                return text.replacingOccurrences(of: "\n", with: " ")
            } else if let hist = state.sessionHistories[session.sessionId] {
                return hist.replacingOccurrences(of: "\n", with: " ")
            }
            return "Idle / Running in background"
        }()
        
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ClaudeLogo(size: 14)
                        .shadow(color: Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.8), radius: 2)
                    
                    Text("[ \(!parent.isEmpty && parent != NSUserName() ? "\(parent)/" : "")\(name) ]")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        
                    Spacer()
                    
                    if let m = state.sessionMetrics[session.sessionId] {
                        HStack(spacing: 4) {
                            MetricLabel(icon: "arrow.down.circle", text: "I/Token:\(formatTokenString(m.inputTokens))", color: .cyan)
                            MetricLabel(icon: "arrow.up.circle", text: "O/Token:\(formatTokenString(m.outputTokens))", color: .orange)
                            MetricLabel(icon: "hammer.fill", text: "TLS:\(m.toolCalls)", color: .purple)
                            MetricLabel(icon: "arrow.2.squarepath", text: "Turns:\(msgs.filter({ $0.role == "user" }).count)", color: .blue)
                        }
                    }
                        
                    if let ep = session.entrypoint {
                        let isCLI = ep.lowercased().contains("cli")
                        Text(isCLI ? "CLI" : "SDK")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(isCLI ? Color.purple.opacity(0.4) : Color.blue.opacity(0.4))
                            .foregroundColor(isCLI ? .purple : .blue)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(isCLI ? Color.purple.opacity(0.8) : Color.blue.opacity(0.8), lineWidth: 1))
                            .cornerRadius(3)
                    }
                    
                    Text(uptimeStr)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                HStack(alignment: .top, spacing: 6) {
                    Text("▶︎")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 1)
                    
                    Text(statusMsg)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.leading, 14)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            
            let hasFinalPayload = (payload?.hookEventName == "Stop" && !(payload?.lastAssistantMessage ?? "").isEmpty) || (payload?.hookEventName == "Error" && !(payload?.prompt ?? "").isEmpty)
            
            if isDetailExpanded && (!msgs.isEmpty || hasFinalPayload) {
                VStack(alignment: .leading, spacing: 8) {
                    let filteredMsgs = getRecentTurns(from: msgs, limit: 3)
                    
                    if msgs.count > filteredMsgs.count {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 9))
                            Text("由于日志庞大，现仅为您渲染最近 3 轮交互核心上下文。")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.orange.opacity(0.8))
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                        .padding(.top, 4)
                    }
                    
                    DynamicHeightScrollView(maxHeight: 350) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(filteredMsgs) { msg in
                                ChatMessageBubble(msg: msg)
                            }
                            
                            FinalHookBubble(payload: payload, filteredMsgs: filteredMsgs)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.5))
            }
        }
        .background(isHovered ? Color.white.opacity(0.15) : Color.black.opacity(0.4))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.05)),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .onHover { hit in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hit
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if state.expandedSessionId == session.sessionId {
                    state.expandedSessionId = nil
                } else {
                    state.expandedSessionId = session.sessionId
                }
            }
        }
    }
    
    // Helper to calculate uptime
    private func getUptimeString(from startedAt: Int) -> String {
        let epochMs = TimeInterval(startedAt)
        let upDate = Date(timeIntervalSince1970: epochMs > 1_000_000_000_000 ? epochMs / 1000.0 : epochMs)
        let mins = max(0, Int(Date().timeIntervalSince(upDate) / 60))
        return mins < 60 ? "\(mins)m" : "\(mins / 60)h \(mins % 60)m"
    }
}

struct ChatMessageBubble: View {
    let msg: SessionMessage
    var body: some View {
        HStack {
            if msg.role == "user" {
                Spacer()
                Text(msg.content.count > 1000 ? String(msg.content.prefix(1000)) + "\n\n... [内容过长，自动截断防卡顿]" : msg.content)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(LinearGradient(gradient: Gradient(colors: [Color.pink.opacity(0.6), Color.purple.opacity(0.6)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.pink.opacity(0.8), lineWidth: 1))
            } else {
                Markdown(msg.content)
                    .markdownTheme(.clawTheme(baseColor: .cyan.opacity(0.9)))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.5), lineWidth: 1))
                Spacer()
            }
        }
        .padding(.horizontal, 14)
    }
}

struct FinalHookBubble: View {
    let payload: HookPayload?
    let filteredMsgs: [SessionMessage]
    
    var body: some View {
        if payload?.hookEventName == "Stop", let txt = payload?.lastAssistantMessage, !txt.isEmpty {
            if !(filteredMsgs.last?.content.contains(txt) ?? false) {
                HStack {
                    Markdown(txt)
                        .markdownTheme(.clawTheme(baseColor: .cyan.opacity(0.9)))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.cyan.opacity(0.15))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.5), lineWidth: 1))
                    Spacer()
                }
                .padding(.horizontal, 14)
            }
        } else if payload?.hookEventName == "Error", let txt = payload?.prompt, !txt.isEmpty {
            if !(filteredMsgs.last?.content.contains(txt) ?? false) {
                HStack {
                    Markdown(txt)
                        .markdownTheme(.clawTheme(baseColor: .red.opacity(0.9)))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.5), lineWidth: 1))
                    Spacer()
                }
                .padding(.horizontal, 14)
            }
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - Claude Logo (official sunburst from simple-icons, viewBox 0 0 24 24)

struct ClaudeLogo: View {
    var size: CGFloat = 22
    private static let color = Color(red: 0.85, green: 0.47, blue: 0.34) // #D97757

    // Official Claude logo SVG path (source: simple-icons)
    fileprivate static let svgPath = "m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"

    var body: some View {
        ClaudeLogoShape()
            .fill(Self.color)
            .frame(width: size, height: size)
    }
}

private struct ClaudeLogoShape: Shape {
    private static let basePath: Path = ClaudeLogoShape.parseSVGPath(ClaudeLogo.svgPath)

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return Self.basePath.applying(transform)
    }

    private static func parseSVGPath(_ d: String) -> Path {
        var path = Path()
        var x: CGFloat = 0, y: CGFloat = 0
        var i = d.startIndex
        var cmd: Character = "m"

        func skipWS() {
            while i < d.endIndex && (d[i] == " " || d[i] == ",") { i = d.index(after: i) }
        }

        func peekNum() -> Bool {
            guard i < d.endIndex else { return false }
            let c = d[i]
            return c == "-" || c == "." || c.isNumber
        }

        func num() -> CGFloat {
            skipWS()
            var s = ""
            if i < d.endIndex && d[i] == "-" { s.append(d[i]); i = d.index(after: i) }
            var hasDot = false
            while i < d.endIndex {
                let c = d[i]
                if c == "." {
                    if hasDot { break }
                    hasDot = true; s.append(c); i = d.index(after: i)
                } else if c.isNumber {
                    s.append(c); i = d.index(after: i)
                } else { break }
            }
            return CGFloat(Double(s) ?? 0)
        }

        while i < d.endIndex {
            skipWS()
            guard i < d.endIndex else { break }
            let c = d[i]
            if c.isLetter {
                cmd = c; i = d.index(after: i)
            }

            switch cmd {
            case "m":
                let dx = num(), dy = num(); x += dx; y += dy
                path.move(to: CGPoint(x: x, y: y))
                cmd = "l"
            case "M":
                x = num(); y = num()
                path.move(to: CGPoint(x: x, y: y))
                cmd = "L"
            case "l":
                let dx = num(), dy = num(); x += dx; y += dy
                path.addLine(to: CGPoint(x: x, y: y))
            case "L":
                x = num(); y = num()
                path.addLine(to: CGPoint(x: x, y: y))
            case "h":
                x += num(); path.addLine(to: CGPoint(x: x, y: y))
            case "H":
                x = num(); path.addLine(to: CGPoint(x: x, y: y))
            case "v":
                y += num(); path.addLine(to: CGPoint(x: x, y: y))
            case "V":
                y = num(); path.addLine(to: CGPoint(x: x, y: y))
            case "c":
                let dx1 = num(), dy1 = num(), dx2 = num(), dy2 = num(), dx = num(), dy = num()
                path.addCurve(to: CGPoint(x: x+dx, y: y+dy),
                              control1: CGPoint(x: x+dx1, y: y+dy1),
                              control2: CGPoint(x: x+dx2, y: y+dy2))
                x += dx; y += dy
            case "C":
                let x1 = num(), y1 = num(), x2 = num(), y2 = num()
                x = num(); y = num()
                path.addCurve(to: CGPoint(x: x, y: y),
                              control1: CGPoint(x: x1, y: y1),
                              control2: CGPoint(x: x2, y: y2))
            case "Z", "z":
                path.closeSubpath()
            default:
                i = d.index(after: i)
            }

            skipWS()
            if i < d.endIndex && peekNum() && "mlhvcMLHVC".contains(cmd) {
                continue
            }
        }
        return path
    }
}
