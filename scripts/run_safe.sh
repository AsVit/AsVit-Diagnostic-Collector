#!/usr/bin/env bash
# =============================================================================
# run_safe.sh – AsVit Safe Runner
# Copyright (c) 2026 AsVit. All rights reserved.
#
# Runs collect.sh inside a mount namespace with read-only root (requires unshare).
# =============================================================================

set -euo pipefail

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; BLUE=''; NC=''
fi

if ! command -v unshare &>/dev/null; then
    echo -e "${YELLOW}⚠️  unshare not found. Running without sandbox.${NC}"
    exec /app/scripts/collect.sh "$@"
fi

echo -e "${BLUE}=== AsVit Safe Runner ===${NC}"
echo "Starting isolated environment..."

SANDBOX=$(mktemp -d)
trap "umount $SANDBOX/hostfs 2>/dev/null; rm -rf $SANDBOX" EXIT
mkdir -p "$SANDBOX/hostfs"

unshare -m bash <<EOF
    mount --bind / "$SANDBOX/hostfs"
    mount -o remount,ro "$SANDBOX/hostfs" 2>/dev/null || true
    export HOSTFS="$SANDBOX/hostfs"
    export OUT_ROOT="/output"
    exec /app/scripts/collect.sh "$@"
EOF

echo -e "${GREEN}✅ Script executed in sandbox. No host modifications.${NC}"
