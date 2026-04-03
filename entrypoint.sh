#!/bin/bash
set -e

# =============================================================================
# Installation paths
# =============================================================================
export SC_INSTALL_DIR=/usr/local/microchip/SoftConsole-v2022.2-RISC-V-747
export LIBERO_INSTALL_DIR=/usr/local/microchip/Libero_SoC_2025.2
export LICENSE_DAEMON_DIR=$LIBERO_INSTALL_DIR/Libero/bin64
export LICENSE_FILE=/usr/local/microchip/license/license

# =============================================================================
# SoftConsole
# =============================================================================
export PATH=$PATH:$SC_INSTALL_DIR/riscv-unknown-elf-gcc/bin
export FPGENPROG=$LIBERO_INSTALL_DIR/Libero/bin64/fpgenprog

# =============================================================================
# Libero
# =============================================================================
export PATH=$PATH:$LIBERO_INSTALL_DIR/Libero/bin:$LIBERO_INSTALL_DIR/Libero/bin64
export PATH=$PATH:$LIBERO_INSTALL_DIR/Synplify/bin
export PATH=$PATH:$LIBERO_INSTALL_DIR/Model/modeltech/linuxacoem
export LOCALE=C
export LD_LIBRARY_PATH=/usr/lib/i386-linux-gnu:${LD_LIBRARY_PATH:-}

# =============================================================================
# License
# =============================================================================
export LM_LICENSE_FILE=1702@localhost
export SNPSLMD_LICENSE_FILE=1702@localhost

# Start license daemon in background
if [ -f "$LICENSE_FILE" ]; then
    echo "[entrypoint] Starting license daemon..."
    $LICENSE_DAEMON_DIR/lmgrd \
        -c "$LICENSE_FILE" \
        -l /var/log/lmgrd.log &
    sleep 2
    echo "[entrypoint] License daemon started (log: /var/log/lmgrd.log)"
else
    echo "[entrypoint] WARNING: No license file at $LICENSE_FILE — daemon not started."
fi

# Hand off to user's command (bash, libero_soc, CI script, etc.)
exec "$@"
