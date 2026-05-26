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

# --- Colors (ANSI-C quoted so escape chars are real ESC, not literal '\033') ---
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

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

# Get the device that has the root filesystem mounted
get_root_device() {
    df / | tail -1 | awk '{print $1}'
}

# Get current filesystem size in GiB (what's actually mounted, not VHDX file size)
# Returns the size in GiB, rounded to match 'df -h' output
get_filesystem_size() {
    local size_kb
    size_kb=$(df / | tail -1 | awk '{print $2}')
    # Convert KiB to GiB with proper rounding: KB / 1024 / 1024, rounded
    awk "BEGIN {printf \"%.0f\", $size_kb / 1024 / 1024}"
}

# Get Linux block device size in MiB (reflects VHDX max capacity, not file size)
get_block_device_size_mib() {
    local device="$1"  # e.g., /dev/sdd
    local devname
    devname=$(basename "$device")
    local sectors
    sectors=$(cat "/sys/block/$devname/size" 2>/dev/null || echo 0)
    # 512-byte sectors -> MiB
    echo $((sectors * 512 / 1024 / 1024))
}

# Force the Linux kernel to re-read the SCSI device size (idempotent).
# Critical when the VHDX was expanded earlier but Linux didn't pick up the new
# capacity — without this, /sys/block/<dev>/size stays stale and df reports
# the old size even though Windows already grew the VHDX.
rescan_block_device() {
    local device="$1"
    local devname
    devname=$(basename "$device")
    local rescan_path="/sys/block/$devname/device/rescan"
    if [ -e "$rescan_path" ]; then
        echo 1 | sudo tee "$rescan_path" >/dev/null 2>&1 || true
    fi
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
    local root_device="$3"

    # Record block device size before to verify expansion succeeded.
    # Use the Linux block device size, NOT the VHDX file size — the VHDX file
    # is sparse, so its physical size doesn't track max capacity changes.
    local size_before_mib
    size_before_mib=$(get_block_device_size_mib "$root_device")

    # Write the diskpart script to the Windows TEMP directory (not WSL /tmp)
    # This avoids failures when the WSL filesystem is full
    local diskpart_content="select vdisk file=\"$vhdx_path\"
expand vdisk maximum=$new_mb
exit"

    print_info "Writing diskpart script to Windows TEMP..."
    local win_script
    win_script=$(powershell.exe -Command "
        \$path = Join-Path \$env:TEMP 'wsl_expand_diskpart.txt'
        Set-Content -Path \$path -Value @'
$diskpart_content
'@ -NoNewline
        if (Test-Path \$path) { Write-Output \$path } else { Write-Output 'WRITE_FAILED' }
    " 2>/dev/null | sed 's/[[:space:]]*$//')

    if [ -z "$win_script" ] || [ "$win_script" = "WRITE_FAILED" ]; then
        print_error "Failed to write diskpart script to Windows TEMP"
        exit 1
    fi

    print_info "Diskpart script: $win_script"
    print_info "Running diskpart with Windows admin elevation (UAC prompt on Windows)..."

    # Run diskpart with elevation, capturing exit code and output via a log file
    # (Start-Process -Verb RunAs opens a new console that closes immediately; redirect to a log)
    local ps_output
    ps_output=$(powershell.exe -Command "
        \$log = Join-Path \$env:TEMP 'wsl_expand_diskpart.log'
        \$cmdArg = '/c diskpart /s \"$win_script\" > \"' + \$log + '\" 2>&1'
        \$proc = Start-Process -FilePath 'cmd.exe' -ArgumentList \$cmdArg -Verb RunAs -Wait -PassThru
        Write-Output \"EXITCODE=\$(\$proc.ExitCode)\"
        Write-Output \"LOGPATH=\$log\"
        if (Test-Path \$log) { Write-Output '---DISKPART LOG---'; Get-Content \$log }
    " 2>&1)

    # Strip Windows CRLF that PowerShell emits when piped to non-PowerShell consumers
    ps_output=$(printf '%s' "$ps_output" | tr -d '\r')

    # Surface diskpart's actual output for diagnosis
    printf "${CYAN}--- diskpart raw output ---${NC}\n%s\n${CYAN}---------------------------${NC}\n" "$ps_output"

    # Parse exit code (we keep the script + log on failure for inspection)
    local diskpart_exit
    diskpart_exit=$(echo "$ps_output" | awk -F= '/^EXITCODE=/ {print $2; exit}')

    if [ -z "$diskpart_exit" ] || [ "$diskpart_exit" != "0" ]; then
        print_error "diskpart exited with code: ${diskpart_exit:-unknown}"
        print_error "Script kept for inspection: $win_script"
        exit 1
    fi

    # Rescan so the kernel picks up the new VHDX max capacity
    rescan_block_device "$root_device"
    local size_after_mib
    size_after_mib=$(get_block_device_size_mib "$root_device")

    if [ "$size_after_mib" -le "$size_before_mib" ]; then
        print_error "Block device did not grow (before: ${size_before_mib} MiB, after: ${size_after_mib} MiB)"
        print_error "diskpart returned success — check the log above for what actually happened."
        print_error "Script kept for inspection: $win_script"
        exit 1
    fi

    # Clean up only on success
    powershell.exe -Command "Remove-Item '$win_script' -ErrorAction SilentlyContinue" 2>/dev/null
    print_success "Block device expanded: ${size_before_mib} MiB -> ${size_after_mib} MiB"
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
    if [ "$DRY_RUN" = true ]; then
        print_header "WSL2 Disk Expansion (DRY RUN)"
    else
        print_header "WSL2 Disk Expansion"
    fi

    check_wsl

    local root_device
    root_device=$(get_root_device)
    local vhdx_path
    local new_mb

    print_info "Finding VHDX path..."
    vhdx_path=$(find_vhdx_path "$WSL_DISTRO_NAME")
    print_success "Found: $vhdx_path"

    # Rescan the block device first — picks up any prior VHDX expansion the
    # kernel missed, so we don't try to re-run diskpart against a VHDX that's
    # already at the target (which fails with E_INVALIDARG).
    print_info "Rescanning block device to refresh kernel view..."
    rescan_block_device "$root_device"

    local current_block_mib
    current_block_mib=$(get_block_device_size_mib "$root_device")
    local current_block_gib=$((current_block_mib / 1024))
    local current_fs_gib
    current_fs_gib=$(get_filesystem_size)
    print_success "Block device: $current_block_gib GiB ($current_block_mib MiB); filesystem: $current_fs_gib GiB"

    # If dry-run with no size argument, just show current state and exit
    if [ "$DRY_RUN" = true ] && [ $# -eq 0 ]; then
        print_info "Run without -d/--dry-run to actually expand"
        return 0
    fi

    # Get desired size from argument or prompt
    local new_gib
    if [ $# -ge 1 ]; then
        new_gib=$(size_to_mb "$1")
        new_gib=$((new_gib / 1024))  # Convert MB result to GiB
    else
        new_gib=$(prompt_for_size "$current_fs_gib")
    fi

    print_info "Requested size: $new_gib GiB"
    new_mb=$((new_gib * 1024))

    # If everything is already at the requested size, nothing to do.
    if [ "$new_gib" -le "$current_fs_gib" ] && [ "$new_mb" -le "$current_block_mib" ]; then
        print_success "Already at or above requested size — nothing to do."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        printf "\n${BOLD}Would do:${NC}\n"
        printf '  VHDX: %s\n' "$vhdx_path"
        printf '  Current block: %d GiB; FS: %d GiB\n' "$current_block_gib" "$current_fs_gib"
        printf '  Target: %d GiB\n' "$new_gib"
        if [ "$new_mb" -le "$current_block_mib" ]; then
            printf '  Plan: rescan + resize2fs only (block device already large enough)\n'
        else
            printf '  Plan: diskpart expand + rescan + resize2fs\n'
        fi
        print_info "Run without -d/--dry-run to actually expand"
        return 0
    fi

    # Skip diskpart entirely if the block device is already big enough.
    # Common case: a previous expand succeeded on Windows but the kernel
    # didn't pick up the new size until the rescan above.
    if [ "$new_mb" -le "$current_block_mib" ]; then
        print_info "Block device already at $current_block_gib GiB (>= requested $new_gib GiB)"
        print_info "Skipping diskpart — just resizing the filesystem"
        resize_filesystem "$root_device"
        show_disk_usage
        print_success "Done!"
        return 0
    fi

    # Confirm before proceeding with diskpart
    printf "\n${BOLD}Confirm:${NC}\n"
    printf '  VHDX: %s\n' "$vhdx_path"
    printf '  Current block: %d GiB; FS: %d GiB\n' "$current_block_gib" "$current_fs_gib"
    printf '  New size: %d GiB\n' "$new_gib"
    printf "${YELLOW}This requires Windows admin elevation (UAC prompt).${NC}\n"
    printf "Proceed? (y/n) [n]: "
    read -r confirm

    if [ "${confirm,,}" != "y" ]; then
        print_info "Cancelled"
        exit 0
    fi

    expand_vhdx "$vhdx_path" "$new_mb" "$root_device"
    resize_filesystem "$root_device"
    show_disk_usage

    print_success "Done!"
}

show_help() {
    cat <<EOF
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS] [SIZE]

${BOLD}Options:${NC}
  -h, --help              Show this help and exit
  -d, --dry-run           Show what would happen without actually expanding

${BOLD}Arguments:${NC}
  SIZE    New disk size (e.g., 50, 100G, 200GB). Omit to be prompted.

${BOLD}Examples:${NC}
  $(basename "$0")              # prompt for size
  $(basename "$0") 50           # expand to 50 GiB
  $(basename "$0") 100G         # expand to 100 GiB
  $(basename "$0") -d           # dry-run, show current state
  $(basename "$0") -d 20        # dry-run, show what 20 GiB expansion would do

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
  - The filesystem resize is automatic on modern WSL2
EOF
}

# Parse arguments
DRY_RUN=false
SIZE_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run|--dryrun)
            DRY_RUN=true
            ;;
        -*)
            print_error "Unknown option: $1"
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
        *)
            if [ -n "$SIZE_ARG" ]; then
                print_error "Multiple size arguments given: '$SIZE_ARG' and '$1'"
                exit 1
            fi
            SIZE_ARG="$1"
            ;;
    esac
    shift
done

if [ -n "$SIZE_ARG" ]; then
    main "$SIZE_ARG"
else
    main
fi
