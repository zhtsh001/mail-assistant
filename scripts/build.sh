#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE_DIR="$ROOT_DIR/src"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/邮件管家.app"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mail-assistant-build.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$DIST_DIR" "$TEMP_DIR/邮件管家.app/Contents/MacOS" "$TEMP_DIR/邮件管家.app/Contents/Resources"

xcrun swiftc \
  -parse-as-library \
  -O \
  -module-cache-path "$TEMP_DIR/ModuleCache" \
  -target arm64-apple-macos13.0 \
  -framework SwiftUI \
  -framework AppKit \
  "$SOURCE_DIR/MailAssistantApp.swift" \
  -o "$TEMP_DIR/邮件管家.app/Contents/MacOS/MailAssistant"

cp "$SOURCE_DIR/Info.plist" "$TEMP_DIR/邮件管家.app/Contents/Info.plist"
cp "$SOURCE_DIR/run_local.sh" "$TEMP_DIR/邮件管家.app/Contents/Resources/run_local.sh"
cp "$SOURCE_DIR/find_codex.sh" "$TEMP_DIR/邮件管家.app/Contents/Resources/find_codex.sh"
cp "$SOURCE_DIR/mail_action.js" "$TEMP_DIR/邮件管家.app/Contents/Resources/mail_action.js"
cp "$SOURCE_DIR/analysis_schema.json" "$TEMP_DIR/邮件管家.app/Contents/Resources/analysis_schema.json"
cp "$SOURCE_DIR/read_unread_mail.js" "$TEMP_DIR/邮件管家.app/Contents/Resources/read_unread_mail.js"
chmod 755 "$TEMP_DIR/邮件管家.app/Contents/MacOS/MailAssistant"
chmod 700 "$TEMP_DIR/邮件管家.app/Contents/Resources/run_local.sh"
chmod 600 "$TEMP_DIR/邮件管家.app/Contents/Resources/read_unread_mail.js"
codesign --force --deep --sign - "$TEMP_DIR/邮件管家.app" >/dev/null

ditto "$TEMP_DIR/邮件管家.app" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
print "$APP_DIR"
