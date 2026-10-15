#!/bin/zsh
set -euo pipefail

SOURCE_DIR="${0:A:h}"
SOURCE_APP="$SOURCE_DIR/邮件管家.app"
TARGET_DIR="$HOME/Applications"
TARGET_APP="$TARGET_DIR/邮件管家.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  print "安装包不完整：没有找到邮件管家.app。"
  read -k 1 "?按任意键关闭…"
  exit 1
fi

source "$SOURCE_APP/Contents/Resources/find_codex.sh"
if ! find_codex >/dev/null; then
  print "没有找到 Mac 版 ChatGPT/Codex。请先安装并登录，再重新运行此安装器。"
  read -k 1 "?按任意键关闭…"
  exit 1
fi

mkdir -p "$TARGET_DIR"
ditto "$SOURCE_APP" "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"
open -R "$TARGET_APP"

print ""
print "安装完成。首次打开时，请允许邮件管家访问 Mail。分析保持只读，回复草稿需审阅确认后创建。"
read -k 1 "?按任意键关闭…"
