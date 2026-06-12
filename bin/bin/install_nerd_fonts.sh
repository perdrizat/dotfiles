#!/bin/bash
# install_nerd_fonts.sh — Install Cascadia and FiraCode Nerd Fonts
# Detects WSL vs native Linux to install properly and prompts to configure apps.
# Automatically fixes corrupted Windows registry font entries using internal font metadata.

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

    # Define PowerShell payload to download and cleanly register fonts using internal metadata
    cat << 'EOF' > /tmp/install_fonts.ps1
param([string]$FontUrl, [string]$ZipName)

$out = "$env:TEMP\$ZipName.zip"
$extractPath = "$env:TEMP\$ZipName"
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

# Only download if we don't have the files
if (-not (Test-Path $fontDir\*$ZipName*)) {
    Write-Host "Downloading $ZipName..."
    Invoke-WebRequest -Uri $FontUrl -OutFile $out
    Expand-Archive $out -DestinationPath $extractPath -Force
} else {
    Write-Host "Files exist, repairing registry metadata..."
    $extractPath = $fontDir
}

New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
Add-Type -AssemblyName PresentationCore

Get-ChildItem "$extractPath\*.ttf" | ForEach-Object {
    $fileName = $_.Name
    $destPath = Join-Path $fontDir $fileName
    
    # Copy file if it's not already in the destination
    if ($_.FullName -ne $destPath) {
        Copy-Item $_.FullName -Destination $destPath -Force
    }
    
    # Clean up any bad registry keys matching the raw filename from previous scripts
    $badName = $fileName.Replace(".ttf", "") + " (TrueType)"
    Remove-ItemProperty -Path $regPath -Name $badName -ErrorAction SilentlyContinue
    
    # Register with correct internal Windows metadata name
    try {
        $gt = New-Object System.Windows.Media.GlyphTypeface($destPath)
        $family = [System.Linq.Enumerable]::FirstOrDefault($gt.Win32FamilyNames.Values)
        $face = [System.Linq.Enumerable]::FirstOrDefault($gt.Win32FaceNames.Values)
        
        $regName = if ($face -eq "Regular" -or $face -eq "Normal") { "$family (TrueType)" } else { "$family $face (TrueType)" }
        New-ItemProperty -Path $regPath -Name $regName -Value $fileName -Force | Out-Null
    } catch {
        New-ItemProperty -Path $regPath -Name $badName -Value $fileName -Force | Out-Null
    }
}

# Compile C# to broadcast the font cache update to the OS without a reboot
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
    
    public static void Notify(string fontPath) {
        AddFontResource(fontPath);
    }
    public static void Broadcast() {
        SendMessage(HWND_BROADCAST, WM_FONTCHANGE, IntPtr.Zero, IntPtr.Zero);
    }
}
"@
try {
    Add-Type -TypeDefinition $code -Language CSharp
    Get-ChildItem "$fontDir\*.ttf" | ForEach-Object { [FontCache]::Notify($_.FullName) }
    [FontCache]::Broadcast()
} catch {
    Write-Host "Warning: Could not broadcast font change to OS. A restart may be required."
}

if (Test-Path $out) { Remove-Item $out -Force }
if (Test-Path "$env:TEMP\$ZipName") { Remove-Item "$env:TEMP\$ZipName" -Recurse -Force }
EOF

    # 1. Install / Repair Cascadia
    # We check if the internal font metadata name exists in the Windows Registry instead of just checking the file.
    if ! reg.exe query "HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" 2>/dev/null | grep -qi "CaskaydiaCove Nerd Font (TrueType)"; then
        echo -e "${YELLOW}CascadiaCode Nerd Font registry entry missing/corrupted. Fixing...${NC}"
        powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w /tmp/install_fonts.ps1)" -FontUrl "$CASCADIA_URL" -ZipName "CascadiaCode"
        echo -e "${GREEN}✓ CascadiaCode successfully registered.${NC}"
    else
        echo -e "${GREEN}✓ CascadiaCode Nerd Font already installed and registered in Windows.${NC}"
    fi

    # 2. Install / Repair FiraCode
    if ! reg.exe query "HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" 2>/dev/null | grep -qi "FiraCode Nerd Font (TrueType)"; then
        echo -e "${YELLOW}FiraCode Nerd Font registry entry missing/corrupted. Fixing...${NC}"
        powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w /tmp/install_fonts.ps1)" -FontUrl "$FIRACODE_URL" -ZipName "FiraCode"
        echo -e "${GREEN}✓ FiraCode successfully registered.${NC}"
    else
        echo -e "${GREEN}✓ FiraCode Nerd Font already installed and registered in Windows.${NC}"
    fi

    # Clean up powershell script
    rm -f /tmp/install_fonts.ps1

    # 3. Check Windows Terminal config
    if [ -f "$WT_SETTINGS" ]; then
        if ! grep -qi "CaskaydiaCove" "$WT_SETTINGS"; then
            echo -e "\n${YELLOW}[ACTION REQUIRED] Windows Terminal is not configured to use Cascadia Nerd Font!${NC}"
            echo "  -> Open Windows Terminal Settings (Ctrl+,)"
            echo "  -> Go to Defaults > Appearance"
            echo "  -> Set font to 'CaskaydiaCove Nerd Font'"
        else
            echo -e "${GREEN}✓ Windows Terminal configured with Cascadia.${NC}"
        fi
    else
        echo -e "${YELLOW}~ Could not locate Windows Terminal settings. Please configure your terminal font manually.${NC}"
    fi

    # 4. Check VS Code config
    if [ -f "$VSCODE_SETTINGS" ]; then
        if ! grep -qi "FiraCode" "$VSCODE_SETTINGS" && ! grep -qi "Fira Code" "$VSCODE_SETTINGS"; then
            echo -e "\n${YELLOW}[ACTION REQUIRED] VS Code (Windows) is not configured to use FiraCode Nerd Font!${NC}"
            echo "  -> Open VS Code Settings (Ctrl+,)"
            echo "  -> Search 'Font Family'"
            echo "  -> Add 'FiraCode Nerd Font', to the front of the list."
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
    
    # 1. Install Cascadia
    if ! ls "$LINUX_FONTS_DIR" 2>/dev/null | grep -qi "CaskaydiaCove"; then
        echo "Downloading and installing CascadiaCode Nerd Font..."
        TMP_DIR=$(mktemp -d)
        curl -sL "$CASCADIA_URL" -o "$TMP_DIR/Cascadia.zip"
        unzip -q "$TMP_DIR/Cascadia.zip" -d "$TMP_DIR/Cascadia"
        cp "$TMP_DIR/Cascadia/"*.ttf "$LINUX_FONTS_DIR/"
        rm -rf "$TMP_DIR"
        fc-cache -f "$LINUX_FONTS_DIR"
    else
        echo -e "${GREEN}✓ CascadiaCode Nerd Font already installed locally.${NC}"
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
            echo "  -> Open VS Code Settings (Ctrl+,)"
            echo "  -> Search 'Font Family'"
            echo "  -> Add 'FiraCode Nerd Font', to the front of the list."
        else
            echo -e "${GREEN}✓ VS Code (Linux) configured with FiraCode.${NC}"
        fi
    fi

    # 4. Prompt for local terminal
    echo -e "\n${YELLOW}[ACTION REQUIRED] Please ensure your native Linux terminal emulator is configured to use 'CaskaydiaCove Nerd Font' or 'FiraCode Nerd Font'.${NC}"
fi

echo -e "\n${GREEN}Font check and installation complete!${NC}"
