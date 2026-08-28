# Mail Assistant for macOS

[简体中文](#简体中文)

Mail Assistant is an on-demand, native macOS app for triaging messages already available in Apple Mail. It reviews up to 20 unread messages received during the previous 72 hours and produces priorities, deadline warnings, reply drafts, unsubscribe candidates, and security notes.

The app was designed for mixed personal, Gmail, Outlook, and managed Microsoft 365 accounts. It reads through the local Mail app, so it does not require ChatGPT to sign in to each email provider.

## Features

- Native SwiftUI interface with an inbox summary, quick actions, and a conversational input field.
- One-click views for messages due today, messages needing replies, unsubscribe candidates, and suspicious mail.
- Multi-turn follow-ups such as “draft a formal reply” followed by “make it shorter.”
- Markdown rendering, selectable text, and clickable links.
- Read-only email access: analysis never marks messages as read or modifies the mailbox.
- Prompt-injection safeguards that always treat email contents as untrusted data.

## Requirements

- macOS 13 or later on Apple silicon.
- Email accounts configured in Apple Mail.
- The ChatGPT/Codex macOS app installed in `/Applications/ChatGPT.app` and signed in.
- Internet access when an AI analysis is requested.

## How it works

1. Opening Mail Assistant is the manual trigger; there is no scheduled polling.
2. A JXA script reads recent unread messages from the local Mail app.
3. A temporary, permission-restricted workspace is created for the request.
4. The local Codex CLI analyzes the messages in a read-only sandbox.
5. Results are displayed in the native app and temporary request files are removed.

Follow-up instructions re-read the current unread set and include a limited amount of recent conversation context.

## Safety and privacy

- No cron job, LaunchAgent, public listener, or Tailscale connection is required.
- The project does not store email bodies, analysis history, OAuth tokens, or mailbox credentials.
- Sending, deleting, moving, blocking, and unsubscribing are never performed automatically.
- An unsubscribe link is surfaced only when the original message explicitly contains an HTTP or HTTPS candidate.
- Suspicious messages are treated as junk candidates rather than safe unsubscribe targets.
- Email text is placed between explicit untrusted-data boundaries and cannot redefine the assistant's task.

## Build

```bash
scripts/build.sh
```

The signed app is created at `dist/邮件管家.app`.

Run a model-backed test with fictional messages:

```bash
MAIL_ASSISTANT_INPUT_FILE="$PWD/tests/test-fixture.json" \
  dist/邮件管家.app/Contents/MacOS/MailAssistant
```

Create the Mac installation archive:

```bash
scripts/package.sh
```

See [INSTALL.md](INSTALL.md) for installation and first-run instructions.

## Project layout

```text
src/       SwiftUI app and local mail-processing scripts
scripts/   Build, packaging, and installation scripts
tests/     Fictional test messages only
dist/      Local build output; intentionally excluded from Git
```

## Current limitations

- The app analyzes unread messages from the last 72 hours, up to 20 per request.
- It suggests mailbox actions but intentionally does not execute them.
- The packaged binary is currently built for Apple silicon.
- A first run can trigger a macOS permission prompt for Apple Mail access.

---

## 简体中文

邮件管家是一款按需运行的原生 macOS 邮件助理。它读取 Apple Mail 中最近 72 小时最多 20 封未读邮件，整理优先级、截止日期、待回复事项、回复草稿、退订候选和安全风险。

### 主要特点

- 原生 SwiftUI 界面，支持快捷筛选和连续对话。
- 直接读取本机 Mail 中已经添加的所有账户，不需要 ChatGPT 分别登录 Gmail、Outlook 或学校 Microsoft 365。
- 只在用户主动打开应用或提交指令时运行，不安装定时任务或后台监听。
- 邮件正文始终作为不可信数据处理，避免邮件中的提示注入影响任务。
- 不自动发送、删除、移动、拉黑或退订邮件。

### 环境要求

- Apple 芯片 Mac，macOS 13 或更高版本。
- 邮箱已经配置在系统 Mail 中。
- `/Applications/ChatGPT.app` 已安装并登录。

### 构建

运行 `scripts/build.sh` 生成应用，运行 `scripts/package.sh` 生成安装包。详细安装步骤请参阅 [INSTALL.md](INSTALL.md) 的中文部分。
