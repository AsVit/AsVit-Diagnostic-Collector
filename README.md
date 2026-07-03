# AsVit Diagnostic Collector

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Ready-blue.svg)](https://www.docker.com/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20|%20macOS%20|%20FreeBSD%20|%20Windows%20(via%20Docker)-green.svg)]()

**One command. Five minutes. Complete server insight – without installing anything.**

---

## The Problem

When a server misbehaves, you need answers fast. But traditional troubleshooting is painful:

- You run dozens of commands (`lscpu`, `df -h`, `netstat`, `docker ps`, …) and pipe output to files.
- You risk exposing passwords, tokens, and API keys when sharing logs.
- Each server has a different set of tools – some have `dmidecode`, others don't.
- It takes hours to piece together the full picture.

---

## The Solution

**AsVit Diagnostic Collector** solves this by providing a single, containerized, read‑only tool that collects everything in minutes:

- **Complete picture** – hardware, disks, network, services, Docker, kernel, GPU, and more.
- **Privacy‑first** – all secrets are automatically masked (`***MASKED***`); `/etc/shadow` is never touched.
- **Zero dependencies** – runs inside Docker; no need to install any packages on the host.
- **Portable** – works on Linux, macOS, FreeBSD, and Windows (via Docker).
- **Parallel collection** – speed with built‑in throttling to avoid overload.
- **Flexible output** – choose between a structured folder or a single JSON for automation/AI.

---

## Key Features

- **11 modular tests** – pick only what you need (system, storage, network, samba, services, docker, stacks, media, users, kernel, gpu).
- **Interactive wizard** – guides you through format and module selection.
- **Read‑only operation** – host root is mounted as `:ro`; absolutely no modifications.
- **Automatic secret masking** – passwords, tokens, keys are replaced with `***MASKED***`.
- **Integrity verification** – SHA‑256 checksums and a manifest file for every report.
- **Safety validators** – included scripts to check for dangerous commands, privacy leaks, and system load.
- **Docker‑aware** – inspects containers, networks, volumes, and compose stacks.

---

## What Makes It Different?

| Feature | AsVit Diagnostic Collector | Other tools (sosreport, sysinfo, etc.) |
|---------|----------------------------|----------------------------------------|
| **No installation** | ✅ (100% Docker) | ❌ (requires packages) |
| **Automatic secret masking** | ✅ | ❌ (manual filtering) |
| **Cross‑platform** | ✅ (Linux, macOS, FreeBSD, Windows) | ❌ (Linux‑only) |
| **Modular tests** | ✅ (choose what to collect) | ❌ (all or nothing) |
| **Parallel collection** | ✅ (throttled) | ❌ (sequential) |
| **JSON output** | ✅ (for AI/automation) | ❌ (text only) |
| **Interactive wizard** | ✅ | ❌ (CLI only) |
| **Integrity checks** | ✅ (SHA‑256 + manifest) | ❌ (none) |
| **Safety validators** | ✅ (check_safety, check_privacy, stress_test) | ❌ (none) |

---

## Safety First

We take security seriously:

- **Read‑only mounts** – the host is mounted with `:ro`; nothing is ever written.
- **Dangerous command scanner** – `check_safety.sh` looks for `rm`, `dd`, `mkfs`, `docker prune`, etc.
- **Privacy checker** – `check_privacy.sh` ensures no personal data (e.g., SSH keys, cloud credentials) is exposed.
- **Load tester** – `stress_test.sh` verifies the collector doesn't overload your server.
- **Open source** – all code is auditable; MIT licensed.

---

## Quick Start

```bash
# Clone the repository
git clone https://github.com/AsVit/AsVit-Diagnostic-Collector.git
cd AsVit-Diagnostic-Collector

# Make the launcher executable
chmod +x StartDiag.sh

# Run the interactive wizard (builds the container, runs diagnostics)
./StartDiag.sh
```

Alternatively, run directly with Docker:

```bash
docker run -it --rm \
  -v /:/hostfs:ro \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd)/output:/output \
  --device /dev --network host --ipc host \
  asvit-diagnostic:latest
```

---

## Platform Support

| Platform | Native (no Docker) | Docker Container | Coverage |
|----------|---------------------|------------------|----------|
| **Linux** | ✅ Yes | ✅ Yes | **Full** – all modules |
| **macOS** | ✅ Partial | ✅ Yes | **Limited** – no hardware details, no SMART, no systemd |
| **FreeBSD** | ✅ Partial | ✅ Yes | **Limited** – similar to macOS, no Docker inside container |
| **Windows** | ❌ No | ✅ Yes (Docker Desktop) | **Limited** – only what Docker can access |

> For full diagnostics, **Linux** is strongly recommended. On other platforms, unsupported commands are skipped gracefully, and the report contains only available data.

---

## Available Modules

| Module | Description |
|--------|-------------|
| `system` | OS, kernel, CPU, RAM, hardware (dmidecode, lspci, lsusb) |
| `storage` | Disks, partitions, filesystems (BTRFS), SMART, I/O schedulers |
| `network` | Interfaces, routes, firewall, active connections, netplan |
| `samba` | SMB configuration, WSDD status and logs |
| `services` | Running systemd services, processes, cron, journal logs |
| `docker` | Engine info, containers, networks, volumes, system usage |
| `stacks` | Compose files and `.env` (secrets masked) |
| `media` | *arr `config.xml` and qBittorrent.conf (secrets masked) |
| `users` | User/group lists, sudoers, lastlog, who (shadow omitted) |
| `kernel` | sysctl, `/proc/cpuinfo`, meminfo, interrupts |
| `gpu` | NVIDIA (nvidia-smi) and other GPUs via lspci |

---

## Output Structure

Each run produces a timestamped directory (or a single `report.json`) inside `./output/`, plus a `.tar.gz` archive:

```
m.15.2025_14-30-config/
├── 01_system/          # OS, CPU, RAM, hardware details
├── 02_storage/         # Disks, SMART, BTRFS, partitions
├── 03_network/         # Interfaces, firewall, routes, connections
├── 04_samba/           # SMB configuration and status
├── 05_services/        # Running services, processes, logs
├── 06_docker/          # Containers, networks, volumes (full inspect)
├── 07_stacks/          # Compose files and .env (masked)
├── 08_media/           # *arr configs, qBittorrent (masked)
├── 09_users/           # Users, groups, sudo, lastlog
├── 10_kernel/          # sysctl, /proc details
├── 11_gpu/             # NVIDIA and other GPUs
├── 00_summary.txt      # Quick overview
├── checksums.txt       # SHA‑256 for all files
└── manifest.txt        # File list with sizes and timestamps
```

---

## Trust, but Verify

We encourage you to:

1. **Inspect the code** – every script is open and commented.
2. **Run safety checks first** – use `./scripts/check_safety.sh collect.sh` to see what commands are used.
3. **Test in a non‑production environment** – ensure it works as expected for your OS.
4. **Review the output** – confirm that secrets are correctly masked.

---

## License

MIT License – see [LICENSE](LICENSE) for details.

---

**Get clarity. Diagnose with confidence.**
