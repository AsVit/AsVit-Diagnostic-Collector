#!/usr/bin/env bash
# =============================================================================
# StartDiag.sh – AsVit Diagnostic Interactive Launcher v1.0
# Copyright (c) 2026 AsVit. All rights reserved.
# =============================================================================

set -euo pipefail

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

IMAGE_NAME="asvit-diagnostic:latest"

# -----------------------------------------------------------------------------
# Prerequisites check
# -----------------------------------------------------------------------------
check_prereqs() {
    local missing=()
    if ! command -v docker &>/dev/null; then
        missing+=("docker")
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required tools: ${missing[*]}${NC}"
        echo "Please install Docker first."
        exit 1
    fi
    echo -e "${GREEN}✅ All prerequisites satisfied.${NC}"
}

# -----------------------------------------------------------------------------
# Check if image exists
# -----------------------------------------------------------------------------
image_exists() {
    docker image inspect "$IMAGE_NAME" &>/dev/null
}

# -----------------------------------------------------------------------------
# Menu
# -----------------------------------------------------------------------------
show_menu() {
    echo ""
    echo -e "${BLUE}=== AsVit Diagnostic Launcher ===${NC}"
    echo "1) Build Docker image"
    echo "2) Run interactive diagnostic wizard (inside container)"
    echo "3) Run diagnostics with custom parameters"
    echo "4) Run safety check on the main script"
    echo "5) Run privacy check on the main script"
    echo "6) Run stress test"
    echo "7) Clean up (remove image and containers)"
    echo "8) Exit"
    echo ""
    read -rp "Select option [1-8]: " choice
    case "$choice" in
        1) build_image ;;
        2) run_interactive ;;
        3) run_custom ;;
        4) run_safety_check ;;
        5) run_privacy_check ;;
        6) run_stress_test ;;
        7) clean_up ;;
        8) echo "Goodbye!"; exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}"; show_menu ;;
    esac
}

# -----------------------------------------------------------------------------
# Actions
# -----------------------------------------------------------------------------
build_image() {
    echo -e "${BLUE}Building Docker image...${NC}"
    docker build -t "$IMAGE_NAME" .
    echo -e "${GREEN}✅ Image built successfully.${NC}"
    show_menu
}

run_interactive() {
    if ! image_exists; then
        echo -e "${RED}Image not found. Please build it first (option 1).${NC}"
        show_menu
        return
    fi
    echo -e "${BLUE}Starting interactive diagnostic wizard...${NC}"
    docker run -it --rm \
        -v /:/hostfs:ro \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$(pwd)/output:/output" \
        --network host \
        --ipc host \
        "$IMAGE_NAME"
    show_menu
}

run_custom() {
    if ! image_exists; then
        echo -e "${RED}Image not found. Please build it first (option 1).${NC}"
        show_menu
        return
    fi
    echo -e "${BLUE}Custom diagnostic run${NC}"
    echo "Available modules: system storage network samba services docker stacks media users kernel gpu"
    read -rp "Enter modules (space-separated, default: all): " modules
    read -rp "Output format (folder/flat, default: folder): " format
    read -rp "Mask serial numbers? (y/n, default: n): " mask_serials

    local args=""
    if [[ -n "$modules" ]]; then
        args="$args --tests \"$modules\""
    fi
    if [[ -n "$format" ]]; then
        args="$args --format $format"
    fi
    if [[ "$mask_serials" == "y" || "$mask_serials" == "Y" ]]; then
        args="$args --mask-serials"
    fi

    docker run -it --rm \
        -v /:/hostfs:ro \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$(pwd)/output:/output" \
        --network host \
        --ipc host \
        "$IMAGE_NAME" /app/scripts/collect.sh $args
    show_menu
}

run_safety_check() {
    if ! image_exists; then
        echo -e "${RED}Image not found. Please build it first (option 1).${NC}"
        show_menu
        return
    fi
    echo -e "${BLUE}Running safety check...${NC}"
    docker run --rm \
        -v /:/hostfs:ro \
        -v "$(pwd)/output:/output" \
        "$IMAGE_NAME" /app/scripts/check_safety.sh /app/scripts/collect.sh
    show_menu
}

run_privacy_check() {
    if ! image_exists; then
        echo -e "${RED}Image not found. Please build it first (option 1).${NC}"
        show_menu
        return
    fi
    echo -e "${BLUE}Running privacy check...${NC}"
    docker run --rm \
        -v /:/hostfs:ro \
        -v "$(pwd)/output:/output" \
        "$IMAGE_NAME" /app/scripts/check_privacy.sh /app/scripts/collect.sh
    show_menu
}

run_stress_test() {
    if ! image_exists; then
        echo -e "${RED}Image not found. Please build it first (option 1).${NC}"
        show_menu
        return
    fi
    echo -e "${BLUE}Running stress test (this may take a few minutes)...${NC}"
    docker run --rm \
        -v /:/hostfs:ro \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$(pwd)/output:/output" \
        "$IMAGE_NAME" /app/scripts/stress_test.sh /app/scripts/collect.sh
    show_menu
}

clean_up() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    docker rm -f asvit-diagnostic 2>/dev/null || true
    docker rmi "$IMAGE_NAME" 2>/dev/null || true
    echo -e "${GREEN}Cleanup complete.${NC}"
    show_menu
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
echo -e "${BLUE}Welcome to AsVit Diagnostic Collector v1.0${NC}"
check_prereqs
mkdir -p output
show_menu