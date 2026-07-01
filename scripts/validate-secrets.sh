#!/usr/bin/env bash
# validate-secrets.sh
# Validates AppSecrets.swift before the Xcode build proceeds.
# Add as an Xcode "Run Script" build phase (before "Compile Sources"):
#
#   Shell: /bin/bash
#   Script: "${SRCROOT}/scripts/validate-secrets.sh"
#
# The build will fail with a clear error if supabaseURL is still a placeholder
# or is not a well-formed HTTPS URL, preventing misconfigured binaries from
# reaching the App Store.

set -euo pipefail

SECRETS_FILE="${SRCROOT}/Hemvo/AppSecrets.swift"

if [ ! -f "$SECRETS_FILE" ]; then
    echo "error: AppSecrets.swift not found at ${SECRETS_FILE}." \
         "Copy AppSecrets.swift.example and fill in your Supabase credentials."
    exit 1
fi

# Extract the supabaseURL value
URL=$(grep 'supabaseURL' "$SECRETS_FILE" | grep -v 'supabaseBaseURL' | \
      sed 's/.*= *"\(.*\)".*/\1/' | tr -d '[:space:]')

if [ -z "$URL" ]; then
    echo "error: Could not parse supabaseURL from AppSecrets.swift."
    exit 1
fi

# Reject placeholder values
if [[ "$URL" == *"YOUR_PROJECT"* ]] || [[ "$URL" == *"example"* ]]; then
    echo "error: AppSecrets.supabaseURL is still a placeholder: \"${URL}\"." \
         "Fill in your real Supabase project URL before building."
    exit 1
fi

# Require https:// scheme and a non-empty host
if [[ ! "$URL" =~ ^https://[^/]+\. ]]; then
    echo "error: AppSecrets.supabaseURL is not a valid HTTPS URL: \"${URL}\"."
    exit 1
fi

echo "note: AppSecrets.supabaseURL is valid: ${URL}"
