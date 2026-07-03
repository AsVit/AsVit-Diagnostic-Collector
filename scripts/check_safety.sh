#!/usr/bin/env bash
# =============================================================================
# check_safety.sh – AsVit Safety Validator
# Copyright (c) 2026 AsVit. All rights reserved.
#
# Scans collect.sh for potentially dangerous commands.
# =============================================================================

set -euo pipefail

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; BLUE=''; NC=''
fi

SCRIPT="${1:-/app/scripts/collect.sh}"
if [[ ! -f "$SCRIPT" ]]; then
    echo -e "${RED}Error: $SCRIPT not found${NC}"
    exit 1
fi

echo -e "${BLUE}=== AsVit Safety Validator ===${NC}"
echo "Analyzing: $SCRIPT"
echo ""

DANGEROUS_CMDS=(
    "rm -rf" "rm -r" "rm -f" "dd if=" "mkfs" "mkswap" "fdisk" "parted"
    "docker rm" "docker rmi" "docker stop" "docker kill" "docker system prune" "docker volume prune"
    "systemctl stop" "systemctl disable" "systemctl mask" "kill -9" "pkill" "killall"
    "curl.*http" "wget.*http" "nc -l" "telnet" "ssh -L" "ssh -R"
    "chmod 777" "chown -R" "chattr -i" "mount -o remount,rw"
    ":(){ :|:& };:"
    "eval" "exec" "source /dev/" "\. /dev/"
)

found=0
for pattern in "${DANGEROUS_CMDS[@]}"; do
    if grep -E -i "$pattern" "$SCRIPT" >/dev/null 2>&1; then
        echo -e "${RED}⚠️  Found dangerous pattern: $pattern${NC}"
        grep -E -i -n "$pattern" "$SCRIPT" | head -3
        found=$((found+1))
    fi
done

WRITE_PATHS=$(grep -E '\> (cp|mv|dd|tee|cat) .*\/' "$SCRIPT" | grep -v -E '( /output/| /hostfs| \.\.\.)' | wc -l)
if [[ $WRITE_PATHS -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Potential writes to host paths (outside /output and /hostfs):${NC}"
    grep -E -n '\> (cp|mv|dd|tee|cat) .*\/' "$SCRIPT" | grep -v -E '( /output/| /hostfs| \.\.\.)' | head -5
    found=$((found+1))
fi

if grep -q "/hostfs" "$SCRIPT"; then
    echo -e "${GREEN}✅ Script uses /hostfs for host access (safe)${NC}"
else
    echo -e "${YELLOW}⚠️  Script does not use /hostfs – may access host directly${NC}"
fi

if grep -q "mask_sensitive_file" "$SCRIPT"; then
    echo -e "${GREEN}✅ Secret masking is present${NC}"
else
    echo -e "${RED}❌ No secret masking found${NC}"
    found=$((found+1))
fi

if [[ $found -eq 0 ]]; then
    echo -e "\n${GREEN}✅✅✅ Script appears SAFE. No dangerous commands detected.${NC}"
    exit 0
else
    echo -e "\n${RED}❌ Found $found potential safety issues. Review the lines above.${NC}"
    exit 1
fi
