import SwiftUI
import AppKit

// MARK: - Navigation Model

enum SettingsPage: String, Identifiable, Hashable {
    case general
    case appearance
    case sound
    case advanced

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "sparkles.tv"
        case .sound: return "speaker.wave.2.fill"
        case .advanced: return "terminal.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .purple
        case .sound: return .green
        case .advanced: return .orange
        }
    }
    
    var title: String {
        switch self {
        case .general: return "常驻与动作"
        case .appearance: return "外观与形象"
        case .sound: return "声音与提示"
        case .advanced: return "调试配置"
        }
    }
}

// MARK: - Main View

struct SettingsView: View {
    @State private var selectedPage: SettingsPage = .sound

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Section {
                    SidebarRow(page: .sound).tag(SettingsPage.sound)
                    SidebarRow(page: .appearance).tag(SettingsPage.appearance)
                    SidebarRow(page: .general).tag(SettingsPage.general)
                } header: {
                    Text("界面与感知")
                }
                
                Section {
                    SidebarRow(page: .advanced).tag(SettingsPage.advanced)
                } header: {
                    Text("核心引擎")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedPage {
                case .sound: SoundPage()
                case .appearance: AppearanceSettingsView()
                case .general: GeneralSettingsView()
                case .advanced: AdvancedSettingsView()
                }
            }
        }
        .frame(width: 760, height: 500)
    }
}

private struct SidebarRow: View {
    let page: SettingsPage

    var body: some View {
        Label {
            Text(page.title)
                .font(.system(size: 13))
                .padding(.leading, 2)
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(page.color.gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: page.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}


// MARK: - Sound Page

private struct SoundPage: View {
    @AppStorage(SoundSettingsKey.soundEnabled) private var soundEnabled = true
    @AppStorage(SoundSettingsKey.soundVolume) private var soundVolume = 80
    @AppStorage(SoundSettingsKey.soundSessionStart) private var soundSessionStart = true
    @AppStorage(SoundSettingsKey.soundTaskComplete) private var soundTaskComplete = true
    @AppStorage(SoundSettingsKey.soundTaskError) private var soundTaskError = true
    @AppStorage(SoundSettingsKey.soundApprovalNeeded) private var soundApprovalNeeded = true
    @AppStorage(SoundSettingsKey.soundPromptSubmit) private var soundPromptSubmit = true

    var body: some View {
        Form {
            Section {
                Toggle("启用音效系统", isOn: $soundEnabled)
                if soundEnabled {
                    HStack(spacing: 8) {
                        Text("系统音量")
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(soundVolume) },
                                set: { soundVolume = Int($0) }
                            ),
                            in: 0...100,
                            step: 5
                        )
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(soundVolume)%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }

            if soundEnabled {
                Section("工作流感知 (Sessions)") {
                    SoundEventRow(title: "引擎启动", subtitle: "引擎被初始化创建时", soundName: "8bit_start", isOn: $soundSessionStart)
                    SoundEventRow(title: "任务完成", subtitle: "模型任务执行完毕", soundName: "8bit_complete", isOn: $soundTaskComplete)
                    SoundEventRow(title: "任务报错", subtitle: "遭遇解析或执行错误", soundName: "8bit_error", isOn: $soundTaskError)
                }

                Section("用户交互体验 (Interactions)") {
                    SoundEventRow(title: "需您审批", subtitle: "引擎被阻断，等待您的点击授权", soundName: "8bit_approval", isOn: $soundApprovalNeeded)
                    SoundEventRow(title: "命令确认", subtitle: "向引擎成功派发操作指令", soundName: "8bit_submit", isOn: $soundPromptSubmit)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SoundEventRow: View {
    let title: String
    var subtitle: String? = nil
    let soundName: String
    @Binding var isOn: Bool
    @State private var customPath: String = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if customPath.isEmpty {
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("已覆盖为：\(URL(fileURLWithPath: customPath).lastPathComponent)")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 16)
            
            Menu {
                Button {
                    chooseCustomSound()
                } label: {
                    Label("浏览外部音频...", systemImage: "folder")
                }
                if !customPath.isEmpty {
                    Button {
                        clearCustomSound()
                    } label: {
                        Label("恢复系统默认", systemImage: "arrow.counterclockwise")
                    }
                }
            } label: {
                Image(systemName: customPath.isEmpty ? "waveform" : "waveform.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(customPath.isEmpty ? .secondary : Color.orange)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            
            Button {
                if !customPath.isEmpty {
                    SoundManager.shared.previewCustom(customPath)
                } else {
                    SoundManager.shared.preview(soundName)
                }
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .onAppear {
            customPath = UserDefaults.standard.string(forKey: SoundSettingsKey.soundCustomPath(soundName)) ?? ""
        }
    }

    private func chooseCustomSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            customPath = url.path
            UserDefaults.standard.set(url.path, forKey: SoundSettingsKey.soundCustomPath(soundName))
        }
    }

    private func clearCustomSound() {
        customPath = ""
        UserDefaults.standard.removeObject(forKey: SoundSettingsKey.soundCustomPath(soundName))
    }
}

// MARK: - Legacy Settings Ported to Form

struct AppearanceSettingsView: View {
    @AppStorage("iconTheme") private var iconTheme: String = "claude"
    @State private var previewStatus: AgentStatus = .processing
    @AppStorage(SettingsKey.mascotSpeed) private var mascotSpeed = SettingsDefaults.mascotSpeed

    private let mascotList: [(name: String, source: String, desc: String, color: Color)] = [
        ("Clawd", "claude", "Claude Code", Color(red: 0.871, green: 0.533, blue: 0.427)),
        ("Dex", "codex", "Codex (OpenAI)", Color(red: 0.92, green: 0.92, blue: 0.93)),
        ("Gemini", "gemini", "Gemini CLI", Color(red: 0.278, green: 0.588, blue: 0.894)),
        ("CursorBot", "cursor", "Cursor", Color(red: 0.96, green: 0.31, blue: 0.0)),
        ("TraeBot", "trae", "Trae", Color(red: 0.96, green: 0.31, blue: 0.0)),
        ("CopilotBot", "copilot", "GitHub Copilot", Color(red: 0.35, green: 0.75, blue: 0.95)),
        ("QoderBot", "qoder", "Qoder", Color(red: 0.165, green: 0.859, blue: 0.361)),
        ("Droid", "droid", "Factory", Color(red: 0.835, green: 0.416, blue: 0.149)),
        ("Buddy", "codebuddy", "CodeBuddy", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("StepFun", "stepfun", "StepFun", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("AntiGravity", "antigravity", "AntiGravity", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("WorkBuddy", "workbuddy", "WorkBuddy", Color(red: 0.475, green: 0.380, blue: 0.870)),
        ("Hermes", "hermes", "Hermes", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("QwenBot", "qwen", "Qwen Code", Color(red: 0.486, green: 0.228, blue: 0.929)),
        ("KimiBot", "kimi", "Kimi Code CLI", Color(red: 0.29, green: 0.56, blue: 1.0)),
        ("OpBot", "opencode", "OpenCode", Color(red: 0.55, green: 0.55, blue: 0.57)),
    ]

    var body: some View {
        Form {
            Section("预览状态及速度设置") {
                Picker("动画状态", selection: $previewStatus) {
                    Text("处理中 (打字等)").tag(AgentStatus.processing)
                    Text("空闲 (呼吸/待机)").tag(AgentStatus.idle)
                    Text("权限等待 (惊吓)").tag(AgentStatus.waitingApproval)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("动画播放速度")
                    Spacer()
                    Text(mascotSpeed == 0 ? "静止" : String(format: "%.1f×", Double(mascotSpeed) / 100.0))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(mascotSpeed) },
                    set: { mascotSpeed = Int($0) }
                ), in: 0...300, step: 25)
            }

            Section("选择状态引擎 Mascot") {
                ForEach(mascotList, id: \.source) { mascot in
                    Button(action: {
                        withAnimation { iconTheme = mascot.source }
                    }) {
                        MascotSettingsRow(
                            name: mascot.name,
                            source: mascot.source,
                            desc: mascot.desc,
                            color: mascot.color,
                            status: previewStatus,
                            isSelected: iconTheme == mascot.source
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct MascotSettingsRow: View {
    let name: String
    let source: String
    let desc: String
    let color: Color
    let status: AgentStatus
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(isSelected ? 0.3 : 1.0))
                    .frame(width: 56, height: 56)
                MascotView(source: source, status: status, size: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
                    .font(.system(size: 14, weight: .bold))
            }
        }
        .padding(.vertical, 4)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("autoCollapseDuration") private var autoCollapseDuration: Double = 3.0
    
    var body: some View {
        Form {
            Section("行为") {
                Toggle("随系统开机自动运行", isOn: $launchAtLogin)
            }
            
            Section {
                HStack {
                    Text("操作闲置折叠时长 (\(String(format: "%.1f", autoCollapseDuration))s)")
                    Spacer()
                    Slider(value: $autoCollapseDuration, in: 1.0...10.0, step: 0.5).frame(width: 200)
                }
            } footer: {
                Text("无活动状态时，通知面板将自动收缩回刘海槽的时间。")
            }
        }
        .formStyle(.grouped)
    }
}

struct AdvancedSettingsView: View {
    @AppStorage("enableDebugMode") private var enableDebugMode: Bool = false
    
    var body: some View {
        Form {
            Section("沙盒实验室（危险区）") {
                Toggle("挂载终端日志钩子 (输出至临时目录)", isOn: $enableDebugMode)
            }
        }
        .formStyle(.grouped)
    }
}
