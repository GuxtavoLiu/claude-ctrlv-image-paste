# ctrlv-image-paste

A Claude Code plugin that makes **Ctrl+V paste images in Claude Code on Windows Terminal**.

## The problem

On Windows, Claude Code pastes images with **Alt+V**. Windows Terminal binds Ctrl+V to its own paste action, and when the clipboard holds only an image, it sends nothing to the app, so Claude Code never sees the key.

## How it works

Two settings changes:

1. **Windows Terminal**: Ctrl+V is unbound (`{ "id": null, "keys": "ctrl+v" }`), so the key reaches the app running in the tab.
2. **Claude Code**: Ctrl+V is bound to `chat:imagePaste` in `~/.claude/keybindings.json`.

When the clipboard has no image, Claude Code's image paste falls back to pasting the clipboard text, so a single Ctrl+V handles both.

## Install

In Claude Code, run:

```
/plugin marketplace add GuxtavoLiu/claude-ctrlv-image-paste
/plugin install ctrlv-image-paste@ctrlv-image-paste
```

Then apply the settings:

```
/ctrlv-image-paste:setup
```

Claude shows the current state, explains what will change and asks before touching anything. Open a new Claude Code session afterwards and try Ctrl+V with a screenshot (Win+Shift+S) and with some text.

Other commands:

```
/ctrlv-image-paste:setup status   # show the current state, change nothing
/ctrlv-image-paste:setup revert   # undo everything
```

### Without the plugin

The script works on its own. From PowerShell:

```powershell
irm https://raw.githubusercontent.com/GuxtavoLiu/claude-ctrlv-image-paste/main/plugins/ctrlv-image-paste/skills/setup/scripts/ctrlv-image-paste.ps1 -OutFile ctrlv-image-paste.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\ctrlv-image-paste.ps1           # install
powershell -NoProfile -ExecutionPolicy Bypass -File .\ctrlv-image-paste.ps1 -Status   # check
powershell -NoProfile -ExecutionPolicy Bypass -File .\ctrlv-image-paste.ps1 -Revert   # undo
```

Or edit the two files by hand: add `{ "id": null, "keys": "ctrl+v" }` to `keybindings` (or `actions`) in Windows Terminal's `settings.json` (replacing any existing Ctrl+V entry), and create `%USERPROFILE%\.claude\keybindings.json`:

```json
{
  "bindings": [
    { "context": "Chat", "bindings": { "ctrl+v": "chat:imagePaste" } }
  ]
}
```

## Things to know

- **Only for Windows + Windows Terminal.** On macOS, Linux and WSL, Ctrl+V already pastes images in Claude Code.
- **It affects every Windows Terminal tab.** Inside Claude Code, Ctrl+V pastes images and text. In PowerShell, Ctrl+V keeps working (PSReadLine handles it). In cmd, Git Bash, WSL and ssh sessions, use **Ctrl+Shift+V** or right-click to paste.
- **Pasting text takes about half a second.** Claude Code first checks the clipboard for an image, then reads the text, and each step runs a short PowerShell command. Ctrl+Shift+V pastes text instantly.
- **The text fallback is not documented.** It was confirmed in Claude Code 2.1.296. If a future version drops it, Ctrl+V will paste only images in Claude Code, and Ctrl+Shift+V will still paste text.
- **Backups.** Every file the script changes is copied to `<file>.bak-ctrlv-<timestamp>` first.
- **Existing Ctrl+V binding in Claude Code.** If `keybindings.json` already maps Ctrl+V in the Chat context to something else, the script stops and changes nothing.

## Files

```
.claude-plugin/marketplace.json                           marketplace entry
plugins/ctrlv-image-paste/.claude-plugin/plugin.json      plugin manifest
plugins/ctrlv-image-paste/skills/setup/SKILL.md           the /ctrlv-image-paste:setup command
plugins/ctrlv-image-paste/skills/setup/scripts/ctrlv-image-paste.ps1   the script that edits the settings
```

## License

MIT
