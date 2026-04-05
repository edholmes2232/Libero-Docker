FROM ubuntu:22.04

# Stop apt from prompting for timezone etc
ENV DEBIAN_FRONTEND=noninteractive

# Extract Libero version info from installer name, e.g. "Libero_SoC_2025.2_offline_lin.sh"
ARG LIBERO_SH=Libero_SoC_2025.2_offline_lin.sh
ARG LIBERO_MD5=4ae7ad607a9d2f08e75ed3fd27d623e8

# Install Libero prerequisites 
RUN apt-get update -yqq && apt-get install -yqq --no-install-recommends \
    # Core tools
    unzip ksh xdg-utils \
    # X11 / XCB
    libxcb1 libxcb-cursor0 libxcb-icccm4 libxcb-keysyms1 \
    libxcb-shape0 libxcb-shm0-dev libxcb-xinerama0 libxcb-xinput0 \
    # X11 libs
    libxcomposite-dev libxcursor-dev libxdamage-dev libxfixes-dev \
    libxft-dev libxi-dev libxinerama-dev libxkbcommon-dev libxkbcommon-x11-0 \
    libxrandr-dev libxrender-dev libxslt1.1 libxss-dev libxtst-dev \
    # EGL / GL / Mesa
    libegl1 libegl-dev libegl-mesa0 libegl1-mesa libegl1-mesa-dev \
    libepoxy-dev libgl1 libgl1-mesa-glx libgles-dev libgles1 \
    libglvnd-core-dev libglvnd-dev libglx-mesa0 libopengl-dev libvulkan1 \
    # GTK / Cairo / Pango
    libgtk2.0-0 libgtk-3-dev libcairo2-dev libpango1.0-dev \
    libgdk-pixbuf-2.0-dev libgdk-pixbuf-xlib-2.0-0 \
    libgdk-pixbuf-xlib-2.0-dev libgdk-pixbuf2.0-dev \
    libatk-bridge2.0-dev libatk1.0-dev libatspi2.0-dev \
    libcanberra-gtk-module libcanberra-gtk3-module \
    # Font / Text
    libfreetype-dev libfreetype6-dev libfontconfig-dev libfontconfig1-dev \
    libharfbuzz-dev libharfbuzz-gobject0 libfribidi-dev \
    libdatrie-dev libgraphite2-dev libthai-dev libpixman-1-dev \
    # Image
    libpng-dev libjpeg-dev libjbig-dev libdeflate-dev libbrotli-dev \
    # Audio (Libero installer deps)
    libasyncns0 libflac8 libpulse0 libpulse-mainloop-glib0 \
    libsndfile1 libvorbisenc2 \
    # Crypto / SSL / Network
    libssl-dev libssl3 libgnutls30 libgcrypt20 libgpg-error0 \
    libgssapi-krb5-2 libk5crypto3 libkrb5-3 libkrb5support0 \
    libkeyutils1 libidn2-0 libnettle8 libhogweed6 libtasn1-6 \
    libp11-kit0 libgmp10 libnsl2 libnss-mdns libnss-myhostname \
    # System libs
    libpcre3 libpcre2-8-0 liblz4-1 liblzma5 libzstd1 libxxhash0 \
    libseccomp2 libsecret-1-0 libdbus-1-dev libgstreamer-plugins-base1.0-0 \
    libicu-dev libtool libncurses-dev libncurses6 libncursesw6 \
    libice-dev libsm-dev libvte-2.91-common libvte-common \
    # Compilers for LD_PRELOAD hack
    build-essential gcc \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Step 1: MD5 Verification
# =============================================================================
RUN --mount=type=bind,from=libero-installer,target=/mnt/installer \
    if [ ! -f "/mnt/installer/$LIBERO_SH" ]; then \
    echo "ERROR: Installer not found: /mnt/installer/$LIBERO_SH"; \
    echo "Check --build-context libero-installer=<path>"; \
    exit 1; \
    fi && \
    echo "Verifying MD5..." && \
    echo "$LIBERO_MD5  /mnt/installer/$LIBERO_SH" | md5sum -c - || \
    { echo "ERROR: MD5 mismatch!"; exit 1; }

# =============================================================================
# Step 2: Install Libero
# =============================================================================
RUN mkdir -p /usr/share/desktop-directories

RUN --mount=type=bind,from=libero-installer,target=/mnt/installer \
    cd /mnt/installer/ && \
    ./$LIBERO_SH \
    --accept-licenses \
    --accept-messages \
    --root /usr/local/microchip/Libero_SoC_2025.2 \
    --confirm-command install Libero_SoC SmartHLS PFSoC_MSS_Configurator Program_Debug MegaVault \
    CommonDir=/usr/local/microchip/common \
    --verbose

# Symlink Ubuntu certs to RHEL location
RUN mkdir -p /etc/pki/tls/certs && \
    ln -sf /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt

# =============================================================================
# Step 3: Compile snpslmd overlayfs workaround & wrapper
# =============================================================================
COPY snpslmd-workaround.c /usr/local/microchip/snpslmd-workaround.c
RUN gcc -ldl -shared -fPIC /usr/local/microchip/snpslmd-workaround.c -o /usr/local/microchip/Libero_SoC_2025.2/LicenseDaemons/snpslmd-workaround.so && \
    # Rename original binary
    mv /usr/local/microchip/Libero_SoC_2025.2/LicenseDaemons/snpslmd /usr/local/microchip/Libero_SoC_2025.2/LicenseDaemons/snpslmd_bin && \
    # Create wrapper
    echo '#!/bin/sh' > /usr/local/microchip/Libero_SoC_2025.2/LicenseDaemons/snpslmd && \
    echo 'export LD_PRELOAD=/usr/local/microchip/Libero_SoC_2025.2/LicenseDaemons/snpslmd-workaround.so' >> /usr/local/microchip/Libero_SoC_2025.2/LicenseDaemons/snpslmd && \
    echo 'exec /usr/local/microchip/Libero_SoC_2025.2/LicenseDaemons/snpslmd_bin "$@"' >> /usr/local/microchip/Libero_SoC_2025.2/LicenseDaemons/snpslmd && \
    chmod +x /usr/local/microchip/Libero_SoC_2025.2/LicenseDaemons/snpslmd

# =============================================================================
# Entrypoint — sets PATH, starts license daemon, then runs user command
# =============================================================================
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
