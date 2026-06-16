#!/bin/bash
# install_nerd_fonts.sh — Install Cascadia (CaskaydiaCove) and FiraCode Nerd Fonts
# Detects WSL vs native Linux; on WSL it installs into the Windows host per-user.
#
# Naming note (this confused us before):
#   • Archive name : CascadiaCode.zip   (named after Microsoft's "Cascadia Code")
#   • The font carries TWO family names. DirectWrite apps (Windows Terminal, VS Code) use the
#     full typographic name "CaskaydiaCove Nerd Font" (Mono variant: "… Mono", Propo: "… Propo")
#     — that is what to put in their config. Legacy GDI / GDI+ tools (and PowerShell's
#     System.Drawing / WPF SystemFontFamilies enumerations) instead show the abbreviated GDI
#     name "CaskaydiaCove NF"/"NFM"/"NFP" (Windows' 32-char GDI name limit truncates "Nerd
#     Font"→"NF"). Same font, two names; don't be fooled by a GDI enumeration into thinking the
#     full name is missing — WT's own font picker lists "CaskaydiaCove Nerd Font". FiraCode's
#     base name is short enough to keep the full name in both tables.
#   • The patched font is renamed (Cascadia→Caskaydia, Code→Cove) because Cascadia Code ships
#     under a Reserved Font Name (OFL) that forbids redistributing a modified copy as-is.
#
# Reliability note (why fonts used to vanish after a reboot):
#   Per-user fonts live in %LOCALAPPDATA%\Microsoft\Windows\Fonts, which is NOT on the font
#   search path. The HKCU registry value MUST therefore be the FULL ABSOLUTE PATH to the
#   .ttf — a bare filename loads only for the live session (AddFontResource is session-only)
#   and is dropped at the next logon. Refs: oh-my-posh#4169, scoop-nerd-fonts manifest,
#   MS "Font Installation and Deletion". This script writes the full path and self-heals
#   any old bare-filename entries.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CASCADIA_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip"
FIRACODE_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip"

IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
fi

if $IS_WSL; then
    echo "Detected WSL environment. Checking Windows host fonts..."
    WIN_LOCALAPPDATA=$(cmd.exe /c "echo %LOCALAPPDATA%" 2>/dev/null | tr -d '\r')
    WSL_LOCALAPPDATA=$(wslpath -u "$WIN_LOCALAPPDATA")

    WIN_APPDATA=$(cmd.exe /c "echo %APPDATA%" 2>/dev/null | tr -d '\r')
    WSL_APPDATA=$(wslpath -u "$WIN_APPDATA")

    WIN_FONTS_DIR="$WSL_LOCALAPPDATA/Microsoft/Windows/Fonts"
    WT_SETTINGS="$WSL_LOCALAPPDATA/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
    VSCODE_SETTINGS="$WSL_APPDATA/Code/User/settings.json"
    REG_FONTS='HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

    # PowerShell payload: download (only if the real patched files are missing), copy into the
    # per-user Fonts dir, and register each face with the FULL PATH as the value — overwriting
    # any stale bare-filename entry in place. Loads into the live session only when something
    # actually changed, so repeat runs are silent no-ops.
    cat << 'EOF' > /tmp/install_fonts.ps1
param([string]$FontUrl, [string]$ZipName, [string]$FilePattern)
$ErrorActionPreference = "Stop"

$out = "$env:TEMP\$ZipName.zip"
$extractPath = "$env:TEMP\$ZipName"
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

New-Item -ItemType Directory -Force -Path $fontDir | Out-Null

# Download + extract only when the patched files are absent. Match the REAL file names
# (CaskaydiaCove*/FiraCode*), not the archive name, so this guard actually fires.
if (-not (Test-Path (Join-Path $fontDir $FilePattern))) {
    Write-Host "  Downloading $ZipName.zip ..."
    Invoke-WebRequest -Uri $FontUrl -OutFile $out
    Expand-Archive $out -DestinationPath $extractPath -Force
    Get-ChildItem "$extractPath\*.ttf" | ForEach-Object {
        Copy-Item $_.FullName -Destination (Join-Path $fontDir $_.Name) -Force
    }
}

Add-Type -AssemblyName PresentationCore
$changed = 0

Get-ChildItem (Join-Path $fontDir $FilePattern) | ForEach-Object {
    $destPath = $_.FullName
    $fileName = $_.Name

    # Derive the registry name from the font's own GDI metadata (e.g. "CaskaydiaCove NF Bold").
    try {
        $gt = New-Object System.Windows.Media.GlyphTypeface($destPath)
        $family = [System.Linq.Enumerable]::FirstOrDefault($gt.Win32FamilyNames.Values)
        $face   = [System.Linq.Enumerable]::FirstOrDefault($gt.Win32FaceNames.Values)
        $regName = if ($face -eq "Regular" -or $face -eq "Normal") { "$family (TrueType)" } else { "$family $face (TrueType)" }
    } catch {
        $regName = $fileName.Replace(".ttf", "") + " (TrueType)"
    }

    # Drop any legacy bare-filename-named entry from older script versions.
    $badName = $fileName.Replace(".ttf", "") + " (TrueType)"
    if ($badName -ne $regName) { Remove-ItemProperty -Path $regPath -Name $badName -ErrorAction SilentlyContinue }

    # Persist with the FULL PATH (the load-bearing fix). Only rewrite when it isn't already correct.
    $current = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue).$regName
    if ($current -ne $destPath) {
        New-ItemProperty -Path $regPath -Name $regName -Value $destPath -Force | Out-Null
        $changed++
    }
}

# AddFontResource = session-only; the full-path registry entry above is what persists. Only
# load + broadcast when something changed, so already-correct runs stay quiet.
if ($changed -gt 0) {
    $code = @"
using System;
using System.Runtime.InteropServices;
public class FontCache {
    [DllImport("gdi32.dll", CharSet = CharSet.Auto)]
    public static extern int AddFontResource(string lpszFilename);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public const uint WM_FONTCHANGE = 0x001D;
    public static readonly IntPtr HWND_BROADCAST = new IntPtr(0xffff);
    public static void Notify(string fontPath) { AddFontResource(fontPath); }
    public static void Broadcast() { SendMessage(HWND_BROADCAST, WM_FONTCHANGE, IntPtr.Zero, IntPtr.Zero); }
}
"@
    try {
        Add-Type -TypeDefinition $code -Language CSharp
        Get-ChildItem (Join-Path $fontDir $FilePattern) | ForEach-Object { [FontCache]::Notify($_.FullName) }
        [FontCache]::Broadcast()
    } catch {
        Write-Host "  Warning: could not broadcast font change to the OS; a re-login may be needed."
    }
}

if (Test-Path $out) { Remove-Item $out -Force }
if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }

if ($changed -gt 0) { Write-Host "STATUS:REPAIRED ($changed faces)" } else { Write-Host "STATUS:OK" }
EOF

    # A font is correctly installed iff HKCU has an entry whose VALUE is a full path (drive
    # letter + backslash). This also detects the old bare-filename state and triggers repair.
    font_fullpath_registered() {  # $1 = family-name substring (case-insensitive)
        reg.exe query "$REG_FONTS" 2>/dev/null | grep -iE "$1"'.*REG_SZ.*[A-Za-z]:\\' >/dev/null 2>&1
    }

    install_or_repair() {  # $1=url $2=zipname $3=file-glob $4=reg-match $5=friendly
        if font_fullpath_registered "$4"; then
            echo -e "${GREEN}✓ $5 already installed (full-path registry entry).${NC}"
        else
            echo -e "${YELLOW}$5 missing or registered with a bare filename (lost on reboot). Fixing...${NC}"
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /tmp/install_fonts.ps1)" \
                -FontUrl "$1" -ZipName "$2" -FilePattern "$3" | tr -d '\r'
            echo -e "${GREEN}✓ $5 registered with full path.${NC}"
        fi
    }

    # 1. CaskaydiaCove (archive: CascadiaCode.zip) — GDI family "CaskaydiaCove NF"
    install_or_repair "$CASCADIA_URL" "CascadiaCode" "CaskaydiaCove*.ttf" "CaskaydiaCove" \
        "CaskaydiaCove Nerd Font (from CascadiaCode.zip)"

    # 2. FiraCode — family "FiraCode Nerd Font"
    install_or_repair "$FIRACODE_URL" "FiraCode" "FiraCode*.ttf" "FiraCode Nerd Font" \
        "FiraCode Nerd Font"

    rm -f /tmp/install_fonts.ps1

    # 3. Check Windows Terminal config. WT uses DirectWrite, so the face is the full
    #    typographic name "CaskaydiaCove Nerd Font" ("… Mono" for single-width icons).
    if [ -f "$WT_SETTINGS" ]; then
        if grep -qi "CaskaydiaCove" "$WT_SETTINGS"; then
            echo -e "${GREEN}✓ Windows Terminal configured with CaskaydiaCove Nerd Font.${NC}"
        else
            echo -e "\n${YELLOW}[ACTION REQUIRED] Set the Windows Terminal font face to 'CaskaydiaCove Nerd Font'.${NC}"
            echo "  -> Settings (Ctrl+,) > Defaults > Appearance > Font face > 'CaskaydiaCove Nerd Font' ('… Mono' for single-width icons)."
        fi
    else
        echo -e "${YELLOW}~ Could not locate Windows Terminal settings. Set the font face to 'CaskaydiaCove Nerd Font' manually.${NC}"
    fi

    # 4. Check VS Code config
    if [ -f "$VSCODE_SETTINGS" ]; then
        if ! grep -qi "FiraCode" "$VSCODE_SETTINGS" && ! grep -qi "Fira Code" "$VSCODE_SETTINGS"; then
            echo -e "\n${YELLOW}[ACTION REQUIRED] VS Code (Windows) is not configured to use FiraCode Nerd Font!${NC}"
            echo "  -> Settings (Ctrl+,) > search 'Font Family' > add 'FiraCode Nerd Font', to the front."
        else
            echo -e "${GREEN}✓ VS Code (Windows) configured with FiraCode.${NC}"
        fi
    else
        echo -e "${YELLOW}~ Could not locate VS Code settings. Please configure your editor font manually.${NC}"
    fi

else
    echo "Detected native Linux environment. Installing fonts locally..."
    LINUX_FONTS_DIR="$HOME/.local/share/fonts"
    mkdir -p "$LINUX_FONTS_DIR"

    # 1. Install Cascadia (CaskaydiaCove)
    if ! ls "$LINUX_FONTS_DIR" 2>/dev/null | grep -qi "CaskaydiaCove"; then
        echo "Downloading and installing CaskaydiaCove Nerd Font (CascadiaCode.zip)..."
        TMP_DIR=$(mktemp -d)
        curl -sL "$CASCADIA_URL" -o "$TMP_DIR/Cascadia.zip"
        unzip -q "$TMP_DIR/Cascadia.zip" -d "$TMP_DIR/Cascadia"
        cp "$TMP_DIR/Cascadia/"*.ttf "$LINUX_FONTS_DIR/"
        rm -rf "$TMP_DIR"
        fc-cache -f "$LINUX_FONTS_DIR"
    else
        echo -e "${GREEN}✓ CaskaydiaCove Nerd Font already installed locally.${NC}"
    fi

    # 2. Install FiraCode
    if ! ls "$LINUX_FONTS_DIR" 2>/dev/null | grep -qi "FiraCode"; then
        echo "Downloading and installing FiraCode Nerd Font..."
        TMP_DIR=$(mktemp -d)
        curl -sL "$FIRACODE_URL" -o "$TMP_DIR/FiraCode.zip"
        unzip -q "$TMP_DIR/FiraCode.zip" -d "$TMP_DIR/FiraCode"
        cp "$TMP_DIR/FiraCode/"*.ttf "$LINUX_FONTS_DIR/"
        rm -rf "$TMP_DIR"
        fc-cache -f "$LINUX_FONTS_DIR"
    else
        echo -e "${GREEN}✓ FiraCode Nerd Font already installed locally.${NC}"
    fi

    # 3. Check VS Code config
    VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
    if [ -f "$VSCODE_SETTINGS" ]; then
        if ! grep -qi "FiraCode" "$VSCODE_SETTINGS" && ! grep -qi "Fira Code" "$VSCODE_SETTINGS"; then
            echo -e "\n${YELLOW}[ACTION REQUIRED] VS Code (Linux) is not configured to use FiraCode Nerd Font!${NC}"
            echo "  -> Settings (Ctrl+,) > search 'Font Family' > add 'FiraCode Nerd Font', to the front."
        else
            echo -e "${GREEN}✓ VS Code (Linux) configured with FiraCode.${NC}"
        fi
    fi

    # 4. Prompt for local terminal
    echo -e "\n${YELLOW}[ACTION REQUIRED] Ensure your Linux terminal uses 'CaskaydiaCove Nerd Font' or 'FiraCode Nerd Font'.${NC}"
fi

echo -e "\n${GREEN}Font check and installation complete!${NC}"
