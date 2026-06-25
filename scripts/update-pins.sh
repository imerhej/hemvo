#!/usr/bin/env bash
# update-pins.sh
# Fetches the current SPKI-SHA256 hashes for the Supabase TLS certificate
# and prints the lines to paste into CertificatePinner.swift.
#
# Run this ~30 days before the current cert expires (or after Google renews it).
# Always ADD the new hash before REMOVING the old one so existing installs
# keep working during the App Store review + user-update rollout window.
#
# Usage:
#   chmod +x scripts/update-pins.sh
#   ./scripts/update-pins.sh

set -euo pipefail

HOST="tyfdsrxkswwwfmdkjknk.supabase.co"

echo "Fetching certificate chain from $HOST …"
echo ""

LEAF=$(echo | openssl s_client -servername "$HOST" -connect "$HOST":443 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | grep -v "PUBLIC KEY" | tr -d '\n' | base64 -d \
  | openssl dgst -sha256 -binary | base64)

INTERMEDIATE=$(echo | openssl s_client -servername "$HOST" -connect "$HOST":443 -showcerts 2>/dev/null \
  | awk '/-----BEGIN CERTIFICATE-----/{i++} i==2{print} /-----END CERTIFICATE-----/ && i==2{exit}' \
  | openssl x509 -pubkey -noout \
  | grep -v "PUBLIC KEY" | tr -d '\n' | base64 -d \
  | openssl dgst -sha256 -binary | base64)

EXPIRY=$(echo | openssl s_client -servername "$HOST" -connect "$HOST":443 2>/dev/null \
  | openssl x509 -noout -enddate | cut -d= -f2)

echo "Certificate expires: $EXPIRY"
echo ""
echo "Paste these into CertificatePinner.pinnedHashes:"
echo "    \"$LEAF\",  // *.supabase.co leaf (expires: $EXPIRY)"
echo "    \"$INTERMEDIATE\"   // Google Trust Services WE1 intermediate CA"
echo ""
echo "Steps:"
echo "  1. ADD the new hashes above to pinnedHashes (keep the old ones too)"
echo "  2. Ship an app update and wait for it to propagate (~2 weeks)"
echo "  3. REMOVE the old hashes in a follow-up release"
