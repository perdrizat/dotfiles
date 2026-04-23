#!/bin/bash
# expand_wsl_disk.sh — Expand WSL2 disk space from within Ubuntu
#
# Usage: expand_wsl_disk.sh [SIZE]
#   SIZE: new size in GB (e.g., 50, 100, 200) or G/GB suffix (e.g., 50G, 100GB)
#         omit to be prompted interactively
#
# Requirements: WSL2, powershell.exe, diskpart.exe, sudo, resize2fs
# Admin elevation: requires UAC prompt on Windows for diskpart

set -uo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Functions ---

print_header() {
    printf "\n${BOLD}%s${NC}\n" "$1"
}

print_error() {
    printf "${RED}ERROR: %s${NC}\n" "$1" >&2
}

print_success() {
    printf "${GREEN}OK: %s${NC}\n" "$1"
}

print_info() {
    printf "${CYAN}INFO: %s${NC}\n" "$1"
}

# Guard: check we're in WSL2
check_wsl() {
    if ! grep -qi microsoft /proc/version 2>/dev/null; then
        print_error "Not running in WSL2 (no 'microsoft' in /proc/version)"
        exit 1
    fi
    if [ -z "${WSL_DISTRO_NAME:-}" ]; then
        print_error "WSL_DISTRO_NAME not set"
        exit 1
    fi
    print_success "Running in WSL2 ($WSL_DISTRO_NAME)"
}

# Find VHDX path in Windows registry
find_vhdx_path() {
    local distro_name="$1"
    local vhdx_path

    # Query registry for the distro's BasePath
    local registry_output
    registry_output=$(powershell.exe -Command "\$d = Get-ChildItem 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Lxss' | Where-Object { (Get-ItemProperty \$_.PSPath).DistributionName -eq '$distro_name' }; if (\$d) { (Get-ItemProperty \$d.PSPath).BasePath } else { Write-Host 'NOT_FOUND' }" 2>/dev/null | sed 's/[[:space:]]*$//')

    if [ -z "$registry_output" ] || [ "$registry_output" = "NOT_FOUND" ]; then
        print_error "Could not find VHDX path for distro '$distro_name' in Windows registry"
        exit 1
    fi

    # Find the ext4.vhdx in the BasePath
    local win_vhdx
    win_vhdx=$(powershell.exe -Command "Get-ChildItem '$registry_output' -Filter 'ext4.vhdx' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName" 2>/dev/null | sed 's/[[:space:]]*$//')

    if [ -z "$win_vhdx" ]; then
        print_error "Could not find ext4.vhdx in $registry_output"
        exit 1
    fi

    echo "$win_vhdx"
}

# Convert size (e.g., "50G", "100GB", "50") to MB
size_to_mb() {
    local size="$1"
    local num

    # Remove trailing B if present (G, GB -> just G)
    size="${size%B}"

    if [[ "$size" =~ ^([0-9]+)([KMGT])?$ ]]; then
        num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]:-G}"

        case "$unit" in
            K) echo $((num * 1024 / 1024)) ;;               # KB to MB
            M) echo "$num" ;;                                # MB
            G) echo $((num * 1024)) ;;                       # GB to MB
            T) echo $((num * 1024 * 1024)) ;;               # TB to MB
            *) echo "$num" ;;                                # assume GB
        esac
    else
        print_error "Invalid size format: $size (use 50, 50G, 50GB, etc.)"
        exit 1
    fi
}

# Get current filesystem size in GiB (what's actually mounted, not VHDX file size)
# Returns the size in GiB, rounded to match 'df -h' output
get_filesystem_size() {
    local size_kb
    size_kb=$(df / | tail -1 | awk '{print $2}')
    # Convert KiB to GiB with proper rounding: KB / 1024 / 1024, rounded
    awk "BEGIN {printf \"%.0f\", $size_kb / 1024 / 1024}"
}

# Get current VHDX file size in MB (for reference/info)
get_vhdx_size() {
    local vhdx_path="$1"
    powershell.exe -Command "[int]((Get-Item '$vhdx_path').Length / 1MB)" 2>/dev/null | sed 's/[[:space:]]*$//'
}

# Prompt for size if not provided
prompt_for_size() {
    local current_gib="$1"
    local default_gib=$((current_gib * 2))
    local size_input

    {
        echo ""
        echo "Current filesystem size: $current_gib GiB"
        printf "Enter new size (e.g., 50, 100G, 200GB) [default: %d]: " "$default_gib"
    } >&2

    read -r size_input || size_input=""
    [ -z "$size_input" ] && size_input="$default_gib"
    # size_to_mb returns MB, we need to convert to GiB
    local size_mb
    size_mb=$(size_to_mb "$size_input")
    echo $((size_mb / 1024))
}

# Run diskpart to expand VHDX
expand_vhdx() {
    local vhdx_path="$1"
    local new_mb="$2"

    # Create a temp diskpart script
    local temp_script
    temp_script=$(mktemp)
    trap "rm -f $temp_script" EXIT

    cat > "$temp_script" <<EOF
select vdisk file="$vhdx_path"
expand vdisk maximum=$new_mb
exit
EOF

    # Convert the Linux path to Windows path
    local win_script
    win_script=$(wslpath -w "$temp_script")

    print_info "Wrote diskpart script to: $win_script"
    print_info "Running diskpart with Windows admin elevation (UAC prompt on Windows)..."

    # Run diskpart with elevation
    # Note: -Verb RunAs requires Windows Terminal or similar to handle UAC
    powershell.exe -Command "Start-Process -FilePath 'diskpart.exe' -ArgumentList '/s \"$win_script\"' -Verb RunAs -Wait" 2>/dev/null

    if [ $? -ne 0 ]; then
        print_error "diskpart failed or was cancelled"
        exit 1
    fi

    print_success "VHDX expanded successfully"
}

# Resize the filesystem
resize_filesystem() {
    local device="${1:-/dev/sdd}"

    print_info "Resizing ext4 filesystem on $device..."
    if ! sudo resize2fs "$device" 2>&1; then
        print_error "resize2fs failed"
        exit 1
    fi
    print_success "Filesystem resized"
}

# Show current disk usage
show_disk_usage() {
    printf "\n${BOLD}Disk usage:${NC}\n"
    df -h / | tail -1
}

# Main flow
main() {
    print_header "WSL2 Disk Expansion"

    check_wsl

    local root_device="/dev/sdd"  # typical for WSL2
    local vhdx_path
    local current_mb
    local new_mb

    print_info "Finding VHDX path..."
    vhdx_path=$(find_vhdx_path "$WSL_DISTRO_NAME")
    print_success "Found: $vhdx_path"

    print_info "Getting current filesystem size..."
    local current_gib
    current_gib=$(get_filesystem_size)
    local vhdx_mb
    vhdx_mb=$(get_vhdx_size "$vhdx_path")
    local vhdx_gib=$((vhdx_mb / 1024))
    print_success "Current filesystem size: $current_gib GiB"
    print_info "VHDX file size: $vhdx_gib GiB ($vhdx_mb MiB)"

    # Get desired size from argument or prompt
    if [ $# -ge 1 ]; then
        new_gib=$(size_to_mb "$1")
        new_gib=$((new_gib / 1024))  # Convert MB result to GiB
    else
        new_gib=$(prompt_for_size "$current_gib")
    fi

    print_info "Requested new size: $new_gib GiB"

    if [ "$new_gib" -le "$current_gib" ]; then
        print_error "New size must be larger than current size ($current_gib GiB)"
        exit 1
    fi

    # Convert GiB back to MB for diskpart
    local new_mb=$((new_gib * 1024))

    # Confirm before proceeding
    printf "\n${BOLD}Confirm:${NC}\n"
    printf '  VHDX: %s\n' "$vhdx_path"
    printf '  Current size: %d GiB\n' "$current_gib"
    printf '  New size: %d GiB\n' "$new_gib"
    printf "${YELLOW}This requires Windows admin elevation (UAC prompt).${NC}\n"
    printf "Proceed? (y/n) [n]: "
    read -r confirm

    if [ "${confirm,,}" != "y" ]; then
        print_info "Cancelled"
        exit 0
    fi

    expand_vhdx "$vhdx_path" "$new_mb"
    resize_filesystem "$root_device"
    show_disk_usage

    print_success "Done!"
}

# Handle help and dryrun flags
case "${1:-}" in
    --help|-h)
        cat <<EOF
${BOLD}Usage:${NC} $(basename "$0") [SIZE]

${BOLD}Arguments:${NC}
  SIZE    New disk size (e.g., 50, 100G, 200GB). Omit to be prompted.

${BOLD}Examples:${NC}
  $(basename "$0")          # prompt for size
  $(basename "$0") 50       # expand to 50 GB
  $(basename "$0") 100G     # expand to 100 GB

${BOLD}Requirements:${NC}
  - WSL2 (Windows Subsystem for Linux 2)
  - Windows admin rights (for diskpart)
  - resize2fs (usually pre-installed)

${BOLD}What it does:${NC}
  1. Finds your distro's VHDX file via Windows registry
  2. Expands it via diskpart.exe (prompts for Windows admin)
  3. Resizes the filesystem with resize2fs

${BOLD}Notes:${NC}
  - A UAC prompt will appear on Windows
  - You may need to log out and back in for the new space to appear
  - The filesystem resize is automatic on modern WSL2
EOF
        exit 0
        ;;
    --dryrun)
        print_header "WSL2 Disk Expansion (DRY RUN)"
        check_wsl
        vhdx_path=$(find_vhdx_path "$WSL_DISTRO_NAME")
        current_gib=$(get_filesystem_size)
        vhdx_mb=$(get_vhdx_size "$vhdx_path")
        vhdx_gib=$((vhdx_mb / 1024))
        print_success "Found VHDX: $vhdx_path"
        print_success "Current filesystem size: $current_gib GiB"
        print_info "VHDX file size: $vhdx_gib GiB ($vhdx_mb MiB)"
        print_info "Run without --dryrun to actually expand"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        main "$1"
        ;;
esac
