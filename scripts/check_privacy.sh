#!/usr/bin/env bash
# =============================================================================
# check_privacy.sh – AsVit Privacy Checker
# Copyright (c) 2026 AsVit. All rights reserved.
#
# Checks if collect.sh collects personal/sensitive data.
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

echo -e "${BLUE}=== AsVit Privacy Checker ===${NC}"
echo "Analyzing: $SCRIPT"
echo ""

SENSITIVE_FILES=(
    "/etc/shadow"
    "/etc/passwd"
    "/etc/sudoers"
    "/etc/ssh/ssh_host_*"
    "~/.ssh/id_*"
    "~/.gnupg/*.gpg"
    "~/.aws/credentials"
    "~/.config/gcloud/credentials.db"
    "~/.docker/config.json"
    "~/.bash_history"
    "~/.zsh_history"
    "~/.mysql_history"
    "~/.psql_history"
    "~/.npmrc"
    "~/.gitconfig"
)

collected=()
masked=()
for f in "${SENSITIVE_FILES[@]}"; do
    if grep -q "$f" "$SCRIPT"; then
        collected+=("$f")
        if grep -q -E "mask_sensitive_file|echo.*not collected|shadow.txt" "$SCRIPT"; then
            masked+=("$f")
        fi
    fi
done

if [[ ${#collected[@]} -eq 0 ]]; then
    echo -e "${GREEN}✅ No known sensitive files are collected directly.${NC}"
else
    echo -e "${YELLOW}⚠️  The script references these sensitive files:${NC}"
    for f in "${collected[@]}"; do
        if [[ " ${masked[*]} " =~ " $f " ]]; then
            echo -e "  ${GREEN}✅ $f (properly masked/excluded)${NC}"
        else
            echo -e "  ${RED}❌ $f (may be exposed!)${NC}"
        fi
    done
fi

ENV_PATTERNS=("PASSWORD" "TOKEN" "SECRET" "API_KEY" "KEY" "PASS" "AWS_SECRET" "PRIVATE")
unmasked=0
for pat in "${ENV_PATTERNS[@]}"; do
    if grep -q -E "$pat.*=.*[^MASKED]" "$SCRIPT"; then
        echo -e "${RED}❌ Potential unmasked $pat found in script${NC}"
        unmasked=$((unmasked+1))
    fi
done

if grep -q -E "(curl|wget|nc|telnet).*(http|://| -)" "$SCRIPT"; then
    echo -e "${YELLOW}⚠️  Script may upload data externally. Check lines:${NC}"
    grep -n -E "(curl|wget|nc|telnet).*(http|://| -)" "$SCRIPT" | head -3
fi

if [[ ${#collected[@]} -eq 0 ]] && [[ $unmasked -eq 0 ]]; then
    echo -e "\n${GREEN}✅✅✅ Privacy check passed. No personal data exposed.${NC}"
    exit 0
else
    echo -e "\n${YELLOW}⚠️  Privacy recommendations:${NC}"
    echo "   - Ensure all collected files are masked or excluded."
    echo "   - Use mask_sensitive_file() for any copied config files."
    echo "   - Avoid uploading data externally."
    exit 1
fi
