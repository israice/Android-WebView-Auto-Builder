#!/bin/bash
# Release script for Android-WebView-Auto-Builder
# Usage: ./BACKEND/release.sh v0.0.24 "Release description"

set -e

VERSION=$1
DESCRIPTION=$2

if [ -z "$VERSION" ]; then
    echo "Usage: ./BACKEND/release.sh <version> [description]"
    echo "Example: ./BACKEND/release.sh v0.0.24 'Added new feature'"
    exit 1
fi

# Validate version format
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in format vX.Y.Z (e.g., v0.0.24)"
    exit 1
fi

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo "Error: You have uncommitted changes. Please commit or stash them first."
    exit 1
fi

# Set description if not provided
if [ -z "$DESCRIPTION" ]; then
    DESCRIPTION="Release $VERSION"
fi

echo "Creating release $VERSION..."

# Update VERSION.md
echo "$VERSION - $DESCRIPTION" >> VERSION.md

# Sync version to UI
if [ -f "TOOLS/sync_version.py" ]; then
    python3 TOOLS/sync_version.py || python TOOLS/sync_version.py
fi

# Git operations
git add VERSION.md FRONTEND/index.html 2>/dev/null || git add VERSION.md
git commit -m "$VERSION - $DESCRIPTION"
git tag -a "$VERSION" -m "$DESCRIPTION"

echo ""
echo "Release $VERSION created locally."
echo ""
echo "To publish the release, run:"
echo "  git push && git push --tags"
echo ""
echo "This will trigger GitHub Actions to:"
echo "  - Create a GitHub Release"
echo "  - Build and push Docker image to GHCR"
