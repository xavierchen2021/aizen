#!/bin/bash
set -e

LIBGIT2_VERSION="v1.9.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/../Vendor/libgit2"
TMP_DIR="/tmp/libgit2-build-$$"

echo "Building libgit2 $LIBGIT2_VERSION..."

# Cleanup any previous build
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Clone
echo "Cloning libgit2..."
git clone --depth 1 --branch $LIBGIT2_VERSION https://github.com/libgit2/libgit2.git "$TMP_DIR/libgit2"
cd "$TMP_DIR/libgit2"

# Build universal binary
echo "Building universal binary (arm64 + x86_64)..."
mkdir build && cd build
cmake .. \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_SSH=OFF \
    -DUSE_HTTPS=SecureTransport \
    -DBUILD_TESTS=OFF \
    -DBUILD_CLI=OFF \
    -DUSE_BUNDLED_ZLIB=ON

cmake --build . --config Release

# Verify universal binary
echo "Verifying universal binary..."
lipo -info libgit2.a

# Copy to Vendor
echo "Copying to $OUTPUT_DIR..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/lib"
mkdir -p "$OUTPUT_DIR/include"
cp libgit2.a "$OUTPUT_DIR/lib/"
cp -r ../include/git2 "$OUTPUT_DIR/include/"
cp ../include/git2.h "$OUTPUT_DIR/include/"

# Create module.modulemap
cat > "$OUTPUT_DIR/include/module.modulemap" << 'EOF'
module Clibgit2 [system] {
    header "git2.h"
    link "git2"
    link "z"
    link "iconv"
    export *
}
EOF

# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "libgit2 $LIBGIT2_VERSION built successfully!"
echo "Location: $OUTPUT_DIR"
echo ""
echo "Files:"
ls -la "$OUTPUT_DIR/lib/"
echo ""
echo "Next steps:"
echo "1. Add Vendor/libgit2/lib/libgit2.a to 'Link Binary With Libraries'"
echo "2. Add \$(PROJECT_DIR)/Vendor/libgit2/include to 'Header Search Paths'"
echo "3. Add \$(PROJECT_DIR)/Vendor/libgit2/include to 'Import Paths'"
echo "4. Link frameworks: Security.framework, CoreFoundation.framework"
