#!/bin/bash
set -e

# Script to bump version in Xcode project
# Usage: ./bump-version.sh <marketing-version> [build-version]
# Example: ./bump-version.sh 1.0.1 10001

if [ -z "$1" ]; then
    echo "Error: Version number required"
    echo "Usage: $0 <version>"
    echo "Example: $0 1.0.1"
    exit 1
fi

MARKETING_VERSION="$1"
BUILD_VERSION="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$PROJECT_ROOT/aizen.xcodeproj/project.pbxproj"

# Validate marketing version format (should be semantic versioning: X.Y.Z)
if ! echo "$MARKETING_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: Invalid marketing version format. Use semantic versioning (e.g., 1.0.1)"
    exit 1
fi

# If build version not provided, use patch number from marketing version
if [ -z "$BUILD_VERSION" ]; then
    BUILD_VERSION=$(echo "$MARKETING_VERSION" | cut -d. -f3)
fi

echo "Bumping version to $MARKETING_VERSION (build $BUILD_VERSION)..."

# Check if project file exists
if [ ! -f "$PROJECT_FILE" ]; then
    echo "Error: project.pbxproj not found at $PROJECT_FILE"
    exit 1
fi

# Backup the project file
cp "$PROJECT_FILE" "$PROJECT_FILE.bak"

# Update MARKETING_VERSION (the user-visible version)
# This updates all instances in the project file
perl -i -pe "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $MARKETING_VERSION;/g" "$PROJECT_FILE"

# Update CURRENT_PROJECT_VERSION (the build number)
perl -i -pe "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $BUILD_VERSION;/g" "$PROJECT_FILE"

# Verify the changes
if grep -q "MARKETING_VERSION = $MARKETING_VERSION;" "$PROJECT_FILE"; then
    echo "✅ Version updated to $MARKETING_VERSION (build $BUILD_VERSION)"
    rm "$PROJECT_FILE.bak"
else
    echo "❌ Failed to update version"
    mv "$PROJECT_FILE.bak" "$PROJECT_FILE"
    exit 1
fi

echo ""
echo "Changes made:"
echo "  MARKETING_VERSION = $MARKETING_VERSION"
echo "  CURRENT_PROJECT_VERSION = $BUILD_VERSION"
