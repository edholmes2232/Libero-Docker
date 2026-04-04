# Microchip Libero SoC Docker

Docker image containing Microchip's Libero SoC FPGA synthesis toolchain (Synplify, ModelSim, Designer, SmartHLS) for headless CI/CD and development use.

## Quick Start

`run_docker.sh` parses your license file, extracts the hostname/MAC, and starts the container automatically:

```bash
./run_docker.sh /path/to/your/Microchip/license.dat
```

## Licensing

Libero requires a FlexLM license. The license is locked to a specific MAC address (hostid), so the container must be started with a matching MAC.

> [!NOTE]
> The hostname in your license file should not be `localhost`.

The entrypoint supports three modes:

| Mode | How |
|------|-----|
| **Local license file** (default) | Mount at `/usr/local/microchip/license`. The entrypoint starts `lmgrd` automatically |
| **External license server** | Set `-e LM_LICENSE_FILE=1702@license-server.corp` |
| **No license** | Container starts with a warning; tools will fail on checkout |

### Manual Run

```bash
docker run -it --rm \
    --hostname <YOUR_SERVER_HOSTNAME> \
    --mac-address <YOUR_SERVER_MAC> \
    -v /path/to/your/license.dat:/usr/local/microchip/license \
    -v $(pwd):/workspace -w /workspace \
    libero:2025.2 bash
```

### snpslmd Docker Detection Workaround

The Synopsys license daemon (`snpslmd`) detects Docker via `/proc/1/cgroup` and refuses to run. This image includes an `LD_PRELOAD` shim ([snpslmd-workaround.c](snpslmd-workaround.c)) that intercepts filesystem calls to hide container indicators, allowing the daemon to start normally.

## Build from Source

You need the Libero offline installer (e.g. `Libero_SoC_2025.2_offline_lin.zip`) extracted into a directory:

```bash
docker build \
    --build-context libero-installer=$HOME/Downloads/Libero_SoC_2025.2_offline_lin \
    -t libero:2025.2 .
```

The build verifies the installer MD5 checksum automatically.

## Verification

```bash
./run_docker.sh /path/to/your/Microchip/license.dat
container# cd /usr/local/microchip/Libero_SoC_2025.2/Libero_SoC/Designer/scripts/sample/
container# libero script:run.tcl
```

## License

[MIT](LICENSE)
