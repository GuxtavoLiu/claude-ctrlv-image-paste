<#
.SYNOPSIS
    Makes Ctrl+V paste images (and text) in Claude Code on Windows Terminal.

.DESCRIPTION
    Windows Terminal binds Ctrl+V to its own paste action. When the clipboard
    holds only an image, Windows Terminal sends nothing, so Claude Code never
    sees the key. This script:

      1. Unbinds Ctrl+V in Windows Terminal, so the key reaches Claude Code.
      2. Binds Ctrl+V to chat:imagePaste in ~/.claude/keybindings.json.

    Every file is backed up before it is changed. Run with -Revert to undo.

.PARAMETER Status
    Only report the current state. Changes nothing.

.PARAMETER Revert
    Restore Windows Terminal's Ctrl+V paste and remove the Claude Code binding.

.PARAMETER WtSettingsPath
    Use this Windows Terminal settings.json instead of auto-detecting.

.PARAMETER ClaudeConfigDir
    Use this Claude Code config folder instead of $env:CLAUDE_CONFIG_DIR or ~/.claude.
#>
[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$Revert,
    [string[]]$WtSettingsPath,
    [string]$ClaudeConfigDir
)

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    Write-Output 'This setup is only for Windows. On macOS, Linux and WSL, Ctrl+V already pastes images in Claude Code.'
    exit 0
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# Matches a flat binding object whose "keys" is ctrl+v (in any key order).
$CtrlVObject = '\{[^{}]*"keys"\s*:\s*"ctrl\+v"[^{}]*\}'
$UnbindObject = '{ "id": null, "keys": "ctrl+v" }'
$PasteObject = '{ "id": "Terminal.PasteFromClipboard", "keys": "ctrl+v" }'

function Backup-File([string]$Path) {
    $backup = "$Path.bak-ctrlv-$Stamp"
    Copy-Item -LiteralPath $Path -Destination $backup
    return $backup
}

function Test-JsonText([string]$Text) {
    try { $null = $Text | ConvertFrom-Json; return $true } catch { return $false }
}

# ---------------------------------------------------------------- Windows Terminal

function Get-WtSettingsFiles {
    if ($WtSettingsPath) { return $WtSettingsPath | Where-Object { Test-Path -LiteralPath $_ } }
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    return $candidates | Where-Object { Test-Path -LiteralPath $_ }
}

function Get-WtState([string]$Text) {
    $m = [regex]::Match($Text, $CtrlVObject)
    if (-not $m.Success) { return 'default' }          # Ctrl+V uses the built-in paste
    if ($m.Value -match '"id"\s*:\s*null') { return 'unbound' }
    return 'bound'
}

function Set-WtUnbound([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    $state = Get-WtState $text
    if ($state -eq 'unbound') { return "already done: $Path" }

    $wasValid = Test-JsonText $text
    if ($state -eq 'bound') {
        # Replace the existing Ctrl+V binding with an unbind.
        $new = ([regex]$CtrlVObject).Replace($text, $UnbindObject, 1)
    }
    elseif ($text -match '"keybindings"\s*:\s*\[') {
        $new = Add-ToArray $text 'keybindings'
    }
    elseif ($text -match '"actions"\s*:\s*\[') {
        $new = Add-ToArray $text 'actions'
    }
    else {
        $new = ([regex]'\{').Replace($text, "{`n    `"keybindings`": [ $UnbindObject ],", 1)
    }

    if ($wasValid -and -not (Test-JsonText $new)) {
        throw "Refusing to write ${Path}: the edit would produce invalid JSON. Nothing was changed."
    }
    $backup = Backup-File $Path
    [IO.File]::WriteAllText($Path, $new, $Utf8NoBom)
    return "unbound Ctrl+V in $Path (backup: $backup)"
}

function Add-ToArray([string]$Text, [string]$Name) {
    $re = [regex]('"' + $Name + '"\s*:\s*\[(\s*)(\])?')
    $m = $re.Match($Text)
    if ($m.Groups[2].Success) {
        # Empty array.
        $insert = "`"$Name`": [ $UnbindObject ]"
    }
    else {
        $insert = "`"$Name`": [$($m.Groups[1].Value)$UnbindObject,$($m.Groups[1].Value)"
    }
    return $Text.Substring(0, $m.Index) + $insert + $Text.Substring($m.Index + $m.Length)
}

function Set-WtRestored([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    if ((Get-WtState $text) -ne 'unbound') { return "nothing to revert: $Path" }
    $new = ([regex]$CtrlVObject).Replace($text, $PasteObject, 1)
    $backup = Backup-File $Path
    [IO.File]::WriteAllText($Path, $new, $Utf8NoBom)
    return "restored Ctrl+V paste in $Path (backup: $backup)"
}

# ---------------------------------------------------------------- Claude Code

function Get-ClaudeKeybindingsPath {
    $dir = $ClaudeConfigDir
    if (-not $dir) { $dir = $env:CLAUDE_CONFIG_DIR }
    if (-not $dir) { $dir = Join-Path $env:USERPROFILE '.claude' }
    return Join-Path $dir 'keybindings.json'
}

function Read-Keybindings([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = [IO.File]::ReadAllText($Path)
    if (-not $raw.Trim()) { return $null }
    try { return $raw | ConvertFrom-Json }
    catch { throw "$Path is not valid JSON. Fix it or move it aside, then run again." }
}

function Get-ChatBlock($Config) {
    if (-not $Config -or -not $Config.bindings) { return $null }
    return @($Config.bindings) | Where-Object { $_.context -eq 'Chat' } | Select-Object -First 1
}

function Get-ClaudeState([string]$Path) {
    $chat = Get-ChatBlock (Read-Keybindings $Path)
    if (-not $chat) { return 'missing' }
    $value = $chat.bindings.'ctrl+v'
    if ($null -eq $value) { return 'missing' }
    if ($value -eq 'chat:imagePaste') { return 'bound' }
    return "other:$value"
}

function Write-Keybindings([string]$Path, $Config) {
    $json = $Config | ConvertTo-Json -Depth 20
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $json + "`n", $Utf8NoBom)
}

function Set-ClaudeBinding([string]$Path) {
    $state = Get-ClaudeState $Path
    if ($state -eq 'bound') { return "already done: $Path" }
    if ($state -like 'other:*') {
        throw "Ctrl+V in $Path is already bound to '$($state.Substring(6))'. Remove that binding first if you want Ctrl+V to paste images."
    }

    $config = Read-Keybindings $Path
    $backup = $null
    if ($config) { $backup = Backup-File $Path }
    else {
        $config = [pscustomobject]@{
            '$schema' = 'https://www.schemastore.org/claude-code-keybindings.json'
            bindings  = @()
        }
    }
    if (-not ($config.PSObject.Properties.Name -contains 'bindings')) {
        $config | Add-Member -NotePropertyName bindings -NotePropertyValue @()
    }

    $chat = Get-ChatBlock $config
    if ($chat) {
        $chat.bindings | Add-Member -NotePropertyName 'ctrl+v' -NotePropertyValue 'chat:imagePaste' -Force
    }
    else {
        $config.bindings = @($config.bindings) + [pscustomobject]@{
            context  = 'Chat'
            bindings = [pscustomobject]@{ 'ctrl+v' = 'chat:imagePaste' }
        }
    }
    Write-Keybindings $Path $config
    if ($backup) { return "bound Ctrl+V to chat:imagePaste in $Path (backup: $backup)" }
    return "created $Path with Ctrl+V bound to chat:imagePaste"
}

function Remove-ClaudeBinding([string]$Path) {
    if ((Get-ClaudeState $Path) -ne 'bound') { return "nothing to revert: $Path" }
    $config = Read-Keybindings $Path
    $backup = Backup-File $Path
    $chat = Get-ChatBlock $config
    $chat.bindings.PSObject.Properties.Remove('ctrl+v')
    if (-not @($chat.bindings.PSObject.Properties).Count) {
        $config.bindings = @(@($config.bindings) | Where-Object { $_ -ne $chat })
    }
    Write-Keybindings $Path $config
    return "removed the Ctrl+V binding from $Path (backup: $backup)"
}

# ---------------------------------------------------------------- main

$wtFiles = @(Get-WtSettingsFiles)
$kbPath = Get-ClaudeKeybindingsPath

if ($Status) {
    if (-not $wtFiles.Count) { Write-Output 'Windows Terminal: settings.json not found' }
    foreach ($f in $wtFiles) {
        $label = @{ default = 'Ctrl+V pastes (Windows Terminal default)'; bound = 'Ctrl+V pastes (explicit binding)'; unbound = 'Ctrl+V passed through to the app' }[(Get-WtState ([IO.File]::ReadAllText($f)))]
        Write-Output "Windows Terminal: $label  [$f]"
    }
    $cs = Get-ClaudeState $kbPath
    $label = if ($cs -eq 'bound') { 'Ctrl+V -> chat:imagePaste' } elseif ($cs -eq 'missing') { 'no Ctrl+V binding (Alt+V pastes images)' } else { "Ctrl+V -> $($cs.Substring(6))" }
    Write-Output "Claude Code: $label  [$kbPath]"
    exit 0
}

if (-not $wtFiles.Count) {
    Write-Output 'Windows Terminal settings.json was not found. Open Windows Terminal once (Ctrl+, then Save) and run this again.'
    exit 1
}

if ($Revert) {
    foreach ($f in $wtFiles) { Write-Output (Set-WtRestored $f) }
    Write-Output (Remove-ClaudeBinding $kbPath)
}
else {
    # Claude Code first: if it fails, Windows Terminal is left untouched.
    Write-Output (Set-ClaudeBinding $kbPath)
    foreach ($f in $wtFiles) { Write-Output (Set-WtUnbound $f) }
}
Write-Output 'Done. Open a new Claude Code session for the change to take effect.'
