---
name: setup
description: Configure Windows Terminal and Claude Code so Ctrl+V pastes images (and text) in Claude Code on Windows. Run only when the user explicitly asks for it.
argument-hint: "[status | revert]"
disable-model-invocation: true
allowed-tools: Bash(powershell -NoProfile -ExecutionPolicy Bypass -File:*)
---

# Ctrl+V image paste for Windows Terminal

Requested mode: `$ARGUMENTS` (empty means install).

The script is `${CLAUDE_SKILL_DIR}/scripts/ctrlv-image-paste.ps1`. Run it with:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}/scripts/ctrlv-image-paste.ps1" <flag>
```

## Steps

1. Run the script with `-Status` and show the user the result.
2. If the mode is `status`, stop here.
3. If the mode is `revert`:
   - Tell the user this restores Windows Terminal's own Ctrl+V paste and removes the Claude Code binding. Images can still be pasted with Alt+V.
   - Ask for confirmation. Once confirmed, run the script with `-Revert`.
4. Otherwise (install):
   - If the status already shows both "Ctrl+V passed through to the app" and "Ctrl+V -> chat:imagePaste", tell the user it is already set up and stop.
   - Before changing anything, explain to the user, in their language:
     - Windows Terminal will stop handling Ctrl+V itself, so the key reaches Claude Code. In Claude Code, Ctrl+V pastes an image, or the clipboard text when there is no image.
     - This affects every tab in Windows Terminal. PowerShell keeps pasting with Ctrl+V (PSReadLine handles it). In cmd, Git Bash, WSL and ssh sessions, paste with Ctrl+Shift+V or right-click instead.
     - Both files are backed up first, and `/ctrlv-image-paste:setup revert` undoes it.
   - Ask for confirmation. Once confirmed, run the script with no flag.
5. Report what the script printed. Tell the user to open a new Claude Code session (or a new Windows Terminal tab) and try Ctrl+V with a screenshot (Win+Shift+S) and with text.

If the script fails, show its error message as-is and do not edit the files by hand.
