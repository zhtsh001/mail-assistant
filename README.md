# Mail Assistant for macOS

[简体中文](#简体中文)

Mail Assistant is an on-demand, native macOS app for triaging messages already available in Apple Mail. It reviews up to 20 unread messages received during the previous 72 hours and produces priorities, deadline warnings, reply drafts, unsubscribe candidates, and security notes.

The app was designed for mixed personal, Gmail, Outlook, and managed Microsoft 365 accounts. It reads through the local Mail app, so it does not require ChatGPT to sign in to each email provider.

## Features

- Native SwiftUI interface with an inbox summary, quick actions, and a conversational input field.
- One-click views for messages due today, messages needing replies, unsubscribe candidates, and suspicious mail.
- Multi-turn follow-ups such as “draft a formal reply” followed by “make it shorter.”
- Markdown rendering, selectable text, and clickable links.
- Source-message cards show sender, received date and excerpt, and open originals in Mail.
- Per-message reply drafting: edit the text, then confirm creation of a real Mail reply draft. Send it yourself from Mail.
- Read-only analysis: analysis never modifies the mailbox. Opening an original in Mail may mark it read.
- Prompt-injection safeguards that always treat email contents as untrusted data.

## Requirements

- macOS 13 or later on Apple silicon.
- Email accounts configured in Apple Mail.
- The ChatGPT or Codex macOS app installed in `/Applications` or `~/Applications` and signed in.
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
- The project does not persist email bodies or analysis history. Temporary request files are removed after use; credentials are managed by Mail and Codex.
- AI analysis and draft generation send email text to the signed-in Codex service; they are not on-device inference.
- Confirmed drafts are saved by Mail and may sync through the original email provider. Mail supplies the reply account, Reply-To and thread association, not the model. Replies target the sender/Reply-To, not all recipients.
- Sending, deleting, moving, blocking, and unsubscribing are never performed automatically.
- An unsubscribe link is surfaced only when the original message explicitly contains an HTTP or HTTPS candidate.
- Suspicious messages are treated as junk candidates rather than safe unsubscribe targets.
- Email text is placed between explicit untrusted-data boundaries and cannot redefine the assistant's task.

## Build

```bash
scripts/build.sh
```

The signed app is created at `dist/邮件管家.app`.

If a preview SDK is selected by default and lacks SwiftUI compiler plugins, select an installed stable SDK, for example `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk scripts/build.sh`.

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

Test action validation without accessing a real mailbox: `node tests/mail_action.test.cjs`.

### Runtime troubleshooting

The app detects both current and legacy bundled Codex CLI locations. Check discovery without reading email:

```bash
zsh src/run_local.sh --check-runtime
```

For a custom CLI installation, set `MAIL_ASSISTANT_CODEX_BIN` to its executable path. A successful runtime check verifies discovery and startup, not login or network access.

## Project layout

```text
src/       SwiftUI app and local mail-processing scripts
scripts/   Build, packaging, and installation scripts
tests/     Action validation tests and fictional test messages
dist/      Local build output; intentionally excluded from Git
```

## Current limitations

- The app analyzes unread messages from the last 72 hours, up to 20 per request.
- It opens originals and saves reviewed reply drafts. Sending, archiving, deleting, and unsubscribing remain manual.
- Original-message actions require a unique identifier match in the inbox; refresh if the source was moved or deleted.
- Fictional-fixture mode disables all actions on real mailboxes.
- The packaged binary is currently built for Apple silicon.
- A first run can trigger a macOS permission prompt for Apple Mail access.

---

## 简体中文

邮件管家是一款按需运行的原生 macOS 邮件助理。它读取 Apple Mail 中最近 72 小时最多 20 封未读邮件，整理优先级、截止日期、待回复事项、回复草稿、退订候选和安全风险。

### 主要特点

- 原生 SwiftUI 界面，支持快捷筛选和连续对话。
- 邮件卡片显示来源、收信时间和摘录，可打开原邮件。点击“拟写回复”，编辑并确认后在 Mail 中创建真实草稿，发送仍需手动完成。
- 直接读取本机 Mail 中已经添加的所有账户，不需要 ChatGPT 分别登录 Gmail、Outlook 或学校 Microsoft 365。
- 只在用户主动打开应用或提交指令时运行，不安装定时任务或后台监听。
- 邮件正文始终作为不可信数据处理，避免邮件中的提示注入影响任务。
- 不自动发送、删除、移动、拉黑或退订邮件。
- 分析不更改邮件；主动打开原邮件可能标为已读，确认创建的草稿可能通过原邮箱同步。
- 邮件在本机读取，但 AI 分析和拟稿使用联网的 Codex 服务，并非完全离线。

### 环境要求

- Apple 芯片 Mac，macOS 13 或更高版本。
- 邮箱已经配置在系统 Mail 中。
- ChatGPT 或 Codex 已安装到系统或个人应用程序目录，并完成登录。

新版支持自动查找新旧版本的分析程序路径。可运行 `zsh src/run_local.sh --check-runtime` 检查程序能否启动，此检查不读取邮件。

### 构建

运行 `scripts/build.sh` 生成应用，运行 `scripts/package.sh` 生成安装包。详细安装步骤请参阅 [INSTALL.md](INSTALL.md) 的中文部分。
