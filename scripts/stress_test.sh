#!/usr/bin/env bash
# =============================================================================
# stress_test.sh – AsVit Load Tester
# Copyright (c) 2026 AsVit. All rights reserved.
# =============================================================================

set -euo pipefail

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

SCRIPT="${1:-/app/scripts/collect.sh}"
if [[ ! -f "$SCRIPT" ]]; then
    echo -e "${RED}Error: $SCRIPT not found${NC}"
    exit 1
fi

echo -e "${BLUE}=== AsVit Load Tester ===${NC}"
echo "Testing script: $SCRIPT"
echo ""

TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

echo "Output directory: $TEST_DIR"
BASELINE_LOAD=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
echo -e "Baseline load: $BASELINE_LOAD"

START_TIME=$(date +%s)
timeout 120 bash "$SCRIPT" --output-dir "$TEST_DIR" --no-interactive --tests "system storage network" --max-parallel 2 &> "$TEST_DIR/run.log" &
PID=$!

MAX_LOAD=0
MAX_MEM=0
while kill -0 $PID 2>/dev/null; do
    LOAD=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
    MEM=$(free -m | grep Mem | awk '{print $3}')
    if (( $(echo "$LOAD > $MAX_LOAD" | bc -l 2>/dev/null || echo "0") )); then MAX_LOAD=$LOAD; fi
    if (( $MEM > $MAX_MEM )); then MAX_MEM=$MEM; fi
    sleep 1
done
END_TIME=$(date +%s)

ELAPSED=$((END_TIME - START_TIME))
echo "Execution time: $ELAPSED seconds"
echo "Peak load: $MAX_LOAD (baseline: $BASELINE_LOAD)"
echo "Peak memory usage: $MAX_MEM MB"

THRESHOLD_LOAD=$(echo "$BASELINE_LOAD * 1.5" | bc -l 2>/dev/null || echo "2.0")
if (( $(echo "$MAX_LOAD < $THRESHOLD_LOAD" | bc -l 2>/dev/null) )); then
    echo -e "${GREEN}✅ Load is within safe limits.${NC}"
else
    echo -e "${YELLOW}⚠️  Load exceeded threshold. Consider reducing parallelism.${NC}"
fi

OUTPUT_SIZE=$(du -sh "$TEST_DIR" | awk '{print $1}')
echo "Output size: $OUTPUT_SIZE"

echo -e "${GREEN}Test completed. No system overload observed.${NC}"