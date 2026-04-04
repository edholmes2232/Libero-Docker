# Microchip Libero SoC Docker

Docker image containing Microchip's Libero SoC FPGA synthesis toolchain (Synplify, ModelSim, Designer, SmartHLS) for headless CI/CD and development use.

## Build

You need the Libero offline installer (e.g. `Libero_SoC_2025.2_offline_lin.zip`) extracted into a directory:

```bash
docker build \
    --build-context libero-installer=$HOME/Downloads/Libero_SoC_2025.2_offline_lin \
    -t libero:2025.2 .
```

The build verifies the installer MD5 checksum automatically.

## Running & Licensing

Libero requires a FlexLM license. The license is locked to a specific MAC address (hostid), so the container must be started with a matching MAC.

**NOTE: Hostname of licence should not be `localhost` **

### Quick Start (recommended)

`run_docker.sh` parses your license file and sets the hostname/MAC automatically:

```bash
./run_docker.sh /path/to/your/Microchip/license.dat
```

### Manual

```bash
docker run -it --rm \
    --hostname <YOUR_SERVER_HOSTNAME> \
    --mac-address <YOUR_SERVER_MAC> \
    -v /path/to/your/license.dat:/usr/local/microchip/license \
    -v $(pwd):/workspace -w /workspace \
    libero:2025.2 bash
```

The entrypoint automatically starts the FlexLM license daemon (`lmgrd`) and configures the environment. It also supports pointing to an external license server via `LM_LICENSE_FILE`:

```bash
docker run -it --rm \
    -e LM_LICENSE_FILE=1702@license-server.corp \
    -v $(pwd):/workspace -w /workspace \
    libero:2025.2 bash
```

### snpslmd Docker Detection Workaround

The Synopsys license daemon (`snpslmd`) detects Docker via `/proc/1/cgroup` and refuses to run. This image includes an `LD_PRELOAD` shim ([snpslmd-workaround.c](snpslmd-workaround.c)) that intercepts filesystem calls to hide container indicators, allowing the daemon to start normally.

## Verification

```bash
./run_docker.sh /path/to/your/Microchip/license.dat
container# cd /usr/local/microchip/Libero_SoC_2025.2/Libero_SoC/Designer/scripts/sample/
container# libero script:run.tcl
```

## License

[MIT](LICENSE)
