#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <path_to_license_file>"
    exit 1
fi

LICENSE_FILE="$1"

if [ ! -f "$LICENSE_FILE" ]; then
    echo "Error: License file '$LICENSE_FILE' not found."
    exit 1
fi

echo "Parsing license file..."

# Extract hostname and MAC from the SERVER line
# e.g., SERVER fpga-server a1b2c3d4e5f6 1702
LICENSE_HOST=$(awk '/^SERVER/{print $2; exit}' "$LICENSE_FILE")
LICENSE_MAC_RAW=$(awk '/^SERVER/{print tolower($3); exit}' "$LICENSE_FILE")

if [ -z "$LICENSE_HOST" ] || [ -z "$LICENSE_MAC_RAW" ]; then
    echo "Error: Could not parse SERVER line in license file."
    exit 1
fi

# Format MAC address from e897447848b5 to e8:97:44:78:48:b5
LICENSE_MAC=$(echo "$LICENSE_MAC_RAW" | sed 's/\(..\)/\1:/g; s/:$//')

echo "Starting libero container..."
echo "  Hostname: $LICENSE_HOST"
echo "  MAC:      $LICENSE_MAC"

docker run -it --rm \
    --hostname "$LICENSE_HOST" \
    --mac-address "$LICENSE_MAC" \
    -v "$(realpath "$LICENSE_FILE")":/usr/local/microchip/license \
    -v "$(pwd)":/workspace \
    -w /workspace \
    libero:2025.2 bash
