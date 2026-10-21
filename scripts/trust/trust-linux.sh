#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <cert.pem|cert.crt>"
  exit 1
fi

CERT="$1"
DEST="/usr/local/share/ca-certificates/betterdesk-publisher.crt"
sudo cp "$CERT" "$DEST"
sudo update-ca-certificates
echo "Installed self-signed publisher certificate into Linux system trust store."
