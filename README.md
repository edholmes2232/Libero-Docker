# Libero Docker

Docker container for Microchip Libero SoC + SoftConsole on Ubuntu 22.04.

## Quick Start (Pull Pre-Built Image)

For CI/CD and devcontainers — just pull, no build needed:

```bash
docker pull ghcr.io/edholmes2232/libero-docker:latest
docker run -it --rm ghcr.io/edholmes2232/libero-docker:latest
```

## Building From Scratch

Only needed when Libero releases a new version.

### Prerequisites

1. Extract your **Libero offline installer** `.zip` somewhere (e.g. `~/Downloads/Libero_SoC_2025.2_offline_lin/`)
2. Place the **SoftConsole** `.run` file in its own folder (e.g. `~/Downloads/SoftConsole/`)
3. Drop your **licence file** into `installer/license` in this repo

### Build

```bash
docker build \
    --build-context libero-installer=~/Downloads/Libero_SoC_2025.2_offline_lin \
    --build-context softconsole-installer=~/Downloads/SoftConsole \
    -t libero .
```

Or use Docker Compose (reads paths from `.env`):

```bash
docker compose build
```

> ⚠️ Requires ~60GB temp disk space. Takes ~30 minutes.

### Push to Registry

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u edholmes2232 --password-stdin
docker tag libero:latest ghcr.io/edholmes2232/libero-docker:latest
docker push ghcr.io/edholmes2232/libero-docker:latest
```

### Clean Up Build Cache

```bash
docker builder prune -a
```

## VS Code Dev Container

Open this project in VS Code → **"Reopen in Container"**. Pulls the pre-built image automatically.

## Container Layout

| Path | Purpose |
|---|---|
| `/usr/local/microchip/license/` | Licence file |
| `/usr/local/microchip/Libero_SoC_2025.2/` | Libero SoC |
| `/usr/local/microchip/SoftConsole-v2022.2-RISC-V-747/` | SoftConsole |
| `/usr/local/bin/entrypoint.sh` | Sets PATH, starts license daemon |

## Environment

The entrypoint automatically configures:
- `PATH` for Libero, Synplify, ModelSim, and SoftConsole RISC-V toolchain
- `LM_LICENSE_FILE` and `SNPSLMD_LICENSE_FILE` for licensing
- Starts `lmgrd` license daemon in background on port 1702
