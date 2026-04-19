<h1 align="center">
  🐾 ClawIsLand
</h1>
<p align="center">
  <b>专为 Claude Code 打造的 macOS 灵动岛动态状态面板</b><br>
  <a href="#安装">安装</a> •
  <a href="#功能特性">功能</a> •
  <a href="#从源码构建">构建</a><br>
  <a href="README_en.md">English</a> | 简体中文
</p>

---

<p align="center">
  <!-- TODO: 后续请在此处补充刘海屏面板的实际效果截图 -->
  <img src="images/chat_list.png" width="700" alt="Panel Preview">
</p>

## ClawIsLand 是什么？

**ClawIsLand**是一个常驻于你 MacBook 灵动岛区域的轻量级工具。它就像是 Claude Code 的一间“透明实验室”。

当你使用 [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) (CLI) 结对编程时，无需再频繁穿梭于终端标签页和 IDE 之间。通过底层的进程 IPC 钩子，ClawIsLand 会实时捕获 Claude 的运行阶段（如思考中、处理完毕、等待授权、抛出错误等），并以生动的**像素风小动物（Mascots）**及**沉浸式 8-bit 音效**直接在屏幕顶端向你汇报。

---

## ✨ 功能特性

| 预览 | 描述 |
| --- | --- |
| ![chat_list](images/chat_list.png) | 聊天列表 |
| ![messages](images/messages.png) | 会话明细（支持markdown） |
| ![msg_notify](images/msg_notify.png) | 消息通知 |
| ![markdown](images/show_markdown.png) | 执行结果通知（支持markdown） |
| ![ask_question](images/ask_question.png) | AskQuestion 快速选择 |
| ![write](images/write.png) | 操作授权 |


- **灵动岛原生 UI** — 完美融入 MacBook 灵动岛。工作时自然丝滑展开，空闲时隐秘收起，绝不霸占你的屏幕空间。
- **纯粹为 Claude Code 优化** — 摒弃臃肿的兼容层，全神贯注于 Claude CLI 独有的任务模型，完美解析拦截授权（Permission Request）、对话暂停等关键环节。
- **生动像素角色引擎** — 不仅仅是一个红绿灯信号！内置了高品质的 Canvas 像素渲染引擎，包含 `Clawd`、`Dex`、`Droid` 等十几款可选小动物形象。它们会：
  - `空闲 (.idle)`：悠闲地呼吸、待机
  - `处理中 (.processing)`：埋头狂敲键盘流汗
  - `等待授权 (.waitingApproval)`：被突发事件惊吓并四处张望
- **沉浸式音效反馈** — 深度整合 App Sandbox 环境内安全的 `NSDataAsset` 音频引擎，提供 8-bit 复古街机音效（支持为会话开始、任务完成、报错、需要手动批准等操作独立配置铃声）。
- **专业设置面板** — 使用原生 macOS `NavigationSplitView` 打磨，支持界面上直接拉动滑块实时调节并预览吉祥物的生命活力。
- **100% Native 原生** — 无 Electron，无网页内嵌，使用 Swift + SwiftUI 原生应用开发，极度轻量且极度流畅。

---

## 🚀 安装与体验

如果你只是想开箱即用，可以直接将打包好的 `.app` 放入应用程序目录并运行。

> **提示：** 首次启动时，如果你遇到了安全限制，请前往 macOS 的 **系统设置 → 隐私与安全性** 中点击 **仍要打开** 即可。

### Hook 组件配置
ClawIsLand 的工作原理依赖于轻便地窃听底层消息，请运行目录内置的 python installer 或由系统自身完成引导，确保你的全局环境变量已经挂载了 `clawisland-hook.py`。
*(更详细的安装部署手段，后续待补充...)*

---

## 🛠️ 从源码构建

本项目基于 **macOS 14.0+** 及 Swift 5.9+ 架构开发。得益于 Xcode 16 文件系统级别的自动同步方案，您可以直接克隆即可进行全量构建：

```bash
# 1. 克隆项目仓库
git clone https://github.com/your-username/ClawIsLand.git
cd ClawIsLand

# 2. 拉取 Markdown 等内部图形依赖：（若 Xcode 识别不到包时使用）
xcodebuild -resolvePackageDependencies -project ClawIsLand.xcodeproj -scheme ClawIsLand

# 3. 部署打包！
./build_and_install.sh
```

---

## ⚙️ 个性化设置

点击屏幕顶栏的常驻图标（或在活动展开时右键），便能进到属于小动物们的调整实验室。在这里你可以：

1. **外观偏好 (Appearance)** — 体验上帝视角并雇佣你的专属常驻吉祥物，甚至能把他们的动作抽风率拉满（支持 3.0× 播放倍速！）。
2. **声音偏好 (Sound)** — 管理不必要的烦恼。你大可只在 Claude Code 卡住并向你索要 `bash` 权限写入时，才让系统发出“滴——”的长鸣报警。
