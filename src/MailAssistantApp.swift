import AppKit
import SwiftUI

struct ConversationItem: Identifiable, Equatable {
    enum Role {
        case assistant
        case user
        case error
    }

    let id = UUID()
    let role: Role
    let text: String
}

@MainActor
final class MailAssistantModel: ObservableObject {
    @Published var conversation: [ConversationItem] = []
    @Published var isWorking = false
    @Published var statusText = "准备就绪"

    private var hasStarted = false

    func startOnce() {
        guard !hasStarted else { return }
        hasStarted = true
        run(instruction: nil)
    }

    func run(instruction: String?) {
        guard !isWorking else { return }
        let cleaned = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let priorContext = conversation.suffix(6).map { item in
            let role: String
            switch item.role {
            case .assistant: role = "邮件管家"
            case .user: role = "用户"
            case .error: role = "错误"
            }
            return "\(role)：\(item.text)"
        }.joined(separator: "\n\n").suffix(12_000)
        if let cleaned, !cleaned.isEmpty {
            conversation.append(.init(role: .user, text: cleaned))
        }

        isWorking = true
        statusText = cleaned?.isEmpty == false ? "正在处理指令…" : "正在整理未读邮件…"

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.execute(instruction: cleaned, context: String(priorContext))
            }.value

            switch result {
            case .success(let output):
                conversation.append(.init(role: .assistant, text: output))
                statusText = "分析完成"
            case .failure(let error):
                conversation.append(.init(role: .error, text: error.localizedDescription))
                statusText = "需要处理"
            }
            isWorking = false
        }
    }

    private nonisolated static func execute(instruction: String?, context: String) -> Result<String, Error> {
        guard let scriptURL = Bundle.main.url(forResource: "run_local", withExtension: "sh") else {
            return .failure(AssistantError("应用资源不完整，请重新安装邮件管家。"))
        }

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        var arguments = [scriptURL.path]
        if let instruction { arguments.append("--instruction=\(instruction)") }
        if !context.isEmpty { arguments.append("--context=\(context)") }
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0, !output.isEmpty {
                return .success(output)
            }
            return .failure(AssistantError(output.isEmpty ? "邮件分析没有完成，请确认 ChatGPT/Codex 已登录并且网络可用。" : output))
        } catch {
            return .failure(AssistantError("无法启动邮件分析：\(error.localizedDescription)"))
        }
    }
}

struct AssistantError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct ContentView: View {
    @StateObject private var model = MailAssistantModel()
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private let quickActions: [(String, String, String)] = [
        ("只看今天", "calendar.badge.clock", "只列出今天必须处理或即将截止的邮件"),
        ("需要回复", "arrowshape.turn.up.left.fill", "列出所有需要我回复的邮件，并分别生成简短草稿"),
        ("退订检查", "envelope.badge.minus", "检查哪些邮件适合安全退订；可疑邮件不要点击退订链接"),
        ("风险检查", "exclamationmark.shield.fill", "检查钓鱼、诈骗、异常付款和可疑链接风险")
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.5)
            mainPanel
        }
        .frame(minWidth: 920, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { model.startOnce() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("邮件管家")
                        .font(.title2.weight(.bold))
                    Text("本地触发 · 所有账户")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            statusCard

            VStack(alignment: .leading, spacing: 8) {
                Text("快捷处理")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Button {
                    model.run(instruction: nil)
                } label: {
                    sidebarButtonLabel("重新整理未读", icon: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)

                ForEach(quickActions, id: \.0) { title, icon, prompt in
                    Button {
                        model.run(instruction: prompt)
                    } label: {
                        sidebarButtonLabel(title, icon: icon)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isWorking)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("只读模式", systemImage: "lock.shield.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                Text("不会自动发送、删除、移动或退订。涉及外部操作时，必须由你确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(22)
        .frame(width: 250)
        .background(.ultraThinMaterial)
    }

    private var statusCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(model.isWorking ? Color.orange.opacity(0.16) : Color.green.opacity(0.16))
                    .frame(width: 34, height: 34)
                if model.isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusText)
                    .font(.callout.weight(.semibold))
                Text("来自本机 Mail")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sidebarButtonLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.blue)
            Text(title)
                .font(.callout.weight(.medium))
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("今日邮件简报")
                        .font(.title3.weight(.semibold))
                    Text("最近 72 小时 · 最多 20 封未读邮件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("无需邮箱插件授权", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.045), in: Capsule())
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 17)

            Divider().opacity(0.45)

            conversationView
            composer
        }
    }

    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if model.conversation.isEmpty && model.isWorking {
                        welcomeLoading
                    }
                    ForEach(model.conversation) { item in
                        messageBubble(item)
                            .id(item.id)
                    }
                }
                .padding(26)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.42))
            .onChange(of: model.conversation.count) { _ in
                if let last = model.conversation.last {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var welcomeLoading: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(.blue.opacity(0.09)).frame(width: 74, height: 74)
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
            }
            Text("正在整理你的未读邮件")
                .font(.title3.weight(.semibold))
            Text("我会找出截止日期、待回复事项、退订候选和潜在风险。")
                .font(.callout)
                .foregroundStyle(.secondary)
            ProgressView().controlSize(.small)
        }
        .padding(.top, 70)
    }

    @ViewBuilder
    private func messageBubble(_ item: ConversationItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if item.role == .user { Spacer(minLength: 90) }

            if item.role != .user {
                Image(systemName: item.role == .error ? "exclamationmark.triangle.fill" : "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.role == .error ? .red : .blue)
                    .frame(width: 30, height: 30)
                    .background((item.role == .error ? Color.red : Color.blue).opacity(0.1), in: Circle())
            }

            Text(markdown(item.text))
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: item.role == .user ? 470 : 680, alignment: .leading)
                .padding(.horizontal, 17)
                .padding(.vertical, 14)
                .background(bubbleColor(item.role), in: RoundedRectangle(cornerRadius: 17, style: .continuous))

            if item.role != .user { Spacer(minLength: 30) }
        }
        .frame(maxWidth: .infinity)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("继续输入，例如：给第 1 封写一个更正式的回复", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onSubmit(sendDraft)

            Button(action: sendDraft) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(canSend ? Color.blue : Color.gray.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !model.isWorking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        let instruction = draft
        draft = ""
        model.run(instruction: instruction)
        inputFocused = true
    }

    private func markdown(_ source: String) -> AttributedString {
        let readableHeadings = source.replacingOccurrences(
            of: "(?m)^#{1,6}\\s+(.+)$",
            with: "**$1**",
            options: .regularExpression
        )
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: readableHeadings, options: options)) ?? AttributedString(source)
    }

    private func bubbleColor(_ role: ConversationItem.Role) -> Color {
        switch role {
        case .assistant: return Color(nsColor: .controlBackgroundColor)
        case .user: return .blue.opacity(0.13)
        case .error: return .red.opacity(0.10)
        }
    }
}

@main
struct MailAssistantApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1020, height: 720)
    }
}
