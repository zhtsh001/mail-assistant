import Foundation

@main
struct WorkflowTests {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let original = try JSONDecoder().decode(MailSnapshot.self, from: Data(contentsOf: url)).messages
        var workspace = MailWorkspace()
        workspace.replaceMessages(original)
        assert(workspace.selectedMessage == nil, "Never guess a target")
        workspace.select(original[0])
        workspace.draft = "User edited: Friday 3 PM"
        workspace.append(.init(role: .user, text: "Tell them Friday 3 PM"), to: original[0].cardID)
        workspace.select(original[1])
        assert(workspace.draft.isEmpty && workspace.conversation.isEmpty, "No cross-mail context")
        workspace.draft = "Second mail draft"
        workspace.select(original[0])
        assert(workspace.draft == "User edited: Friday 3 PM", "Restore edited draft")
        assert(workspace.context(for: original[0].cardID).contains("Friday 3 PM"))
        assert(!workspace.context(for: original[1].cardID).contains("Friday 3 PM"))
        // Opening a message does not refresh the snapshot or change its identity.
        assert(workspace.messages[0].cardID == original[0].cardID)
        workspace.replaceMessages([original[1]])
        assert(workspace.selectedMessage == nil, "Explicit refresh clears stale selection")
        assert(workspace.threads[original[0].cardID]?.draft == "User edited: Friday 3 PM")
        workspace.replaceMessages(original)
        workspace.select(original[0])
        assert(workspace.draft == "User edited: Friday 3 PM")
        var message = original[0]
        message.dueToday = true
        message.needsReply = false
        assert(MailFilter.today.includes(message))
        assert(!MailFilter.replies.includes(message))
        assert(MailFilter.command("只看今天") == .today)
        assert(MailFilter.command("帮我婉拒") == nil)
        let empty = try JSONDecoder().decode(StructuredAnalysis.self, from: Data("{\"cards\":[]}".utf8))
        let emptyMessages = try empty.applying(to: [])
        assert(emptyMessages.isEmpty)
        do {
            _ = try empty.applying(to: original)
            fatalError("Missing analysis cards must not replace sources")
        } catch is AssistantError { }
        print("Workflow tests passed: stable selection, isolated threads, edited drafts, refresh, local filters, result validation.")
    }
}
