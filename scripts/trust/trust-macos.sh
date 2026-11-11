#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <cert.pem|cert.cer>"
  exit 1
fi

CERT="$1"
security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT"
echo "Installed self-signed publisher certificate into macOS System keychain."
