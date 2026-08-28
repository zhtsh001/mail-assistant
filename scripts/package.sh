#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/邮件管家.app"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mail-assistant-package.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

"$ROOT_DIR/scripts/build.sh" >/dev/null
mkdir -p "$TEMP_DIR/邮件管家-Mac安装包"
ditto "$APP_DIR" "$TEMP_DIR/邮件管家-Mac安装包/邮件管家.app"
cp "$ROOT_DIR/scripts/install.command" "$TEMP_DIR/邮件管家-Mac安装包/安装邮件管家.command"
cp "$ROOT_DIR/INSTALL.md" "$TEMP_DIR/邮件管家-Mac安装包/INSTALL.md"
chmod 700 "$TEMP_DIR/邮件管家-Mac安装包/安装邮件管家.command"
ditto -c -k --sequesterRsrc --keepParent "$TEMP_DIR/邮件管家-Mac安装包" "$DIST_DIR/邮件管家-Mac安装包.zip"
print "$DIST_DIR/邮件管家-Mac安装包.zip"
