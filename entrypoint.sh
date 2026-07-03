#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh – AsVit Diagnostic Container Entrypoint
# Copyright (c) 2026 AsVit. All rights reserved.
# =============================================================================

set -e

export HOSTFS="/hostfs"
export OUT_ROOT="/output"

# If no arguments, run collect.sh (interactive mode)
if [[ $# -eq 0 ]]; then
    exec /app/scripts/collect.sh
else
    # If first argument is a script path (like /app/scripts/check_safety.sh)
    if [[ -f "$1" ]]; then
        exec "$@"
    else
        # Otherwise pass all arguments to collect.sh
        exec /app/scripts/collect.sh "$@"
    fi
fi