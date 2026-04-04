#!/bin/bash
set -e

echo "[entrypoint] Initializing Microchip Libero SoC Synthesis Environment..."

# =============================================================================
# Installation paths
# =============================================================================
export LIBERO_INSTALL_DIR=/usr/local/microchip/Libero_SoC_2025.2
export LICENSE_DAEMON_DIR=$LIBERO_INSTALL_DIR/LicenseDaemons
export LICENSE_FILE=/usr/local/microchip/license

# =============================================================================
# Libero
# =============================================================================
export FPGENPROG=$LIBERO_INSTALL_DIR/Libero_SoC/Designer/bin64/fpgenprog
export PATH=$PATH:$LIBERO_INSTALL_DIR/Libero_SoC/Designer/bin:$LIBERO_INSTALL_DIR/Libero_SoC/Designer/bin64
export PATH=$PATH:$LIBERO_INSTALL_DIR/Libero_SoC/Synplify_Pro/bin
export PATH=$PATH:$LIBERO_INSTALL_DIR/Libero_SoC/ModelSim_Pro/linuxacoem
export LOCALE=C
export LD_LIBRARY_PATH=/usr/lib/i386-linux-gnu:${LD_LIBRARY_PATH:-}

# =============================================================================
# License Check & Setup
#
# Three modes:
#   1. Local license file mounted at /usr/local/microchip/license
#      - Parse the SERVER line, start lmgrd locally
#   2. User pre-set LM_LICENSE_FILE env var (e.g. 1702@license-server.corp)
#      - Use their external server, skip local daemon
#   3. Neither provided
#      - Warn and continue (tools will fail on license checkout)
# =============================================================================

# Shared setup: temp dirs, cgroup spoof, flexlm user
if ! id "flexlm" &>/dev/null; then
    useradd -r -s /bin/false flexlm
fi

# Ensure temp directories and logs are writable by the flexlm user
if [ ! -d "/usr/tmp" ]; then
    ln -s /tmp /usr/tmp
fi
mkdir -p /tmp/.flexlm /var/log/microchip /var/tmp
chmod 1777 /tmp/.flexlm /var/tmp /tmp
chown -R flexlm:flexlm /var/log/microchip
touch /var/log/microchip/lmgrd.log
chown flexlm:flexlm /var/log/microchip/lmgrd.log

# Generate a pristine, legitimate-looking cgroup file to spoof Docker detection
echo "0::/user.slice/user-1000.slice/session-2.scope" > /usr/tmp/fake_cgroup
chmod 644 /usr/tmp/fake_cgroup

if [ -f "$LICENSE_FILE" ]; then
    # -- Mode 1: Local license file provided --
    # Parse "SERVER <hostname> <hostid> <port>" from the first SERVER line
    LICENSE_HOST=$(awk '/^SERVER/{print $2; exit}' "$LICENSE_FILE")
    LICENSE_PORT=$(awk '/^SERVER/{print $4; exit}' "$LICENSE_FILE")
    LICENSE_HOST=${LICENSE_HOST:-localhost}
    LICENSE_PORT=${LICENSE_PORT:-1702}

    export LM_LICENSE_FILE="${LICENSE_PORT}@${LICENSE_HOST}"
    export SNPSLMD_LICENSE_FILE="${LICENSE_PORT}@${LICENSE_HOST}"
    echo "[entrypoint] Parsed license: ${LM_LICENSE_FILE} (from mounted license file)"

    # -- MAC address validation --
    # FlexLM locks the license to a specific MAC (hostid). Parse it from the
    # SERVER line (field 3, e.g. "a1b2c3d4e5f6") and verify a matching
    # interface exists in this container.
    LICENSE_MAC_RAW=$(awk '/^SERVER/{print tolower($3); exit}' "$LICENSE_FILE")
    if [ -n "$LICENSE_MAC_RAW" ]; then
        # Format raw "e897447848b1" → "e8:97:44:78:48:b1"
        LICENSE_MAC=$(echo "$LICENSE_MAC_RAW" | sed 's/\(..\)/\1:/g; s/:$//')
        # Grab all MACs from container interfaces
        CONTAINER_MACS=$(cat /sys/class/net/*/address 2>/dev/null | tr '[:upper:]' '[:lower:]')

        if ! echo "$CONTAINER_MACS" | grep -qF "$LICENSE_MAC"; then
            echo "==========================================================================="
            echo " ERROR: MAC address mismatch"
            echo "==========================================================================="
            echo " License expects hostid: $LICENSE_MAC_RAW ($LICENSE_MAC)"
            echo " Container interfaces:   $(echo $CONTAINER_MACS | tr '\n' ' ')"
            echo ""
            echo " Fix: spoof the MAC when starting the container:"
            echo "   docker run --mac-address $LICENSE_MAC ..."
            echo "==========================================================================="
            exit 1
        fi
        echo "[entrypoint] MAC address verified: $LICENSE_MAC"
    fi

    echo "[entrypoint] Starting FlexNet license daemon (lmgrd)..."
    su -s /bin/bash flexlm -c "$LICENSE_DAEMON_DIR/lmgrd -c $LICENSE_FILE -l /var/log/microchip/lmgrd.log" &
    sleep 2
    echo "[entrypoint] License daemon started. Log: /var/log/microchip/lmgrd.log"

elif [ -n "${LM_LICENSE_FILE:-}" ]; then
    # -- Mode 2: User provided LM_LICENSE_FILE via env var --
    export SNPSLMD_LICENSE_FILE="$LM_LICENSE_FILE"
    echo "[entrypoint] Using external license server: $LM_LICENSE_FILE"
    echo "[entrypoint] Skipping local lmgrd daemon startup."

else
    # -- Mode 3: No license at all --
    echo "==========================================================================="
    echo " WARNING: No license configured"
    echo "==========================================================================="
    echo " Option A: Mount a license file:"
    echo "   docker run -v /path/to/license.dat:/usr/local/microchip/license ..."
    echo " "
    echo " Option B: Point to an external license server:"
    echo "   docker run -e LM_LICENSE_FILE=1702@license-server.corp ..."
    echo "==========================================================================="
fi

# Hand off 
exec "$@"
