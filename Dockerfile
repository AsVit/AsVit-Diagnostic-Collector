# =============================================================================
# AsVit Diagnostic Collector Docker Image
# Copyright (c) 2026 AsVit. All rights reserved.
# =============================================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bash \
    coreutils \
    util-linux \
    procps \
    dmidecode \
    smartmontools \
    iproute2 \
    net-tools \
    netplan.io \
    iptables \
    ufw \
    jq \
    curl \
    wget \
    btrfs-progs \
    nvme-cli \
    pciutils \
    usbutils \
    sudo \
    systemd \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY scripts/ ./scripts/

RUN chmod +x ./scripts/*.sh

ENV HOSTFS=/hostfs
ENV OUT_ROOT=/output

# Directly run collect.sh, no entrypoint needed
CMD ["/app/scripts/collect.sh"]