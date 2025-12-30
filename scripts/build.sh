#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# Default configuration
CONFIGURATION="Release"
ARCH="arm64"
CLEAN=false
SCHEME="aizen"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--debug)
            CONFIGURATION="Debug"
            shift
            ;;
        -r|--release)
            CONFIGURATION="Release"
            shift
            ;;
        -n|--nightly)
            SCHEME="aizen nightly"
            shift
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -d, --debug     Build Debug configuration (default: Release)"
            echo "  -r, --release   Build Release configuration"
            echo "  -n, --nightly   Build nightly/development version (default: release)"
            echo "  -c, --clean     Clean before building"
            echo "  -h, --help      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                         # Build Release version"
            echo "  $0 --debug                 # Build Debug version"
            echo "  $0 --nightly               # Build nightly Release version"
            echo "  $0 --nightly --debug       # Build nightly Debug version"
            echo "  $0 --release --clean       # Clean and build Release"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Determine app name and version type
if [[ "$SCHEME" == "aizen nightly" ]]; then
    VERSION_TYPE="nightly (development)"
    APP_NAME="aizen nightly.app"
else
    VERSION_TYPE="release"
    APP_NAME="aizen.app"
fi

echo -e "${GREEN}=== Building aizen ===${NC}"
echo "Version: $VERSION_TYPE"
echo "Configuration: $CONFIGURATION"
echo "Architecture: $ARCH"
echo ""

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo -e "${YELLOW}Cleaning build folder...${NC}"
    xcodebuild clean -scheme "$SCHEME" -configuration "$CONFIGURATION"
    echo ""
fi

# Build
echo -e "${YELLOW}Building...${NC}"
xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -arch "$ARCH" \
    build 2>&1 | grep -E "error:|warning:|failed|succeeded"

# Check if build succeeded
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    APP_PATH="$PROJECT_DIR/build/$CONFIGURATION/$APP_NAME"
    echo ""
    echo -e "${GREEN}✓ Build succeeded!${NC}"
    echo -e "Output: ${YELLOW}$APP_PATH${NC}"
    echo ""
    echo "To run the app:"
    echo -e "  ${YELLOW}open ./build/$CONFIGURATION/$APP_NAME${NC}"
else
    echo ""
    echo -e "${RED}✗ Build failed!${NC}"
    exit 1
fi
