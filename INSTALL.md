# Installation

[简体中文](#中文安装说明)

## Prerequisites

1. Add the email accounts you want to process to Apple Mail.
2. Install the ChatGPT or Codex macOS app in `/Applications` or `~/Applications` and sign in.
3. Make sure the Mac has internet access when running an analysis.

## Install from the packaged archive

1. Unzip `邮件管家-Mac安装包.zip`.
2. Double-click `安装邮件管家.command`.
3. If macOS blocks the installer, Control-click it, select **Open**, and confirm.
4. The installer places Mail Assistant in your personal Applications folder at `~/Applications/邮件管家.app`.
5. Open Mail Assistant. On the first run, allow access to Apple Mail when macOS asks.

## Using the app

- Opening the app immediately starts an on-demand review of recent unread mail.
- Use the sidebar for **Due today**, **Needs reply**, **Unsubscribe review**, or **Risk review**.
- Select a mail card, then type an instruction such as “politely decline” or “make it shorter.” The target is shown above the composer; questions and draft edits do not refresh the inbox.
- Choose Automatic, Ask, Draft, or Revise in the composer. Review and edit the draft in the right-hand panel, then choose Create draft in Mail and confirm.
- Filters operate on existing cards without AI calls. Press Refresh to fetch the inbox again. Conversations and drafts are per message and remain in memory only until the app exits.
- Results, reply drafts, and links stay inside Mail Assistant.
- Use a source card to open the original in Mail (which may mark it read).
- Select **Draft reply**, edit the text, then confirm **Create draft in Mail**. Mail saves and opens a reply using the original account and sender/Reply-To. Review and send from Mail yourself.
- If the source message was moved or deleted, refresh the analysis.

## Safety behavior

- No scheduled task or background polling is installed.
- Mail Assistant does not automatically send, delete, move, block, or unsubscribe.
- Any external action remains under the user's control.
- Drafts are saved only after confirmation and may sync to the provider. They are never sent automatically.

---

## 中文安装说明

### 安装前准备

1. 将需要处理的所有邮箱加入系统 Mail。
2. 将 Mac 版 ChatGPT 或 Codex 安装到系统或个人应用程序目录，并完成登录。
3. 运行分析时保持网络连接。

### 从安装包安装

1. 解压 `邮件管家-Mac安装包.zip`。
2. 双击 `安装邮件管家.command`。
3. 如果 macOS 阻止打开，请按住 Control 点按安装器，选择“打开”并确认。
4. 安装器会将应用放入个人应用程序目录：`~/Applications/邮件管家.app`。
5. 首次打开时，根据 macOS 提示允许邮件管家访问 Mail。

### 使用方法

- 打开应用即开始按需整理最近的未读邮件。
- 左侧可以快速选择“只看今天”“需要回复”“退订检查”和“风险检查”。
- 先选择邮件卡片，再在底部输入“帮我婉拒”或“再短一点”。输入框上方会显示处理对象；追问不重新读取未读列表。
- 可选择“自动识别、问邮件、写回复、改草稿”。在右侧编辑草稿后，点击“在 Mail 中创建草稿…”并确认。
- 筛选只作用于现有卡片，不调用 AI；点击“重新整理”才刷新邮箱。每封邮件的对话、草稿独立保留在内存，退出应用后不保存。
- 结果、链接和回复草稿都显示在邮件管家内部。
- 邮件卡片可打开原邮件，此操作可能标为已读。
- 点击“拟写回复”，编辑后选择“确认，在 Mail 中创建草稿”。Mail 使用原账号和真实回复地址保存并打开草稿；发送仍需手动完成。
- 原邮件若已移动或删除，请先重新整理。

### 安全说明

- 不安装定时任务或后台轮询。
- 不会自动发送、删除、移动、拉黑或退订邮件。
- 所有外部操作仍由用户最终决定。
- 创建草稿需要明确确认，保存后可能通过原邮箱同步；不会自动发送。
