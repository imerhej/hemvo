#!/bin/bash
# Usage: ./scripts/bump-version.sh [major|minor|patch]
# Bumps the marketing version (MARKETING_VERSION) in the Xcode project.
# The build number (CFBundleVersion) is managed separately via agvtool and
# auto-increments by one on every Archive (see the "Version + Build Number
# (agvtool)" Run Script build phase).
#
# Examples:
#   ./scripts/bump-version.sh patch   1.1.0 → 1.1.1
#   ./scripts/bump-version.sh minor   1.1.0 → 1.2.0
#   ./scripts/bump-version.sh major   1.1.0 → 2.0.0
#
# NOTE: this deliberately does NOT use agvtool for the marketing version.
# Info.plist stores CFBundleShortVersionString as the literal "$(MARKETING_VERSION)"
# build-setting reference, so `agvtool what-marketing-version` reports
# `"<path>/Info.plist"=$(MARKETING_VERSION)` rather than a version string — and
# feeding that back to `agvtool new-marketing-version` truncates project.pbxproj
# to zero bytes. MARKETING_VERSION in project.pbxproj is the source of truth.

set -euo pipefail

cd "$(dirname "$0")/.."

PBXPROJ="Hemvo.xcodeproj/project.pbxproj"
TYPE=${1:-patch}

case "$TYPE" in
    major|minor|patch) ;;
    *) echo "Usage: $0 [major|minor|patch]" >&2; exit 1 ;;
esac

# Read the app target's marketing version. Test targets sit at 1.0, so take the
# highest distinct value — the app target is always ahead of them.
CURRENT=$(grep -oE 'MARKETING_VERSION = [0-9]+(\.[0-9]+)*;' "$PBXPROJ" \
    | sed -E 's/MARKETING_VERSION = (.*);/\1/' \
    | sort -V | tail -1)

if ! [[ "$CURRENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: could not read a valid marketing version from $PBXPROJ (got '${CURRENT}')" >&2
    exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$TYPE" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

TMP=$(mktemp)
sed "s/MARKETING_VERSION = ${CURRENT};/MARKETING_VERSION = ${NEW_VERSION};/g" "$PBXPROJ" > "$TMP"

# Never let a failed rewrite land: the project file must stay non-empty and must
# actually contain the new version before we overwrite the original.
if [ ! -s "$TMP" ] || ! grep -q "MARKETING_VERSION = ${NEW_VERSION};" "$TMP"; then
    rm -f "$TMP"
    echo "error: rewrite failed — $PBXPROJ left untouched" >&2
    exit 1
fi
mv "$TMP" "$PBXPROJ"

echo "Version bumped: ${CURRENT} → ${NEW_VERSION}"
echo "Next: commit and tag — git commit -am \"chore: bump version to ${NEW_VERSION}\" && git tag \"v${NEW_VERSION}\""
