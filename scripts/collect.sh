#!/usr/bin/env bash
# =============================================================================
# collect.sh – AsVit Diagnostic Collector v1.0
# Copyright (c) 2026 AsVit. All rights reserved.
# Licensed under MIT License.
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
HOSTFS="${HOSTFS:-}"
OUT_ROOT="${OUT_ROOT:-}"
STAMP=$(date +%m.%d.%Y_%H-%M)
MASK_SERIALS=false
FORMAT="folder"
MAX_PARALLEL=4
NO_INTERACTIVE=false
SELECTED_TESTS=()
ALL_TESTS=("system" "storage" "network" "samba" "services" "docker" "stacks" "media" "users" "kernel" "gpu")

# Colors
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    NC=''
fi

# -----------------------------------------------------------------------------
# Parse command line arguments
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mask-serials)   MASK_SERIALS=true ;;
        --format)         FORMAT="$2"; shift ;;
        --output-dir)     OUT_ROOT="$2"; shift ;;
        --tests)          IFS=' ' read -ra SELECTED_TESTS <<< "$2"; shift ;;
        --max-parallel)   MAX_PARALLEL="$2"; shift ;;
        --no-interactive) NO_INTERACTIVE=true ;;
        --help|-h)
            cat <<HELP
Usage: $0 [OPTIONS]

Collect read-only system diagnostics. All sensitive data is masked.

Options:
  --mask-serials        Replace hardware serial numbers with ***MASKED***
  --format {folder|flat} Output structure (folder or flat JSON)
  --output-dir DIR      Output directory (default: current directory)
  --tests "list"        Space-separated test modules to run (default: all)
                        Available: ${ALL_TESTS[*]}
  --max-parallel N      Max concurrent background tasks (default: 4)
  --no-interactive      Skip interactive prompts
  --help                Show this help

Examples:
  $0 --tests "system storage network"
  $0 --format flat --mask-serials
HELP
            exit 0
            ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
    shift
done

# -----------------------------------------------------------------------------
# Interactive setup
# -----------------------------------------------------------------------------
if [[ "$NO_INTERACTIVE" == false && -t 0 ]]; then
    if [[ -z "$OUT_ROOT" ]]; then
        read -rp "Enter output directory (default: current directory): " out_dir
        OUT_ROOT="${out_dir:-.}"
    fi

    echo "Select output format:"
    echo "  1) folder - Hierarchical directory structure (multiple files)"
    echo "  2) flat   - Single JSON report (minimal files, ideal for analysis)"
    read -rp "Enter choice [1/2] (default: 1): " fmt_choice
    case "$fmt_choice" in
        2) FORMAT="flat" ;;
        *) FORMAT="folder" ;;
    esac

    echo ""
    echo "Select test modules to run (space-separated numbers, e.g., 1 3 5)"
    echo "Available modules:"
    for i in "${!ALL_TESTS[@]}"; do
        printf "  %2d) %s\n" $((i+1)) "${ALL_TESTS[$i]}"
    done
    echo "  all) All modules (default)"
    read -rp "Enter choices (or 'all'): " test_input
    if [[ "$test_input" == "all" || -z "$test_input" ]]; then
        SELECTED_TESTS=("${ALL_TESTS[@]}")
    else
        SELECTED_TESTS=()
        for num in $test_input; do
            if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#ALL_TESTS[@]} )); then
                SELECTED_TESTS+=("${ALL_TESTS[$((num-1))]}")
            else
                echo -e "${YELLOW}Warning: invalid number '$num' ignored${NC}"
            fi
        done
        if [[ ${#SELECTED_TESTS[@]} -eq 0 ]]; then
            echo -e "${YELLOW}No valid modules selected; running all.${NC}"
            SELECTED_TESTS=("${ALL_TESTS[@]}")
        fi
    fi
else
    OUT_ROOT="${OUT_ROOT:-.}"
    if [[ ${#SELECTED_TESTS[@]} -eq 0 ]]; then
        SELECTED_TESTS=("${ALL_TESTS[@]}")
    fi
fi

OUT_ROOT=$(realpath "$OUT_ROOT" 2>/dev/null || echo "$OUT_ROOT")
mkdir -p "$OUT_ROOT" || { echo -e "${RED}ERROR: Cannot create output dir '$OUT_ROOT'${NC}"; exit 1; }

echo -e "${GREEN}Output format: $FORMAT${NC}"
echo -e "${GREEN}Selected test modules: ${SELECTED_TESTS[*]}${NC}"
echo -e "${GREEN}Output directory: $OUT_ROOT${NC}"

# -----------------------------------------------------------------------------
# Determine if inside container
# -----------------------------------------------------------------------------
if [[ -d "/hostfs" ]]; then
    HOSTFS="/hostfs"
    REAL_ROOT="$HOSTFS"
else
    HOSTFS=""
    REAL_ROOT=""
fi

REPORT_DIR="${OUT_ROOT}/${STAMP}-config"
STAGE_DIR="${REPORT_DIR}/stage"
mkdir -p "$STAGE_DIR"

echo "=== Diagnostic collection started: $(date) ==="
echo "Report directory: $REPORT_DIR"
echo "Mask serial numbers: $MASK_SERIALS"
echo "Max parallel tasks: $MAX_PARALLEL"

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
mask_sensitive_file() {
    local src="$1" dst="$2"
    if [[ ! -f "$src" ]]; then
        echo "N/A - not found: $src" > "${dst}.missing"
        return
    fi
    sed -E \
        -e 's/^([A-Za-z0-9_]*)(PASSWORD|PASS|PWD|TOKEN|SECRET|API[_-]?KEY|APIKEY|KEY|SECRET_KEY)([A-Za-z0-9_]*)[[:space:]]*[:=][[:space:]]*.*/\1\2\3=***MASKED***/I' \
        -e 's/(<ApiKey>)[^<]*(</ApiKey>)/\1***MASKED***\2/I' \
        -e 's/("api_key"|"apikey"|"secret"|"token")\s*:\s*"[^"]*"/\1: "***MASKED***"/I' \
        -e 's/(WebUI\\Password[^=]*=).*/\1***MASKED***/I' \
        -e 's/(PGPASSWORD|MYSQL_PWD|MONGODB_PWD|REDIS_PASSWORD|AWS_SECRET_ACCESS_KEY)=[^ ]*/\1=***MASKED***/I' \
        -e 's/(Authorization:)[^"]*/\1 ***MASKED***/I' \
        -e 's/(x-api-key:)[^"]*/\1 ***MASKED***/I' \
        "$src" > "$dst" 2>/dev/null
}

safe_copy_masked() {
    local src="$1" dst="$2"
    if [[ -e "$src" ]]; then
        if [[ -f "$src" ]]; then
            mask_sensitive_file "$src" "$dst"
        else
            cp -r "$src" "$dst" 2>/dev/null
        fi
    else
        echo "N/A - not found: $src" > "${dst}.missing"
    fi
}

run_cmd() {
    local desc="$1" outfile="$2"
    shift 2
    echo "  [$desc]"
    if ! "$@" > "$outfile" 2>&1; then
        echo "ERROR (continuing): $*" >> "$outfile"
    fi
}

BG_PIDS=()
bg_task() {
    local name="$1" outfile="$2"
    shift 2
    while (( $(jobs -r | wc -l) >= MAX_PARALLEL )); do
        sleep 0.2
    done
    ( run_cmd "$name" "$outfile" "$@" ) &
    BG_PIDS+=($!)
}

has_cmd() {
    command -v "$1" &>/dev/null
}

# -----------------------------------------------------------------------------
# Module: system
# -----------------------------------------------------------------------------
run_system() {
    local dir="$STAGE_DIR/01_system"
    mkdir -p "$dir"
    run_cmd "uname" "$dir/uname.txt" uname -a
    [[ -f "${REAL_ROOT}/etc/os-release" ]] && run_cmd "os-release" "$dir/os-release.txt" cat "${REAL_ROOT}/etc/os-release"
    if has_cmd lscpu; then run_cmd "lscpu" "$dir/cpu.txt" lscpu; else run_cmd "cpuinfo" "$dir/cpu.txt" cat /proc/cpuinfo; fi
    run_cmd "free" "$dir/memory.txt" free -h
    run_cmd "uptime" "$dir/uptime.txt" uptime
    if has_cmd dmesg; then
        dmesg -T 2>/dev/null > "$dir/dmesg.txt" || dmesg > "$dir/dmesg.txt"
    fi
    run_cmd "cmdline" "$dir/cmdline.txt" cat /proc/cmdline 2>/dev/null
    run_cmd "modules" "$dir/modules.txt" lsmod 2>/dev/null || echo "lsmod not available"
    run_cmd "loadavg" "$dir/loadavg.txt" cat /proc/loadavg

    if has_cmd dmidecode; then
        local dmidecode_cmd="dmidecode"
        [[ "$MASK_SERIALS" == true ]] && dmidecode_cmd="dmidecode | sed -E 's/(Serial Number|Asset Tag|UUID):.*/\\1: ***MASKED***/I'"
        run_cmd "dmidecode_full" "$dir/dmidecode_full.txt" bash -c "$dmidecode_cmd"
        for type in system baseboard memory bios; do
            run_cmd "dmidecode_$type" "$dir/dmidecode_${type}.txt" bash -c "dmidecode -t $type | sed -E 's/(Serial Number|Asset Tag|UUID):.*/\\1: ***MASKED***/I' 2>/dev/null"
        done
    else
        echo "dmidecode not installed" > "$dir/dmidecode_full.txt"
    fi

    if has_cmd lspci; then run_cmd "lspci" "$dir/pci_devices.txt" lspci -vv; fi
    if has_cmd lsusb; then run_cmd "lsusb" "$dir/usb_devices.txt" lsusb -v; fi
    if has_cmd sysctl; then
        run_cmd "sysctl_hw" "$dir/sysctl_hw.txt" sysctl hw 2>/dev/null
        run_cmd "sysctl_kern" "$dir/sysctl_kern.txt" sysctl kern 2>/dev/null
    fi
}

# -----------------------------------------------------------------------------
# Module: storage
# -----------------------------------------------------------------------------
run_storage() {
    local dir="$STAGE_DIR/02_storage"
    mkdir -p "$dir"
    if has_cmd lsblk; then
        run_cmd "lsblk" "$dir/lsblk.txt" lsblk -f -o NAME,FSTYPE,SIZE,MOUNTPOINT,UUID,LABEL,MODEL
    else
        run_cmd "mount" "$dir/mount.txt" mount
    fi
    run_cmd "df" "$dir/df.txt" df -hT
    run_cmd "df_i" "$dir/df_inodes.txt" df -hi
    if has_cmd blkid; then run_cmd "blkid" "$dir/blkid.txt" blkid; fi
    [[ -f "${REAL_ROOT}/etc/fstab" ]] && run_cmd "fstab" "$dir/fstab.txt" cat "${REAL_ROOT}/etc/fstab"
    run_cmd "mounts" "$dir/mount.txt" mount
    if has_cmd swapon; then run_cmd "swaps" "$dir/swaps.txt" swapon --show; fi

    if has_cmd btrfs; then
        for cmd in "btrfs filesystem show" "btrfs filesystem usage /" "btrfs subvolume list /"; do
            outname=$(echo "$cmd" | tr ' /' '_')
            run_cmd "btrfs_$outname" "$dir/btrfs_${outname}.txt" bash -c "$cmd 2>/dev/null"
        done
        run_cmd "btrfs_mounts" "$dir/btrfs_mounts.txt" grep -E 'btrfs' /proc/mounts
    fi

    if has_cmd smartctl; then
        mkdir -p "$dir/smart"
        for dev in $(lsblk -dno NAME 2>/dev/null | grep -E '^(sd|nvme|hd|vd)'); do
            bg_task "smart_$dev" "$dir/smart/${dev}.txt" smartctl -a "/dev/${dev}"
        done
    fi

    if [[ -d /sys/block ]]; then
        mkdir -p "$dir/queue"
        for dev in /sys/block/*; do
            if [[ -d "$dev" ]]; then
                devname=$(basename "$dev")
                {
                    echo "Device: $devname"
                    cat "$dev/queue/scheduler" 2>/dev/null
                    cat "$dev/queue/read_ahead_kb" 2>/dev/null
                    cat "$dev/queue/nr_requests" 2>/dev/null
                } > "$dir/queue/${devname}.txt" 2>/dev/null
            fi
        done
    fi
}

# -----------------------------------------------------------------------------
# Module: network
# -----------------------------------------------------------------------------
run_network() {
    local dir="$STAGE_DIR/03_network"
    mkdir -p "$dir"
    if has_cmd ip; then
        run_cmd "ip_addr" "$dir/ip_addr.txt" ip addr show
        run_cmd "ip_route" "$dir/ip_route.txt" ip route show
        run_cmd "ip_link" "$dir/ip_link.txt" ip link show
    else
        run_cmd "ifconfig" "$dir/ifconfig.txt" ifconfig -a
        run_cmd "route" "$dir/route.txt" route -n
    fi
    if has_cmd ss; then
        run_cmd "ss_listen" "$dir/listening_ports.txt" ss -tulnp
        run_cmd "ss_conn" "$dir/active_connections.txt" ss -tuna
    else
        run_cmd "netstat_listen" "$dir/netstat_listen.txt" netstat -tulnp
        run_cmd "netstat_conn" "$dir/netstat_conn.txt" netstat -tuna
    fi
    [[ -f "${REAL_ROOT}/etc/resolv.conf" ]] && run_cmd "resolv.conf" "$dir/resolv.conf.txt" cat "${REAL_ROOT}/etc/resolv.conf"
    [[ -f "${REAL_ROOT}/etc/hostname" ]] && run_cmd "hostname" "$dir/hostname.txt" cat "${REAL_ROOT}/etc/hostname"
    [[ -f "${REAL_ROOT}/etc/hosts" ]] && run_cmd "hosts" "$dir/hosts.txt" cat "${REAL_ROOT}/etc/hosts"
    run_cmd "hostname_ips" "$dir/hostname_ips.txt" hostname -I 2>/dev/null || echo "hostname -I not supported"
    [[ -d "${REAL_ROOT}/etc/netplan" ]] && safe_copy_masked "${REAL_ROOT}/etc/netplan" "$dir/netplan"

    if has_cmd ufw; then run_cmd "ufw" "$dir/ufw_status.txt" ufw status verbose; fi
    if has_cmd iptables; then
        run_cmd "iptables" "$dir/iptables.txt" iptables -L -n -v
        run_cmd "iptables_nat" "$dir/iptables_nat.txt" iptables -t nat -L -n -v
    fi
    if has_cmd ip6tables; then run_cmd "ip6tables" "$dir/ip6tables.txt" ip6tables -L -n -v; fi
    if has_cmd arp; then run_cmd "arp" "$dir/arp.txt" arp -a; fi
}

# -----------------------------------------------------------------------------
# Module: samba
# -----------------------------------------------------------------------------
run_samba() {
    local dir="$STAGE_DIR/04_samba"
    mkdir -p "$dir"
    if [[ -f "${REAL_ROOT}/etc/samba/smb.conf" ]]; then
        safe_copy_masked "${REAL_ROOT}/etc/samba/smb.conf" "$dir/smb.conf"
        if has_cmd testparm; then
            run_cmd "testparm" "$dir/testparm.txt" testparm -s "${REAL_ROOT}/etc/samba/smb.conf" 2>/dev/null
        fi
        for svc in smbd nmbd wsdd; do
            if systemctl status "$svc" &>/dev/null 2>&1; then
                run_cmd "status_$svc" "$dir/${svc}_status.txt" systemctl status "$svc" --no-pager
            fi
        done
        if has_cmd journalctl; then
            run_cmd "wsdd_journal" "$dir/wsdd_journal.txt" journalctl -u wsdd --no-pager -n 500 2>/dev/null || echo "wsdd not found"
        fi
        if has_cmd ip; then
            run_cmd "multicast" "$dir/multicast.txt" ip maddr show
        fi
    fi
}

# -----------------------------------------------------------------------------
# Module: services
# -----------------------------------------------------------------------------
run_services() {
    local dir="$STAGE_DIR/05_services"
    mkdir -p "$dir"
    if has_cmd systemctl; then
        run_cmd "systemd_services" "$dir/running_services.txt" systemctl list-units --type=service --state=running --no-pager
    fi
    if has_cmd ps; then
        run_cmd "ps_auxf" "$dir/processes.txt" ps auxf
        run_cmd "pstree" "$dir/pstree.txt" pstree -a 2>/dev/null || echo "pstree not available"
    fi
    run_cmd "top" "$dir/top.txt" top -b -n1 -o %MEM 2>/dev/null || top -l 1 -o mem 2>/dev/null || echo "top not supported"
    run_cmd "user_cron" "$dir/user_cron.txt" crontab -l -u asvit 2>/dev/null || echo "No crontab for asvit"
    run_cmd "system_cron" "$dir/system_cron.txt" ls -la /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly 2>/dev/null || echo "No cron directories"

    if has_cmd journalctl; then
        mkdir -p "$dir/logs"
        for unit in ssh docker systemd-logind nginx traefik; do
            bg_task "journal_$unit" "$dir/logs/${unit}.txt" journalctl -u "$unit" --no-pager -n 500 2>/dev/null
        done
    fi
}

# -----------------------------------------------------------------------------
# Module: docker
# -----------------------------------------------------------------------------
run_docker() {
    if ! has_cmd docker; then
        echo -e "${YELLOW}Docker not found, skipping docker module${NC}"
        return
    fi
    local dir="$STAGE_DIR/06_docker"
    mkdir -p "$dir/inspect"
    run_cmd "docker_version" "$dir/docker_version.txt" docker version
    run_cmd "docker_info" "$dir/docker_info.txt" docker info
    run_cmd "docker_ps" "$dir/containers_list.txt" docker ps -a
    run_cmd "docker_images" "$dir/images_list.txt" docker images
    run_cmd "docker_volumes" "$dir/volumes_list.txt" docker volume ls
    run_cmd "docker_networks" "$dir/networks_list.txt" docker network ls
    run_cmd "docker_system_df" "$dir/system_df.txt" docker system df

    for c in $(docker ps -a --format '{{.Names}}'); do
        bg_task "inspect_$c" "$dir/inspect/${c}.json" docker inspect "$c"
    done
    for n in $(docker network ls --format '{{.Name}}'); do
        bg_task "network_$n" "$dir/inspect/network_${n}.json" docker network inspect "$n"
    done
}

# -----------------------------------------------------------------------------
# Module: stacks
# -----------------------------------------------------------------------------
run_stacks() {
    local dir="$STAGE_DIR/07_stacks"
    mkdir -p "$dir"
    local stacks=("frontend-stack" "media-stack" "proxy-stack")
    local DOCKER_DIR="${REAL_ROOT}/home/asvit/docker"
    for stack in "${stacks[@]}"; do
        local src="${DOCKER_DIR}/${stack}"
        local dst="${dir}/${stack}"
        mkdir -p "$dst"
        if [[ -d "$src" ]]; then
            find "$src" -maxdepth 3 > "${dst}/_directory_tree.txt" 2>&1
            find "$src" -maxdepth 2 -type f \( -iname "docker-compose*.yml" -o -iname "compose*.yaml" -o -iname ".env" -o -iname "*.conf" -o -iname "*.json" -o -iname "*.xml" \) | \
            while read -r f; do
                rel="${f#$src/}"
                outfile="${dst}/${rel//\//_}"
                mask_sensitive_file "$f" "$outfile"
            done
        else
            echo "N/A - stack directory not found: $src" > "${dst}/_missing.txt"
        fi
    done
}

# -----------------------------------------------------------------------------
# Module: media
# -----------------------------------------------------------------------------
run_media() {
    local dir="$STAGE_DIR/08_media"
    mkdir -p "$dir"
    local MEDIA_DIR="${REAL_ROOT}/home/asvit/docker/media-stack"
    if [[ -d "$MEDIA_DIR" ]]; then
        find "$MEDIA_DIR" -iname "config.xml" 2>/dev/null | while read -r f; do
            rel="${f#$MEDIA_DIR/}"
            outfile="${dir}/$(echo "$rel" | tr '/' '_')"
            mask_sensitive_file "$f" "$outfile"
        done
        find "$MEDIA_DIR" -iname "qBittorrent.conf" 2>/dev/null | while read -r f; do
            rel="${f#$MEDIA_DIR/}"
            outfile="${dir}/$(echo "$rel" | tr '/' '_')"
            mask_sensitive_file "$f" "$outfile"
        done
    else
        echo "N/A - media-stack directory not found" > "${dir}/_missing.txt"
    fi
}

# -----------------------------------------------------------------------------
# Module: users
# -----------------------------------------------------------------------------
run_users() {
    local dir="$STAGE_DIR/09_users"
    mkdir -p "$dir"
    [[ -f "${REAL_ROOT}/etc/passwd" ]] && run_cmd "passwd" "$dir/passwd.txt" cat "${REAL_ROOT}/etc/passwd"
    [[ -f "${REAL_ROOT}/etc/group" ]] && run_cmd "group" "$dir/group.txt" cat "${REAL_ROOT}/etc/group"
    echo "Shadow file not collected for security" > "$dir/shadow.txt"
    [[ -f "${REAL_ROOT}/etc/sudoers" ]] && run_cmd "sudoers" "$dir/sudoers.txt" cat "${REAL_ROOT}/etc/sudoers" 2>/dev/null
    run_cmd "groups" "$dir/groups_of_asvit.txt" groups asvit 2>/dev/null
    if has_cmd lastlog; then run_cmd "lastlog" "$dir/lastlog.txt" lastlog | head -20; fi
    if has_cmd who; then run_cmd "who" "$dir/who.txt" who -a; fi
    if has_cmd w; then run_cmd "w" "$dir/w.txt" w; fi
    if has_cmd last; then run_cmd "last" "$dir/last.txt" last -n 20; fi
}

# -----------------------------------------------------------------------------
# Module: kernel
# -----------------------------------------------------------------------------
run_kernel() {
    local dir="$STAGE_DIR/10_kernel"
    mkdir -p "$dir"
    if has_cmd sysctl; then
        run_cmd "sysctl_all" "$dir/sysctl.txt" sysctl -a 2>/dev/null
    fi
    [[ -f /proc/cpuinfo ]] && run_cmd "proc_cpuinfo" "$dir/cpuinfo.txt" cat /proc/cpuinfo
    [[ -f /proc/meminfo ]] && run_cmd "proc_meminfo" "$dir/meminfo.txt" cat /proc/meminfo
    [[ -f /proc/interrupts ]] && run_cmd "proc_interrupts" "$dir/interrupts.txt" cat /proc/interrupts
    [[ -f /proc/iomem ]] && run_cmd "proc_iomem" "$dir/iomem.txt" cat /proc/iomem
    [[ -f /proc/uptime ]] && run_cmd "proc_uptime" "$dir/uptime_proc.txt" cat /proc/uptime
    if [[ -d /proc/sys/fs ]]; then
        run_cmd "fs_limits" "$dir/fs_limits.txt" cat /proc/sys/fs/file-max 2>/dev/null
    fi
}

# -----------------------------------------------------------------------------
# Module: gpu
# -----------------------------------------------------------------------------
run_gpu() {
    local dir="$STAGE_DIR/11_gpu"
    mkdir -p "$dir"
    if has_cmd nvidia-smi; then
        run_cmd "nvidia_smi" "$dir/nvidia_smi.txt" nvidia-smi
        run_cmd "nvidia_top" "$dir/nvidia_top.txt" nvidia-smi dmon -c 1
    fi
    if has_cmd lspci; then
        run_cmd "gpu_lspci" "$dir/gpu_lspci.txt" lspci -nn | grep -E 'VGA|3D|Display' || echo "No GPU found via lspci"
    fi
    if [[ "$(uname)" == "Darwin" ]]; then
        run_cmd "gpu_sysctl" "$dir/gpu_sysctl.txt" sysctl hw.gpu 2>/dev/null || echo "No GPU info from sysctl"
    fi
}

# -----------------------------------------------------------------------------
# Dispatch selected modules
# -----------------------------------------------------------------------------
for module in "${SELECTED_TESTS[@]}"; do
    case "$module" in
        system)   run_system ;;
        storage)  run_storage ;;
        network)  run_network ;;
        samba)    run_samba ;;
        services) run_services ;;
        docker)   run_docker ;;
        stacks)   run_stacks ;;
        media)    run_media ;;
        users)    run_users ;;
        kernel)   run_kernel ;;
        gpu)      run_gpu ;;
        *) echo -e "${YELLOW}Unknown module: $module (ignored)${NC}" ;;
    esac
done

# -----------------------------------------------------------------------------
# Wait for background tasks
# -----------------------------------------------------------------------------
echo "Waiting for background tasks to finish..."
for pid in "${BG_PIDS[@]}"; do
    wait "$pid" 2>/dev/null
done

# -----------------------------------------------------------------------------
# Generate summary
# -----------------------------------------------------------------------------
SUMMARY_FILE="$STAGE_DIR/00_summary.txt"
{
    echo "=== SYSTEM SUMMARY ==="
    echo "Collection timestamp: $(date)"
    echo "Hostname: $(cat "${REAL_ROOT}/etc/hostname" 2>/dev/null || hostname 2>/dev/null || echo 'unknown')"
    echo "Kernel: $(uname -r 2>/dev/null || echo 'unknown')"
    echo "Architecture: $(uname -m 2>/dev/null || echo 'unknown')"
    echo "OS: $(cat "${REAL_ROOT}/etc/os-release" 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo 'unknown')"
    echo "CPU: $(lscpu 2>/dev/null | grep 'Model name' | head -1 | cut -d: -f2 | xargs || echo 'unknown')"
    echo "Cores: $(nproc 2>/dev/null || echo 'unknown')"
    echo "Memory: $(free -h 2>/dev/null | grep Mem | awk '{print $2}' || echo 'unknown')"
    echo "Disk usage: $(df -h / 2>/dev/null | tail -1 | awk '{print $3 " used, " $2 " total"}' || echo 'unknown')"
    echo ""
    echo "=== COLLECTED STATISTICS ==="
    echo "Number of containers: $(docker ps -a 2>/dev/null | wc -l | xargs)"
    echo "Number of volumes: $(docker volume ls 2>/dev/null | wc -l | xargs)"
    echo "Number of networks: $(docker network ls 2>/dev/null | wc -l | xargs)"
    echo "Total files collected: $(find "$STAGE_DIR" -type f 2>/dev/null | wc -l | xargs)"
} > "$SUMMARY_FILE"

# -----------------------------------------------------------------------------
# Finalize format
# -----------------------------------------------------------------------------
if [[ "$FORMAT" == "flat" ]]; then
    echo "Converting to flat JSON structure..."
    JSON_FILE="$REPORT_DIR/report.json"
    if has_cmd jq; then
        cd "$STAGE_DIR" || exit 1
        find . -type f -print0 | while IFS= read -r -d '' file; do
            key="${file#./}"
            content=$(jq -Rs . < "$file")
            echo "{\"$key\": $content}"
        done | jq -s 'add' > "$JSON_FILE"
        cd - >/dev/null || exit 1
        rm -rf "$STAGE_DIR"
    else
        echo -e "${YELLOW}WARNING: jq not found, keeping folder structure.${NC}"
        mv "$STAGE_DIR"/* "$REPORT_DIR"/ 2>/dev/null
        rmdir "$STAGE_DIR" 2>/dev/null
    fi
else
    mv "$STAGE_DIR"/* "$REPORT_DIR"/ 2>/dev/null
    rmdir "$STAGE_DIR" 2>/dev/null
fi

# -----------------------------------------------------------------------------
# Generate checksums and manifest
# -----------------------------------------------------------------------------
cd "$REPORT_DIR" || exit 1
if has_cmd sha256sum; then
    find . -type f ! -name "checksums.txt" ! -name "manifest.txt" -print0 | sort -z | while IFS= read -r -d '' file; do
        sha256sum "$file"
    done > checksums.txt
elif has_cmd shasum; then
    find . -type f ! -name "checksums.txt" ! -name "manifest.txt" -print0 | sort -z | while IFS= read -r -d '' file; do
        shasum -a 256 "$file"
    done > checksums.txt
else
    echo "No checksum tool found" > checksums.txt
fi

{
    echo "MANIFEST for diagnostic report"
    echo "Generated: $(date)"
    echo "Format: $FORMAT"
    echo "----------------------------------------"
    find . -type f ! -name "checksums.txt" ! -name "manifest.txt" -print0 | sort -z | while IFS= read -r -d '' file; do
        size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null || echo "?")
        mtime=$(stat -c %y "$file" 2>/dev/null || stat -f %Sm "$file" 2>/dev/null || echo "?")
        echo "$file | size: $size bytes | mtime: $mtime"
    done
} > manifest.txt

# -----------------------------------------------------------------------------
# Create archive
# -----------------------------------------------------------------------------
cd "$OUT_ROOT" || exit 1
ARCHIVE="${STAMP}-config.tar.gz"
tar -czf "$ARCHIVE" "${STAMP}-config" 2>/dev/null
if has_cmd sha256sum; then
    sha256sum "$ARCHIVE" > "${ARCHIVE}.sha256"
elif has_cmd shasum; then
    shasum -a 256 "$ARCHIVE" > "${ARCHIVE}.sha256"
else
    echo "No checksum tool" > "${ARCHIVE}.sha256"
fi

# -----------------------------------------------------------------------------
# Set ownership and permissions
# -----------------------------------------------------------------------------
CURRENT_USER=$(whoami)
CURRENT_GROUP=$(id -gn)
if [[ "$EUID" -eq 0 ]]; then
    chown -R "$CURRENT_USER:$CURRENT_GROUP" "$REPORT_DIR" "$ARCHIVE" "${ARCHIVE}.sha256" 2>/dev/null
fi
find "$REPORT_DIR" -type d -exec chmod 755 {} \; 2>/dev/null
find "$REPORT_DIR" -type f -exec chmod 644 {} \; 2>/dev/null
chmod 644 "$ARCHIVE" "${ARCHIVE}.sha256" 2>/dev/null

# -----------------------------------------------------------------------------
# Final output
# -----------------------------------------------------------------------------
echo -e "${GREEN}=== Collection finished: $(date) ===${NC}"
echo "Report directory: ${REPORT_DIR}"
echo "Archive: ${OUT_ROOT}/${ARCHIVE}"
echo "Archive checksum: ${OUT_ROOT}/${ARCHIVE}.sha256"
echo "Checksums and manifest inside the report."
echo "Summary: ${REPORT_DIR}/00_summary.txt"
echo -e "${GREEN}No data was modified on the host.${NC}"