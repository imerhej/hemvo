#!/bin/bash
# Usage: ./scripts/bump-version.sh [major|minor|patch]
# Bumps the marketing version (CFBundleShortVersionString) in the Xcode project.
# The build number (CFBundleVersion) is managed separately via agvtool and
# auto-increments by one on every Archive (see the "Version + Build Number
# (agvtool)" Run Script build phase).
#
# Examples:
#   ./scripts/bump-version.sh patch   1.1.0 → 1.1.1
#   ./scripts/bump-version.sh minor   1.1.0 → 1.2.0
#   ./scripts/bump-version.sh major   1.1.0 → 2.0.0

set -e

cd "$(dirname "$0")/.."

TYPE=${1:-patch}

CURRENT=$(xcrun agvtool what-marketing-version -terse 2>/dev/null | head -1 | tr -d '[:space:]')
if [ -z "$CURRENT" ]; then
    echo "error: could not read current marketing version" >&2
    exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
MAJOR=${MAJOR:-1}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}

case "$TYPE" in
    major)
        MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor)
        MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch)
        PATCH=$((PATCH + 1)) ;;
    *)
        echo "Usage: $0 [major|minor|patch]" >&2
        exit 1 ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
xcrun agvtool new-marketing-version "$NEW_VERSION" > /dev/null

echo "Version bumped: ${CURRENT} → ${NEW_VERSION}"
echo "Next: commit and tag — git commit -am \"chore: bump version to ${NEW_VERSION}\" && git tag \"v${NEW_VERSION}\""
