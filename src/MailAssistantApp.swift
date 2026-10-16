import AppKit
import SwiftUI

@MainActor
final class MailAssistantModel: ObservableObject {
    @Published var workspace = MailWorkspace()
    @Published var isWorking = false
    @Published var statusText = "准备就绪"
    @Published var filter: MailFilter = .all
    @Published var actionError: String?

    private var hasStarted = false
    var messages: [MailMessage] { workspace.messages }
    var selectedMessage: MailMessage? { workspace.selectedMessage }
    var conversation: [ConversationItem] { workspace.conversation }
    var replyBody: String {
        get { workspace.draft }
        set { workspace.draft = newValue }
    }
    var visibleMessages: [MailMessage] { messages.filter { filter.includes($0) } }

    func startOnce() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()
    }

    func refresh() {
        guard !isWorking else { return }
        isWorking = true
        statusText = "正在整理邮件卡片…"

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.execute(task: "triage")
            }.value

            switch result {
            case .success(let output):
                workspace.replaceMessages(output.messages)
                statusText = "\(messages.count) 封邮件 · \(messages.filter { $0.needsReply == true }.count) 封需回复"
            case .failure(let error):
                actionError = error.localizedDescription
                statusText = "需要处理"
            }
            isWorking = false
        }
    }

    func prepareReply(_ message: MailMessage) {
        guard !isWorking else { return }
        workspace.select(message)
        if !replyBody.isEmpty {
            statusText = "已恢复此邮件的草稿，可在下方继续修改"
            return
        }
        submit(instruction: "请为这封邮件拟写简短得体的回复。", task: "draft")
    }

    func select(_ message: MailMessage) {
        guard !isWorking else { return }
        workspace.select(message)
    }

    @discardableResult
    func submit(instruction: String, task: String = "assist") -> Bool {
        guard !isWorking else { return false }
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return false }
        if let command = MailFilter.command(instruction) {
            filter = command
            statusText = "\(command.rawValue) · \(visibleMessages.count) 封"
            return true
        }
        guard let message = selectedMessage else {
            actionError = "请先选择一封邮件，再提问或说明回复意图。"
            return false
        }
        if task == "revise" && replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            actionError = "这封邮件还没有草稿，请先拟写回复。"
            return false
        }
        let id = message.cardID
        let context = workspace.context(for: id)
        let currentDraft = replyBody
        workspace.append(.init(role: .user, text: instruction), to: id)
        isWorking = true
        statusText = task == "draft" || task == "revise" ? "正在处理回复草稿…" : "正在处理所选邮件…"
        Task {
            let result = await Task.detached {
                Self.execute(task: task, instruction: instruction, context: context,
                             selectedMessage: message, currentDraft: currentDraft)
            }.value
            switch result {
            case .success(let output):
                if output.kind == "draft" {
                    workspace.threads[id, default: MailThread()].draft = output.text
                    workspace.append(.init(role: .assistant, text: "草稿已更新，请在编辑区审阅。"), to: id)
                    statusText = "草稿已更新，尚未保存到 Mail"
                } else {
                    workspace.append(.init(role: .assistant, text: output.text), to: id)
                    statusText = output.kind == "clarify" ? "需要补充信息" : "已回答所选邮件的问题"
                }
            case .failure(let error):
                workspace.append(.init(role: .error, text: error.localizedDescription), to: id)
                statusText = "处理未完成"
            }
            isWorking = false
        }
        return true
    }

    func performMailAction(_ action: String, message: MailMessage, body: String = "") {
        guard !isWorking else { return }
        isWorking = true
        Task {
            let result = await Task.detached {
                Self.executeMailAction(action, message: message, body: body)
            }.value
            switch result {
            case .success(let text):
                statusText = text
                if action == "draft" {
                    workspace.append(.init(role: .assistant, text: text), to: message.cardID)
                }
            case .failure(let error):
                actionError = error.localizedDescription
                statusText = "操作未完成"
            }
            isWorking = false
        }
    }

    private nonisolated static func executeMailAction(_ action: String, message: MailMessage, body: String) -> Result<String, Error> {
        // Fixture mode must never open or create actual messages.
        guard ProcessInfo.processInfo.environment["MAIL_ASSISTANT_INPUT_FILE"] == nil else {
            return .failure(AssistantError("测试模式不操作真实邮箱。"))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let request = directory.appendingPathComponent("request.json")
            let data = try JSONSerialization.data(withJSONObject: ["action": action, "id": message.id,
                "localID": message.localID ?? "", "body": body])
            try data.write(to: request)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: request.path)
            guard let script = Bundle.main.url(forResource: "mail_action", withExtension: "js") else {
                throw AssistantError("缺少 Mail 操作组件，请重新安装。")
            }
            return runProcess("/usr/bin/osascript", arguments: ["-l", "JavaScript", script.path, request.path])
        } catch { return .failure(error) }
    }

    private nonisolated static func runProcess(_ executable: String, arguments: [String], environment: [String: String]? = nil) -> Result<String, Error> {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0, !text.isEmpty else {
                return .failure(AssistantError(text.isEmpty ? "操作没有完成，请检查 Mail 权限、登录状态和网络。" : text))
            }
            return .success(text)
        } catch { return .failure(error) }
    }

    private nonisolated static func execute(task: String, instruction: String = "", context: String = "", selectedMessage: MailMessage? = nil, currentDraft: String = "") -> Result<MailTaskResult, Error> {
        guard let scriptURL = Bundle.main.url(forResource: "run_local", withExtension: "sh") else {
            return .failure(AssistantError("应用资源不完整，请重新安装邮件管家。"))
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let snapshotURL = directory.appendingPathComponent("messages.json")
            var arguments = [scriptURL.path, "--task=\(task)", "--messages-file=\(snapshotURL.path)"]
            var environment = ProcessInfo.processInfo.environment
            if let selectedMessage {
                let inputURL = directory.appendingPathComponent("input.json")
                try JSONEncoder().encode(MailSnapshot(messages: [selectedMessage])).write(to: inputURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: inputURL.path)
                environment["MAIL_ASSISTANT_INPUT_FILE"] = inputURL.path
            }
            if task != "triage", selectedMessage == nil { throw AssistantError("请先选择邮件。") }
            if !currentDraft.isEmpty {
                let draftURL = directory.appendingPathComponent("draft.txt")
                try currentDraft.write(to: draftURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: draftURL.path)
                arguments.append("--draft-file=\(draftURL.path)")
            }
            if !instruction.isEmpty { arguments.append("--instruction=\(instruction)") }
            if !context.isEmpty { arguments.append("--context=\(context)") }
            switch runProcess("/bin/zsh", arguments: arguments, environment: environment) {
            case .failure(let error): return .failure(error)
            case .success(let text):
                let snapshot = try JSONDecoder().decode(MailSnapshot.self, from: Data(contentsOf: snapshotURL))
                if task == "triage" {
                    let structured = try JSONDecoder().decode(StructuredAnalysis.self, from: Data(text.utf8))
                    return .success(MailTaskResult(text: "", kind: "cards", messages: try structured.applying(to: snapshot.messages)))
                }
                if task == "assist" {
                    let result = try JSONDecoder().decode(FollowUpResult.self, from: Data(text.utf8))
                    guard ["answer", "draft", "clarify"].contains(result.kind),
                          !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw AssistantError("追问结果无效，请重试。")
                    }
                    return .success(MailTaskResult(text: result.text, kind: result.kind, messages: []))
                }
                return .success(MailTaskResult(text: text, kind: task == "question" ? "answer" : "draft", messages: []))
            }
        } catch {
            return .failure(AssistantError("无法启动邮件分析：\(error.localizedDescription)"))
        }
    }
}

struct ContentView: View {
    @StateObject private var model = MailAssistantModel()
    @State private var draft = ""
    @State private var taskMode = "assist"
    @State private var confirmSave = false
    @State private var pendingMessage: MailMessage?
    @State private var pendingBody = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.5)
            mainPanel
        }
        .frame(minWidth: 920, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { model.startOnce() }
        .confirmationDialog("确认在 Mail 中创建这封邮件的回复草稿？", isPresented: $confirmSave, titleVisibility: .visible) {
            Button("创建草稿（不发送）") {
                if let message = pendingMessage {
                    model.performMailAction("draft", message: message, body: pendingBody)
                }
                pendingMessage = nil
                pendingBody = ""
            }
            Button("取消", role: .cancel) { pendingMessage = nil; pendingBody = "" }
        } message: {
            Text("\(pendingMessage?.subject ?? "")\n回复给：\(pendingMessage?.replyTo ?? pendingMessage?.sender ?? "")\n请先核对草稿正文。发送仍需在 Mail 中手动完成。")
        }
        .alert("操作未完成", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) { Button("好") { model.actionError = nil } } message: { Text(model.actionError ?? "") }
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
                    model.refresh()
                } label: {
                    sidebarButtonLabel("重新整理未读", icon: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)

                ForEach(MailFilter.allCases, id: \.self) { filter in
                    Button {
                        model.filter = filter
                    } label: {
                        sidebarButtonLabel(filter.rawValue, icon: filter.icon)
                            .background(model.filter == filter ? Color.blue.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isWorking)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("操作由你确认", systemImage: "lock.shield.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                Text("分析不更改邮件。打开原邮件可能标为已读；回复草稿审阅后才保存，发送需在 Mail 中完成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(22)
        .frame(width: 210)
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
                    Text("邮件工作台")
                        .font(.title3.weight(.semibold))
                    Text("\(model.messages.count) 封 · \(model.messages.filter { $0.needsReply == true }.count) 封需回复 · 仅重新整理时刷新邮箱")
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
        HSplitView {
            ScrollView {
                LazyVStack(spacing: 18) {
                    Text("\(model.filter.rawValue) · \(model.visibleMessages.count) 封").font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(model.visibleMessages.enumerated()), id: \.element.cardID) { index, message in
                        mailCard(message, number: index + 1)
                    }
                    if model.messages.isEmpty {
                        if model.isWorking { welcomeLoading }
                        else { Text("暂无近期未读邮件").foregroundStyle(.secondary) }
                    } else if model.visibleMessages.isEmpty {
                        Text("此筛选下没有邮件").foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            }
            .frame(minWidth: 310, idealWidth: 390, maxWidth: 470)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.42))

            VStack(alignment: .leading, spacing: 12) {
                if let message = model.selectedMessage {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("正在处理").font(.caption).foregroundStyle(.blue)
                        Text(message.subject).font(.headline)
                        Text(message.sender).font(.caption).foregroundStyle(.secondary)
                        Text("追问只针对这封邮件，不重新读取邮箱。").font(.caption2).foregroundStyle(.secondary)
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if model.conversation.isEmpty {
                                    Text("在下方提问或说明回复意图，例如：告诉他我周五下午有空。")
                                        .foregroundStyle(.secondary).font(.callout)
                                }
                                ForEach(model.conversation) { item in
                                    messageBubble(item).id(item.id)
                                }
                            }
                        }
                        .onChange(of: model.conversation.count) { _ in
                            if let last = model.conversation.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .frame(minHeight: 90)
                    if !model.replyBody.isEmpty {
                        Divider()
                        HStack {
                            Text("回复草稿 · 可直接编辑").font(.headline)
                            Spacer()
                            Button("在 Mail 中创建草稿…") {
                                pendingMessage = message
                                pendingBody = model.replyBody
                                confirmSave = true
                            }
                            .disabled(model.isWorking || model.replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("回复给：\(message.replyTo?.isEmpty == false ? message.replyTo! : message.sender)")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: Binding(get: { model.replyBody }, set: { model.replyBody = $0 }))
                            .font(.body).padding(8).disabled(model.isWorking)
                            .frame(minHeight: 160, idealHeight: 220)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                        Text("可继续输入“再短一点”或“换成英文”；当前编辑内容会一起传给助手。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Spacer()
                    Image(systemName: "envelope.open").font(.largeTitle).foregroundStyle(.blue)
                    Text("选择一封邮件开始处理").font(.headline)
                    Text("每封邮件的对话与草稿独立保存于本次会话，切换卡片不会混用上下文。")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(18).frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func mailCard(_ message: MailMessage, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("\(number)").font(.caption.bold()).foregroundStyle(.blue)
                    .padding(7).background(.blue.opacity(0.09), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Button { model.select(message) } label: {
                        Text(message.subject).font(.headline).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain).disabled(model.isWorking)
                    Text(message.sender).font(.caption).foregroundStyle(.secondary)
                    Text("\(message.mailbox) · \(receivedDate(message.receivedAt))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(message.summary ?? String(message.snippet.prefix(220))).font(.callout)
                .foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            if let deadline = message.deadline {
                Label(deadline, systemImage: "calendar.badge.clock")
                    .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            if let suggestion = message.suggestion {
                Text("建议：\(suggestion)").font(.callout).textSelection(.enabled)
            }
            HStack {
                Button {
                    model.select(message)
                    model.performMailAction("open", message: message)
                } label: { Label("打开原邮件", systemImage: "arrow.up.forward.app") }
                Button { model.prepareReply(message) } label: {
                    Label("拟写回复", systemImage: "square.and.pencil")
                }
                Button("选择") { model.select(message) }
                Spacer()
            }
            .buttonStyle(.bordered).disabled(model.isWorking)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(
            model.selectedMessage?.cardID == message.cardID ? Color.blue : Color.clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { model.select(message) }
    }

    private func receivedDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date?.formatted(date: .abbreviated, time: .shortened) ?? value
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("处理方式", selection: $taskMode) {
                    Text("自动识别").tag("assist")
                    Text("问邮件").tag("question")
                    Text("写回复").tag("draft")
                    Text("改草稿").tag("revise")
                }
                .frame(width: 210).disabled(model.isWorking)
                Text(model.selectedMessage.map { "针对：\($0.subject)" } ?? "请先选择邮件，也可输入“只看今天”等筛选指令")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        HStack(alignment: .bottom, spacing: 12) {
            TextField("例如：帮我婉拒 ／ 再短一点 ／ 这封邮件需要做什么？", text: $draft, axis: .vertical)
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
        if model.submit(instruction: instruction, task: taskMode) { draft = "" }
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
