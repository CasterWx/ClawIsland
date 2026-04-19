# ClawIsLand 整体架构说明

## 项目描述
ClawIsLand 是一个为 Claude Code 设计的 macOS 刘海屏（Notch）悬浮监控与交互应用。它的主要目的是将终端的后台代理运行状态反映到系统顶部的全局悬浮面板中，提供即时的交互无需切换窗口。

## 技术栈与核心组件
- **语言**：Swift 6 (AppKit + SwiftUI)、Python (Hook CLI)
- **架构设计**：
  - **无 Dock 图标的守护态运行**（LSUIElement）：通过控制 `NSApp.setActivationPolicy(.accessory)` 来实现。
  - **通讯机制（BridgeServer.swift）**：内建基于 Unix Domain Socket 的本地通信服务端，默认监听 `/tmp/clawisland.sock`。用于和 Hook 层进行全双工通信（接收事件 + 返回授权指令）。
  - **数据层（SessionState.swift）**：`@Observable` 全局状态管理，以 JSON 对象的形式反序列化 Claude Code 事件流（SessionStart, PermissionRequest 等），控制 UI 折叠与重绘。
  - **表现层（NotchWindowController.swift & ContentView.swift）**：封装一个不被激活且在所有 App 上方的透明 `NSPanel` 承载 SwiftUI 视图，利用弹簧动画模拟系统的 Dynamic Island 展开折叠效果。
  - **代理客户端（clawisland-hook.py）**：配置入 `~/.claude/settings.json` 的钩子程序，负责承接 Claude Code `stdin` 发出的 JSON，利用 Socket 推送至 BridgeServer，并负责回传处理结果给 Claude Code。

## 数据交互全流程
1. **Hook 注入**: Claude Code 后台产生 `PermissionRequest` 事件，唤起 `clawisland-hook.py`。
2. **IPC 转发**: Python 脚本通过 Socket `/tmp/clawisland.sock` 发送 JSON Payload，阻塞等待 App 的响应。
3. **App 渲染**: `BridgeServer` 反序列化接管事件，通知 `@Observable SessionState`，`ContentView` 执行展开动画并在 Notch 内提供 `Allow/Deny` 按钮操作区。
4. **决策回传**: 用户点击后，App 通过 Socket 发送确认指令回原连接。Python 脚本捕获并利用标准输出回传给 Claude Code 实现通过或终止。

## 目录结构
- `/ClawIsLand`：SwiftUI + AppKit 源码和应用资源
  - `ClawIsLandApp.swift`：应用入口，重写启动逻辑，配置 Notch Panel
  - `BridgeServer.swift`：Socket 服务端
  - `SessionState.swift`：JSON DTO 模型与响应状态树
  - `NotchWindowController.swift`：构建 NSPanel
  - `ContentView.swift`：SwiftUI 刘海屏视觉
- `/ARCHITECTURE.md`：本文件
- `clawisland-hook.py`：需要被部署的 hook 拦截处理中间件
