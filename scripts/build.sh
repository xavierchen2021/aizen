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
            echo "  -c, --clean     Clean before building"
            echo "  -h, --help      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Build Release version"
            echo "  $0 --debug            # Build Debug version"
            echo "  $0 --release --clean  # Clean and build Release"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}=== Building aizen ===${NC}"
echo "Configuration: $CONFIGURATION"
echo "Architecture: $ARCH"
echo ""

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo -e "${YELLOW}Cleaning build folder...${NC}"
    xcodebuild clean -scheme aizen -configuration "$CONFIGURATION"
    echo ""
fi

# Build
echo -e "${YELLOW}Building...${NC}"
xcodebuild \
    -scheme aizen \
    -configuration "$CONFIGURATION" \
    -arch "$ARCH" \
    build

# Check if build succeeded
if [ $? -eq 0 ]; then
    APP_PATH="$PROJECT_DIR/build/$CONFIGURATION/aizen.app"
    echo ""
    echo -e "${GREEN}✓ Build succeeded!${NC}"
    echo -e "Output: ${YELLOW}$APP_PATH${NC}"
    echo ""
    echo "To run the app:"
    echo -e "  ${YELLOW}open ./build/$CONFIGURATION/aizen.app${NC}"
else
    echo ""
    echo -e "${RED}✗ Build failed!${NC}"
    exit 1
fi
