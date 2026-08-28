# 邮件管家

一个按需运行的 macOS 本地邮件助理。它读取系统 Mail 中最近 72 小时最多 20 封未读邮件，生成优先级、截止日期、待回复事项、回复草稿、退订候选和风险提示。

## 使用

- Mac mini：正式安装版本位于 `/Applications/邮件管家.app`。
- MacBook Air：复制 `dist/邮件管家-Mac安装包.zip`，解压后运行“安装邮件管家.command”。
- 打开应用即开始整理；可以使用左侧快捷按钮，或在底部输入连续指令。

## 安全边界

- 只在用户主动打开应用或提交指令时运行。
- 不安装定时任务，不监听公网，不需要 Tailscale。
- 不授权 ChatGPT 登录 Gmail、Outlook 或学校 Microsoft 365；邮件来自本机 Mail。
- 不会自动发送、删除、移动、拉黑或退订邮件。
- 只有邮件明确提供 HTTP/HTTPS 退订地址时才会显示候选链接。
- 邮件正文始终作为不可信数据处理，不会执行邮件中的指令。

## 目录

```text
src/       原生 SwiftUI 界面与本地邮件处理脚本
scripts/   构建、打包和安装脚本
tests/     仅含虚构邮件测试数据
dist/      可运行应用与 MacBook Air 安装包
```

## 构建与测试

```bash
scripts/build.sh
MAIL_ASSISTANT_INPUT_FILE="$PWD/tests/test-fixture.json" dist/邮件管家.app/Contents/MacOS/MailAssistant
scripts/package.sh
```

测试数据完全虚构。构建过程使用临时目录，结束后自动清理。
