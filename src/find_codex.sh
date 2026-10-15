#!/bin/zsh
# Shared by the app and installer; app updates can relocate the bundled CLI.
find_codex() {
  local app_root candidate
  if [[ -n "${MAIL_ASSISTANT_CODEX_BIN:-}" ]]; then
    [[ -x "$MAIL_ASSISTANT_CODEX_BIN" ]] || return 1
    print -r -- "$MAIL_ASSISTANT_CODEX_BIN"
    return 0
  fi
  for app_root in /Applications/ChatGPT.app /Applications/Codex.app \
    "$HOME/Applications/ChatGPT.app" "$HOME/Applications/Codex.app"; do
    for candidate in \
      "$app_root/Contents/Resources/codex-cli/bin/codex" \
      "$app_root/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex" \
      "$app_root/Contents/Resources/codex"; do
      if [[ -x "$candidate" ]]; then
        print -r -- "$candidate"
        return 0
      fi
    done
  done
  return 1
}
