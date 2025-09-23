#!/bin/bash

# Apple Intelligence API Release Publisher
# Creates an optimized release build and packages it as tar.gz

set -e  # Exit on any error

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="AppleIntelligenceAPI"
RELEASE_DIR="${PROJECT_DIR}/releases"
TEMP_BUILD_DIR="/tmp/${PROJECT_NAME}-build-$$"
ARCHIVE_PATH="${TEMP_BUILD_DIR}/${PROJECT_NAME}.xcarchive"
EXPORT_PATH="${TEMP_BUILD_DIR}/export"
FINAL_TARBALL="${RELEASE_DIR}/${PROJECT_NAME}-Release.tar.gz"

echo "🚀 Starting Apple Intelligence API release build..."
echo "📂 Project directory: ${PROJECT_DIR}"

# Create releases directory if it doesn't exist
echo "📁 Creating releases directory..."
mkdir -p "${RELEASE_DIR}"

# Clean up any existing build artifacts
echo "🧹 Cleaning up previous builds..."
rm -rf "${TEMP_BUILD_DIR}"
rm -f "${FINAL_TARBALL}"

# Create temporary build directory
mkdir -p "${TEMP_BUILD_DIR}"

# Clean and build the archive
echo "🔨 Building optimized release archive..."
cd "${PROJECT_DIR}"
xcodebuild clean > /dev/null 2>&1

xcodebuild -project "${PROJECT_NAME}.xcodeproj" \
           -scheme "${PROJECT_NAME}" \
           -configuration Release \
           -archivePath "${ARCHIVE_PATH}" \
           archive \
           SWIFT_OPTIMIZATION_LEVEL="-Osize" \
           DEPLOYMENT_POSTPROCESSING=YES \
           STRIP_INSTALLED_PRODUCT=YES \
           COPY_PHASE_STRIP=NO \
           > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Archive build failed!"
    rm -rf "${TEMP_BUILD_DIR}"
    exit 1
fi

echo "✅ Archive build completed successfully"

# Create export options plist
EXPORT_PLIST="${TEMP_BUILD_DIR}/export-options.plist"
cat > "${EXPORT_PLIST}" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>
EOF

# Export the app
echo "📦 Exporting application..."
xcodebuild -exportArchive \
           -archivePath "${ARCHIVE_PATH}" \
           -exportPath "${EXPORT_PATH}" \
           -exportOptionsPlist "${EXPORT_PLIST}" \
           > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Export failed!"
    rm -rf "${TEMP_BUILD_DIR}"
    exit 1
fi

echo "✅ Export completed successfully"

# Create the tar.gz file
echo "📋 Creating tar.gz archive..."
cd "${EXPORT_PATH}"
tar -czf "${FINAL_TARBALL}" "${PROJECT_NAME}.app"

if [ $? -ne 0 ]; then
    echo "❌ Failed to create tar.gz!"
    rm -rf "${TEMP_BUILD_DIR}"
    exit 1
fi

# Get file size
FILE_SIZE=$(du -h "${FINAL_TARBALL}" | cut -f1)

# Clean up temporary files
rm -rf "${TEMP_BUILD_DIR}"

echo "✅ Release build completed successfully!"
echo ""
echo "📊 Build Summary:"
echo "   • File: ${PROJECT_NAME}-Release.tar.gz"
echo "   • Size: ${FILE_SIZE}"
echo "   • Location: ${RELEASE_DIR}/"
echo ""
echo "🎉 Ready for distribution!"